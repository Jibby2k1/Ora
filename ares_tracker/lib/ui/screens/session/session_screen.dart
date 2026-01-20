import 'package:flutter/material.dart';

import 'dart:async';

import '../../../core/command_bus/command.dart';
import '../../../core/command_bus/dispatcher.dart';
import '../../../core/command_bus/session_command_reducer.dart';
import '../../../core/command_bus/undo_redo.dart';
import '../../../core/voice/llm_parser.dart';
import '../../../core/voice/voice_models.dart';
import '../../../core/voice/nlu_parser.dart';
import '../../../core/voice/stt.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/models/last_logged_set.dart';
import '../../../domain/models/session_context.dart';
import '../../../domain/models/session_exercise_info.dart';
import '../../../domain/services/exercise_matcher.dart';
import '../../widgets/confirmation_card/confirmation_card.dart';
import '../../widgets/exercise_modal/exercise_modal.dart';
import '../../widgets/timer_bar/timer_bar.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.contextData});

  final SessionContext contextData;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _PendingLogSet {
  _PendingLogSet({required this.exerciseInfo, required this.reps, this.partials, this.rpe, this.rir});

  final SessionExerciseInfo exerciseInfo;
  final int reps;
  final int? partials;
  final double? rpe;
  final double? rir;
}


class _SessionScreenState extends State<SessionScreen> {
  final _voiceController = TextEditingController();
  final _parser = NluParser();
  final _llmParser = LlmParser();
  late final WorkoutRepo _workoutRepo;
  late final ExerciseMatcher _matcher;
  late final ExerciseRepo _exerciseRepo;
  late final Map<int, SessionExerciseInfo> _exerciseById;
  late final Map<int, SessionExerciseInfo> _sessionExerciseById;
  late final Map<String, int> _cacheRefToExerciseId;
  late final CommandDispatcher _dispatcher;
  late final List<SessionExerciseInfo> _sessionExercises;
  final UndoRedoStack _undoRedo = UndoRedoStack();
  Timer? _restTimer;
  int _restRemaining = 0;
  bool _listening = false;
  String? _voicePartial;

  _PendingLogSet? _pending;
  LastLoggedSet? _lastLogged;
  SessionExerciseInfo? _lastExerciseInfo;
  String? _prompt;
  bool _showVoiceDebug = false;
  String? _debugTranscript;
  String? _debugRule;
  String? _debugLlm;
  String? _debugDecision;
  String? _debugParts;
  String? _debugLlmRaw;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _workoutRepo = WorkoutRepo(db);
    _exerciseRepo = ExerciseRepo(db);
    _matcher = ExerciseMatcher(_exerciseRepo);
    _sessionExercises = List<SessionExerciseInfo>.from(widget.contextData.exercises);
    _exerciseById = {for (final info in _sessionExercises) info.exerciseId: info};
    _sessionExerciseById = {for (final info in _sessionExercises) info.sessionExerciseId: info};
    _cacheRefToExerciseId = {};
    _dispatcher = CommandDispatcher(
      SessionCommandReducer(
        workoutRepo: _workoutRepo,
        sessionExerciseById: _sessionExerciseById,
      ).call,
    );
    Future.microtask(() => _llmParser.initialize());
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleVoiceInput(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    _setVoiceDebug(transcript: trimmed);

    final pending = _pending;
    if (pending != null) {
      final weight = double.tryParse(trimmed) ?? _parser.parseWeightOnly(trimmed);
      if (weight != null) {
        await _logSet(pending.exerciseInfo, reps: pending.reps, weight: weight, partials: pending.partials, rpe: pending.rpe, rir: pending.rir);
        setState(() {
          _pending = null;
          _prompt = null;
        });
        return;
      }
    }

    final parsed = _parser.parse(trimmed);
    if (parsed != null) {
      if (_shouldTryLlm(parsed)) {
        final llmCommand = await _runLlmParse(trimmed);
        if (llmCommand != null) {
          final normalized = _normalizeLogSetFromTranscript(llmCommand, trimmed);
          if (_preferLlm(parsed, normalized)) {
            _setVoiceDebug(
              rule: _describeCommand(parsed),
              llm: _describeCommand(normalized),
              decision: 'LLM preferred over rule',
            );
            await _handleParsedCommand(normalized);
            return;
          }
        }
      }
      _setVoiceDebug(
        rule: _describeCommand(parsed),
        decision: 'Rule-based used',
      );
      await _handleParsedCommand(_normalizeLogSetFromTranscript(parsed, trimmed));
      return;
    }

    final llmCommand = await _runLlmParse(trimmed);
    if (llmCommand != null) {
      _setVoiceDebug(
        llm: _describeCommand(llmCommand),
        decision: 'LLM used',
      );
      await _handleParsedCommand(_normalizeLogSetFromTranscript(llmCommand, trimmed));
      return;
    }

    final partsOnly = _parser.parseLogPartsWithOrderHints(trimmed);
    if (_lastExerciseInfo != null && partsOnly.reps != null) {
      final weight = partsOnly.weight;
      if (weight == null) {
        final lastWeight = await _workoutRepo.getLatestWeightForSessionExercise(
            _lastExerciseInfo!.sessionExerciseId);
        if (lastWeight == null) {
          setState(() {
            _pending = _PendingLogSet(
              exerciseInfo: _lastExerciseInfo!,
              reps: partsOnly.reps!,
              partials: partsOnly.partials,
              rpe: partsOnly.rpe,
              rir: partsOnly.rir,
            );
            _prompt = 'What weight?';
          });
          return;
        }
        await _logSet(
          _lastExerciseInfo!,
          reps: partsOnly.reps!,
          weight: lastWeight,
          partials: partsOnly.partials,
          rpe: partsOnly.rpe,
          rir: partsOnly.rir,
        );
        return;
      }
      await _logSet(
        _lastExerciseInfo!,
        reps: partsOnly.reps!,
        weight: weight,
        partials: partsOnly.partials,
        rpe: partsOnly.rpe,
        rir: partsOnly.rir,
      );
      return;
    }

    final fallbackInfo = _guessSessionExercise(trimmed);
    if (fallbackInfo != null) {
      final parts = _parser.parseLogPartsWithOrderHints(trimmed);
      if (parts.reps == null) {
        _showMessage('Need reps for "${fallbackInfo.exerciseName}".');
        return;
      }
      final weight = parts.weight;
      if (weight == null) {
        final lastWeight = await _workoutRepo.getLatestWeightForSessionExercise(
            fallbackInfo.sessionExerciseId);
        if (lastWeight == null) {
          setState(() {
            _pending = _PendingLogSet(
              exerciseInfo: fallbackInfo,
              reps: parts.reps!,
              partials: parts.partials,
              rpe: parts.rpe,
              rir: parts.rir,
            );
            _prompt = 'What weight?';
          });
          return;
        }
        await _logSet(
          fallbackInfo,
          reps: parts.reps!,
          weight: lastWeight,
          partials: parts.partials,
          rpe: parts.rpe,
          rir: parts.rir,
        );
        return;
      }
      await _logSet(
        fallbackInfo,
        reps: parts.reps!,
        weight: weight,
        partials: parts.partials,
        rpe: parts.rpe,
        rir: parts.rir,
      );
      return;
    }

    if (_llmParser.lastError != null) {
      _setVoiceDebug(
        decision: 'LLM failed: ${_llmParser.lastError}',
      );
      _showMessage('LLM parse failed: ${_llmParser.lastError}');
      return;
    }

    _setVoiceDebug(decision: 'No parse matched');
    _showMessage('Could not parse command: "$trimmed"');
  }

  Future<void> _handleParsedCommand(NluCommand parsed) async {
    switch (parsed.type) {
      case 'undo':
        await _undo();
        return;
      case 'redo':
        await _redo();
        return;
      case 'switch':
        if (parsed.exerciseRef == null) return;
        final exerciseInfo = await _resolveExercise(parsed.exerciseRef!);
        if (exerciseInfo != null) {
          _openExerciseModal(exerciseInfo);
        }
        return;
      case 'show_stats':
        _showMessage('Stats view not in demo.');
        return;
      case 'log_set':
        final ref = parsed.exerciseRef;
        final exerciseInfo = (ref == null || ref.trim().isEmpty)
            ? _lastExerciseInfo
            : await _resolveExercise(ref);
        if (exerciseInfo == null || parsed.reps == null) {
          _showMessage('Need exercise and reps.');
          return;
        }

        final weight = parsed.weight;
        if (weight == null) {
          final lastWeight = await _workoutRepo.getLatestWeightForSessionExercise(exerciseInfo.sessionExerciseId);
          if (lastWeight == null) {
            setState(() {
              _pending = _PendingLogSet(
                exerciseInfo: exerciseInfo,
                reps: parsed.reps!,
                partials: parsed.partials,
                rpe: parsed.rpe,
                rir: parsed.rir,
              );
              _prompt = 'What weight?';
            });
            return;
          }
          await _logSet(exerciseInfo, reps: parsed.reps!, weight: lastWeight, partials: parsed.partials, rpe: parsed.rpe, rir: parsed.rir);
          return;
        }
        await _logSet(exerciseInfo, reps: parsed.reps!, weight: weight, partials: parsed.partials, rpe: parsed.rpe, rir: parsed.rir);
        return;
    }
  }

  Future<NluCommand?> _runLlmParse(String transcript) async {
    setState(() {
      _prompt = 'Thinking...';
    });
    final result = await _llmParser.parse(transcript);
    setState(() {
      _prompt = null;
    });
    if (_llmParser.lastRawOutput != null) {
      _setVoiceDebug(llmRaw: _llmParser.lastRawOutput);
    }
    return result;
  }

  bool _shouldTryLlm(NluCommand parsed) {
    if (!_llmParser.isReady) return false;
    if (_commandQuality(parsed) < 2) return true;
    if (parsed.type == 'log_set' && !_hasSessionMatch(parsed.exerciseRef)) {
      return true;
    }
    if (parsed.type == 'log_set') {
      return true;
    }
    return false;
  }

  bool _preferLlm(NluCommand rule, NluCommand llm) {
    final ruleQuality = _commandQuality(rule);
    final llmQuality = _commandQuality(llm);
    if (llmQuality > ruleQuality) return true;
    if (llmQuality == ruleQuality &&
        llm.type == 'log_set' &&
        _hasSessionMatch(llm.exerciseRef) &&
        !_hasSessionMatch(rule.exerciseRef)) {
      return true;
    }
    return false;
  }

  int _commandQuality(NluCommand command) {
    switch (command.type) {
      case 'undo':
      case 'redo':
      case 'rest':
        return 2;
      case 'switch':
      case 'show_stats':
        return command.exerciseRef == null ? 1 : 2;
      case 'log_set':
        if (command.exerciseRef == null || command.reps == null) return 1;
        return 2;
    }
    return 0;
  }

  bool _hasSessionMatch(String? exerciseRef) {
    if (exerciseRef == null || exerciseRef.trim().isEmpty) return false;
    return _matchSessionExercises(exerciseRef).isNotEmpty;
  }

  void _setVoiceDebug({
    String? transcript,
    String? rule,
    String? llm,
    String? decision,
    String? parts,
    String? llmRaw,
  }) {
    final hints = _parser.parseLogPartsWithOrderHints(_debugTranscript ?? transcript ?? '');
    setState(() {
      _debugTranscript = transcript ?? _debugTranscript;
      _debugRule = rule ?? _debugRule;
      _debugLlm = llm ?? _debugLlm;
      _debugDecision = decision ?? _debugDecision;
      _debugParts = parts ??
          'hints: weight=${hints.weight}, reps=${hints.reps}, unit=${hints.weightUnit}, partials=${hints.partials}';
      _debugLlmRaw = llmRaw ?? _debugLlmRaw;
    });
  }

  String _describeCommand(NluCommand command) {
    return 'type=${command.type} ex=${command.exerciseRef} weight=${command.weight} '
        'unit=${command.weightUnit} reps=${command.reps} partials=${command.partials} '
        'rpe=${command.rpe} rir=${command.rir} rest=${command.restSeconds}';
  }

  NluCommand _normalizeLogSetFromTranscript(NluCommand command, String transcript) {
    if (command.type != 'log_set') return command;
    final parts = _parser.parseLogPartsWithOrderHints(transcript);
    var weight = command.weight ?? parts.weight;
    var reps = command.reps ?? parts.reps;
    final normalized = _parser.normalize(transcript);
    final hasRepsKeyword = normalized.contains('reps');
    final hasUnitKeyword = RegExp(r'\b(kg|kilograms|kilo|lbs|lb|pounds)\b')
        .hasMatch(normalized);
    if (hasRepsKeyword && hasUnitKeyword && parts.reps != null && parts.weight != null) {
      weight = parts.weight;
      reps = parts.reps;
    }
    if (weight != null &&
        reps != null &&
        parts.weight != null &&
        parts.reps != null) {
      final partsWeight = parts.weight!;
      final partsReps = parts.reps!;
      final swapped = weight < reps && partsWeight > partsReps;
      final extreme = reps >= 80 && partsReps < reps && partsWeight > partsReps;
      if (swapped || extreme) {
        weight = partsWeight;
        reps = partsReps;
      }
    }
    return NluCommand(
      type: command.type,
      exerciseRef: command.exerciseRef,
      weight: weight,
      weightUnit: command.weightUnit ?? parts.weightUnit,
      reps: reps,
      partials: command.partials ?? parts.partials,
      rpe: command.rpe ?? parts.rpe,
      rir: command.rir ?? parts.rir,
      restSeconds: command.restSeconds,
    );
  }

  Future<SessionExerciseInfo?> _resolveExercise(String exerciseRef) async {
    final normalized = _matcher.normalize(exerciseRef);
    final cached = _cacheRefToExerciseId[normalized];
    if (cached != null) {
      final info = _exerciseById[cached];
      if (info != null) return info;
      _cacheRefToExerciseId.remove(normalized);
    }

    final sessionMatches = _matchSessionExercises(exerciseRef);
    if (sessionMatches.isNotEmpty) {
      final info = sessionMatches.length == 1
          ? sessionMatches.first
          : await _showSessionDisambiguation(sessionMatches);
      if (info == null) return null;
      _cacheRefToExerciseId[normalized] = info.exerciseId;
      return info;
    }

    final match = await _matcher.match(exerciseRef);
    if (match.isNone) {
      _showMessage('No exercise match.');
      return null;
    }

    final ExerciseMatch? selected =
        match.isSingle ? match.matches.first : await _showDisambiguation(match.matches);
    if (selected == null) return null;

    final existing = _exerciseById[selected.id];
    if (existing != null) {
      _cacheRefToExerciseId[normalized] = selected.id;
      return existing;
    }

    final add = await _confirmAddExercise(selected.name);
    if (!add) return null;

    final added = await _addExerciseToSession(selected);
    if (added == null) return null;
    _cacheRefToExerciseId[normalized] = selected.id;
    return added;
  }

  Future<void> _logSet(
    SessionExerciseInfo info, {
    required int reps,
    double? weight,
    int? partials,
    double? rpe,
    double? rir,
  }) async {
    final result = await _dispatcher.dispatch(
      LogSetEntry(
        sessionExerciseId: info.sessionExerciseId,
        weightUnit: 'lb',
        weightMode: info.weightModeDefault,
        weight: weight,
        reps: reps,
        partials: partials,
        rpe: rpe,
        rir: rir,
      ),
    );
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    final latest = await _workoutRepo.getLatestSetForSessionExercise(info.sessionExerciseId);
    final setsForExercise = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    final role = latest?['set_role'] as String? ?? 'TOP';
    final isAmrap = (latest?['is_amrap'] as int? ?? 0) == 1;
    setState(() {
      _lastLogged = LastLoggedSet(
        exerciseName: info.exerciseName,
        reps: reps,
        weight: weight,
        role: role,
        isAmrap: isAmrap,
        sessionSetCount: setsForExercise.length,
      );
      _lastExerciseInfo = info;
      _prompt = null;
      _pending = null;
    });
  }

  Future<void> _updateSet(int id, {double? weight, int? reps, int? partials, double? rpe, double? rir}) async {
    final result = await _dispatcher.dispatch(
      UpdateSetEntry(
        id: id,
        weight: weight,
        reps: reps,
        partials: partials,
        rpe: rpe,
        rir: rir,
      ),
    );
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    setState(() {});
  }

  Future<void> _undo() async {
    final cmd = _undoRedo.popUndo();
    if (cmd == null) return;
    final result = await _dispatcher.dispatch(cmd);
    if (result.inverse != null) {
      _undoRedo.pushRedo(result.inverse!);
    }
    setState(() {});
  }

  Future<void> _redo() async {
    final cmd = _undoRedo.popRedo();
    if (cmd == null) return;
    final result = await _dispatcher.dispatch(cmd);
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    setState(() {});
  }

  void _startRestTimer([int seconds = 120]) {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = seconds;
    });
    _restTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_restRemaining <= 1) {
        timer.cancel();
        setState(() {
          _restRemaining = 0;
        });
      } else {
        setState(() {
          _restRemaining -= 1;
        });
      }
    });
  }

  void _stopRestTimer() {
    _restTimer?.cancel();
    setState(() {
      _restRemaining = 0;
    });
  }

  Future<void> _runVoice() async {
    if (_listening) {
      await _stopVoiceListening();
      return;
    }
    if (!SpeechToTextEngine.instance.isAvailable) {
      final text = await _promptVoiceText();
      if (text == null || text.trim().isEmpty) return;
      await _handleVoiceInput(text);
      return;
    }
    await _startVoiceListening();
  }

  Future<void> _startVoiceListening() async {
    if (_listening) return;
    setState(() {
      _listening = true;
      _voicePartial = null;
    });
    try {
      await SpeechToTextEngine.instance.startListening(
        onPartial: (text) {
          setState(() => _voicePartial = text);
        },
        onResult: (text) async {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _voicePartial = null;
          });
          await _handleVoiceInput(text);
        },
        onError: (error) {
          if (!mounted) return;
          setState(() {
            _listening = false;
            _voicePartial = null;
          });
          _showMessage('Voice error: $error');
        },
      );
    } catch (e) {
      setState(() {
        _listening = false;
        _voicePartial = null;
      });
      _showMessage('Voice unavailable: $e');
    }
  }

  Future<void> _stopVoiceListening() async {
    await SpeechToTextEngine.instance.stopListening();
    setState(() {
      _listening = false;
      _voicePartial = null;
    });
  }

  Future<String?> _promptVoiceText() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Voice input (fallback)'),
          content: TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Type command'),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(controller.text.trim()), child: const Text('Send')),
          ],
        );
      },
    );
    return result;
  }

  Future<ExerciseMatch?> _showDisambiguation(List<ExerciseMatch> matches) async {
    return showModalBottomSheet<ExerciseMatch>(
      context: context,
      builder: (context) {
        return ListView.separated(
          shrinkWrap: true,
          itemCount: matches.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final match = matches[index];
            return ListTile(
              title: Text(match.name),
              onTap: () => Navigator.of(context).pop(match),
            );
          },
        );
      },
    );
  }

  Future<SessionExerciseInfo?> _showSessionDisambiguation(
      List<SessionExerciseInfo> matches) async {
    return showModalBottomSheet<SessionExerciseInfo>(
      context: context,
      builder: (context) {
        return ListView.separated(
          shrinkWrap: true,
          itemCount: matches.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final match = matches[index];
            return ListTile(
              title: Text(match.exerciseName),
              subtitle: const Text('In current session'),
              onTap: () => Navigator.of(context).pop(match),
            );
          },
        );
      },
    );
  }

  Future<bool> _confirmAddExercise(String name) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Add to session?'),
        content: Text('$name is not in this session. Add it now?'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Add')),
        ],
      ),
    );
    return result ?? false;
  }

  Future<SessionExerciseInfo?> _addExerciseToSession(ExerciseMatch match) async {
    final row = await _exerciseRepo.getById(match.id);
    if (row == null) return null;
    final orderIndex = _sessionExercises.length;
    final sessionExerciseId = await _workoutRepo.addSessionExercise(
      workoutSessionId: widget.contextData.sessionId,
      exerciseId: match.id,
      orderIndex: orderIndex,
    );
    final info = SessionExerciseInfo(
      sessionExerciseId: sessionExerciseId,
      exerciseId: match.id,
      exerciseName: row['canonical_name'] as String? ?? match.name,
      weightModeDefault: row['weight_mode_default'] as String? ?? 'TOTAL',
      planBlocks: const [],
    );
    setState(() {
      _sessionExercises.add(info);
      _exerciseById[info.exerciseId] = info;
      _sessionExerciseById[info.sessionExerciseId] = info;
    });
    return info;
  }

  List<SessionExerciseInfo> _matchSessionExercises(String exerciseRef) {
    final normalized = _matcher.normalize(exerciseRef);
    if (normalized.isEmpty) return [];
    final refTokens = _tokenize(normalized);
    final matches = <SessionExerciseInfo>[];
    for (final info in _sessionExercises) {
      final nameTokens = _tokenize(_matcher.normalize(info.exerciseName));
      final refInName = refTokens.every(nameTokens.contains);
      final nameInRef = nameTokens.every(refTokens.contains);
      if (refInName || nameInRef) {
        matches.add(info);
      }
    }
    return matches;
  }

  SessionExerciseInfo? _guessSessionExercise(String utterance) {
    final normalized = _matcher.normalize(utterance);
    if (normalized.isEmpty) return null;
    final refTokens = _tokenize(normalized);
    SessionExerciseInfo? best;
    double bestScore = 0.0;
    for (final info in _sessionExercises) {
      final nameTokens = _tokenize(_matcher.normalize(info.exerciseName));
      if (nameTokens.isEmpty) continue;
      final overlap = nameTokens.where(refTokens.contains).length;
      if (overlap == 0) continue;
      final coverage = overlap / nameTokens.length;
      final strictOk = nameTokens.length <= 2 ? overlap == nameTokens.length : coverage >= 0.6;
      if (!strictOk) continue;
      final score = coverage + (overlap / 10.0);
      if (score > bestScore) {
        bestScore = score;
        best = info;
      }
    }
    return best;
  }

  Set<String> _tokenize(String value) {
    return value.split(' ').where((t) => t.isNotEmpty).toSet();
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openExerciseModal(SessionExerciseInfo info) {
    _lastExerciseInfo = info;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return ExerciseModal(
          info: info,
          workoutRepo: _workoutRepo,
          onAddSet: ({double? weight, required int reps, int? partials, double? rpe, double? rir}) =>
              _logSet(info, reps: reps, weight: weight, partials: partials, rpe: rpe, rir: rir),
          onUpdateSet: _updateSet,
          onUndo: _undo,
          onRedo: _redo,
          onStartRest: _startRestTimer,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Session'),
        actions: [
          IconButton(
            icon: const Icon(Icons.stop_circle_outlined),
            onPressed: () async {
              await _workoutRepo.endSession(widget.contextData.sessionId);
              if (!mounted) return;
              Navigator.of(context).pop();
            },
          ),
        ],
      ),
      floatingActionButton: GestureDetector(
        onLongPressStart: (_) => _startVoiceListening(),
        onLongPressEnd: (_) => _stopVoiceListening(),
        child: FloatingActionButton(
          onPressed: _runVoice,
          child: Icon(_listening ? Icons.mic : Icons.mic_none),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: _sessionExercises.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final info = _sessionExercises[index];
                return ListTile(
                  tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                  title: Text(info.exerciseName),
                  subtitle: Text('Tap to log sets'),
                  onTap: () => _openExerciseModal(info),
                );
              },
            ),
          ),
          if (_lastLogged != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: ConfirmationCard(
                lastLogged: _lastLogged!,
                onUndo: _undo,
                onRedo: _redo,
                onStartRest: _startRestTimer,
                undoCount: _undoRedo.undoCount,
                redoCount: _undoRedo.redoCount,
              ),
            ),
          TimerBar(
            remainingSeconds: _restRemaining,
            onStop: _stopRestTimer,
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_voicePartial != null)
                  Text(
                    'Listening: $_voicePartial',
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                if (_prompt != null)
                  Text(
                    _prompt!,
                    style: TextStyle(color: Theme.of(context).colorScheme.primary),
                  ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _voiceController,
                        decoration: const InputDecoration(
                          labelText: 'Voice command (type to simulate)',
                          border: OutlineInputBorder(),
                        ),
                        onSubmitted: (value) {
                          _handleVoiceInput(value);
                          _voiceController.clear();
                        },
                      ),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      onPressed: () {
                        final text = _voiceController.text;
                        _voiceController.clear();
                        _handleVoiceInput(text);
                      },
                      child: const Text('Send'),
                    )
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    TextButton(
                      onPressed: () {
                        setState(() {
                          _showVoiceDebug = !_showVoiceDebug;
                        });
                      },
                      child: Text(_showVoiceDebug ? 'Hide voice debug' : 'Show voice debug'),
                    ),
                  ],
                ),
                if (_showVoiceDebug)
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Transcript: ${_debugTranscript ?? '-'}'),
                        const SizedBox(height: 6),
                        Text('Rule: ${_debugRule ?? '-'}'),
                        const SizedBox(height: 6),
                        Text('LLM: ${_debugLlm ?? '-'}'),
                        const SizedBox(height: 6),
                        Text('Hints: ${_debugParts ?? '-'}'),
                        const SizedBox(height: 6),
                        Text('Decision: ${_debugDecision ?? '-'}'),
                        const SizedBox(height: 6),
                        Text('LLM raw: ${_debugLlmRaw ?? '-'}'),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
