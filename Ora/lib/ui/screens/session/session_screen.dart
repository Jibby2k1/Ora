import 'package:flutter/material.dart';
import 'dart:convert';

import 'dart:async';

import '../../../core/command_bus/command.dart';
import '../../../core/command_bus/dispatcher.dart';
import '../../../core/command_bus/session_command_reducer.dart';
import '../../../core/command_bus/undo_redo.dart';
import '../../../core/voice/gemini_parser.dart';
import '../../../core/voice/llm_parser.dart';
import '../../../core/voice/openai_parser.dart';
import '../../../core/voice/wake_word.dart';
import '../../../core/voice/voice_models.dart';
import '../../../core/voice/nlu_parser.dart';
import '../../../core/voice/stt.dart';
import '../../../core/voice/muscle_enricher.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../data/repositories/program_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/models/last_logged_set.dart';
import '../../../domain/models/session_context.dart';
import '../../../domain/models/session_exercise_info.dart';
import '../../../domain/services/exercise_matcher.dart';
import '../../widgets/confirmation_card/confirmation_card.dart';
import '../../widgets/exercise_modal/exercise_modal.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../../widgets/timer_bar/timer_bar.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.contextData});

  final SessionContext contextData;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

enum _PendingField { weight, reps }

class _PendingLogSet {
  _PendingLogSet({
    required this.exerciseInfo,
    required this.missingField,
    this.reps,
    this.weight,
    this.weightUnit,
    this.partials,
    this.rpe,
    this.rir,
  });

  final SessionExerciseInfo exerciseInfo;
  final _PendingField missingField;
  final int? reps;
  final double? weight;
  final String? weightUnit;
  final int? partials;
  final double? rpe;
  final double? rir;
}

const double _sessionMatchThreshold = 0.4;
const double _sessionGuessThreshold = 0.4;

class _SessionMatchScore {
  _SessionMatchScore(this.info, this.score);

  final SessionExerciseInfo info;
  final double score;
}

class _ExerciseMuscles {
  _ExerciseMuscles({required this.primary, required this.secondary});

  final String? primary;
  final List<String> secondary;
}

class _SessionScreenState extends State<SessionScreen> {
  final _voiceController = TextEditingController();
  final _parser = NluParser();
  final _llmParser = LlmParser();
  final _geminiParser = GeminiParser();
  final _openAiParser = OpenAiParser();
  final _wakeWordEngine = WakeWordEngine();
  late final WorkoutRepo _workoutRepo;
  late final ExerciseMatcher _matcher;
  late final ExerciseRepo _exerciseRepo;
  late final ProgramRepo _programRepo;
  late final SettingsRepo _settingsRepo;
  late final Map<int, SessionExerciseInfo> _exerciseById;
  late final Map<int, SessionExerciseInfo> _sessionExerciseById;
  late final Map<String, int> _cacheRefToExerciseId;
  late final CommandDispatcher _dispatcher;
  late final List<SessionExerciseInfo> _sessionExercises;
  final Map<int, _ExerciseMuscles> _musclesByExerciseId = {};
  List<String> _currentDayExerciseNames = [];
  List<String> _otherDayExerciseNames = [];
  List<String> _catalogExerciseNames = [];
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
  String? _debugGemini;
  String? _debugOpenAi;
  String? _debugCloud;
  String? _debugDecision;
  String? _debugParts;
  String? _debugLlmRaw;
  String? _debugGeminiRaw;
  String? _debugOpenAiRaw;
  String? _debugResolved;

  bool _cloudEnabled = false;
  String? _cloudApiKey;
  String _cloudModel = 'gemini-2.5-pro';
  String _cloudProvider = 'gemini';
  bool _wakeWordEnabled = false;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _workoutRepo = WorkoutRepo(db);
    _exerciseRepo = ExerciseRepo(db);
    _programRepo = ProgramRepo(db);
    _settingsRepo = SettingsRepo(db);
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
    _currentDayExerciseNames = _sessionExercises.map((e) => e.exerciseName).toList();
    // Defer local LLM initialization until it is actually needed.
    Future.microtask(_loadCloudSettings);
    Future.microtask(_loadExerciseHints);
    Future.microtask(_loadSessionMuscles);
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _loadCloudSettings() async {
    final enabled = await _settingsRepo.getCloudEnabled();
    final apiKey = await _settingsRepo.getCloudApiKey();
    final model = await _settingsRepo.getCloudModel();
    final provider = await _settingsRepo.getCloudProvider();
    final wakeWordEnabled = await _settingsRepo.getWakeWordEnabled();
    if (!mounted) return;
    setState(() {
      _cloudEnabled = enabled;
      _cloudApiKey = apiKey;
      _cloudModel = model;
      _cloudProvider = provider;
      _wakeWordEnabled = wakeWordEnabled;
    });
    _wakeWordEngine.enabled = wakeWordEnabled;
    if (wakeWordEnabled) {
      await _wakeWordEngine.start();
    } else {
      await _wakeWordEngine.stop();
    }
  }

  Future<void> _loadExerciseHints() async {
    try {
      final programId = widget.contextData.programId;
      final programDayId = widget.contextData.programDayId;
      final byDay = await _programRepo.getExerciseNamesByDayForProgram(programId);
      final other = <String>[];
      byDay.forEach((dayId, names) {
        if (dayId != programDayId) {
          other.addAll(names);
        }
      });
      final catalogRows = await _exerciseRepo.getAll();
      final catalog = catalogRows
          .map((row) => row['canonical_name'] as String?)
          .whereType<String>()
          .where((name) => name.trim().isNotEmpty)
          .toList();
      if (!mounted) return;
      setState(() {
        _otherDayExerciseNames = _limitList(_dedupeList(other), 120);
        _catalogExerciseNames = _limitList(_dedupeList(catalog), 200);
      });
    } catch (_) {
      // ignore hint failures
    }
  }

  Future<void> _loadSessionMuscles() async {
    try {
      final cloudEnabled = await _settingsRepo.getCloudEnabled();
      final apiKey = await _settingsRepo.getCloudApiKey();
      final provider = await _settingsRepo.getCloudProvider();
      final model = await _settingsRepo.getCloudModel();
      final canEnrich = cloudEnabled && apiKey != null && apiKey.trim().isNotEmpty;
      final enricher = canEnrich ? MuscleEnricher() : null;
      for (final info in _sessionExercises) {
        final row = await _exerciseRepo.getById(info.exerciseId);
        if (row == null) continue;
        final primary = (row['primary_muscle'] as String?)?.trim();
        final secondaryJson = row['secondary_muscles_json'] as String?;
        final secondary = <String>[];
        if (secondaryJson != null && secondaryJson.isNotEmpty) {
          try {
            final decoded = jsonDecode(secondaryJson);
            if (decoded is List) {
              secondary.addAll(
                decoded.map((e) => e.toString()).where((e) => e.trim().isNotEmpty),
              );
            }
          } catch (_) {}
        }
        _musclesByExerciseId[info.exerciseId] = _ExerciseMuscles(
          primary: primary,
          secondary: secondary,
        );
        if ((primary == null || primary.isEmpty) && enricher != null) {
          final result = await enricher.enrich(
            exerciseName: info.exerciseName,
            provider: provider,
            apiKey: apiKey!.trim(),
            model: model,
          );
          if (result != null) {
            await _exerciseRepo.updateMuscles(
              exerciseId: info.exerciseId,
              primaryMuscle: result.primary,
              secondaryMuscles: result.secondary,
            );
            _musclesByExerciseId[info.exerciseId] = _ExerciseMuscles(
              primary: result.primary,
              secondary: result.secondary,
            );
          }
        }
      }
      if (mounted) setState(() {});
    } catch (_) {}
  }

  List<String> _dedupeList(List<String> values) {
    final seen = <String>{};
    final result = <String>[];
    for (final value in values) {
      final trimmed = value.trim();
      final key = trimmed.toLowerCase();
      if (trimmed.isEmpty || seen.contains(key)) continue;
      seen.add(key);
      result.add(trimmed);
    }
    return result;
  }

  List<String> _limitList(List<String> values, int max) {
    if (values.length <= max) return values;
    return values.sublist(0, max);
  }

  Future<void> _refreshCloudSettingsForVoice() async {
    final enabled = await _settingsRepo.getCloudEnabled();
    final apiKey = await _settingsRepo.getCloudApiKey();
    final model = await _settingsRepo.getCloudModel();
    final provider = await _settingsRepo.getCloudProvider();
    if (!mounted) return;
    if (enabled != _cloudEnabled ||
        apiKey != _cloudApiKey ||
        model != _cloudModel ||
        provider != _cloudProvider) {
      setState(() {
        _cloudEnabled = enabled;
        _cloudApiKey = apiKey;
        _cloudModel = model;
        _cloudProvider = provider;
      });
    }
  }

  Future<void> _handleVoiceInput(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;
    await _refreshCloudSettingsForVoice();
    final cloudKeyPresent = _cloudApiKey != null && _cloudApiKey!.trim().isNotEmpty;
    final cloudStatus = _cloudEnabled
        ? (cloudKeyPresent ? 'On (${_cloudProvider}/${_cloudModel})' : 'On (missing key)')
        : 'Off';
    _setVoiceDebug(
      transcript: trimmed,
      rule: '-',
      llm: '-',
      gemini: '-',
      openai: '-',
      cloud: cloudStatus,
      decision: 'Listening...',
      parts: null,
      llmRaw: null,
      geminiRaw: null,
      openaiRaw: null,
      resolved: null,
    );

    if (await _handlePendingVoice(trimmed)) return;

    if (_cloudEnabled && cloudKeyPresent) {
      if (_cloudProvider == 'openai') {
        final openAiCommand = await _runOpenAiParse(trimmed);
        if (openAiCommand != null) {
          final normalized = _normalizeLogSetFromTranscript(openAiCommand, trimmed);
          _setVoiceDebug(
            openai: _describeCommand(normalized),
            decision: 'OpenAI primary',
          );
          await _handleParsedCommand(
            normalized,
            transcript: trimmed,
            source: 'openai',
          );
          return;
        }
        if (_openAiParser.lastError != null) {
          _setVoiceDebug(
            decision: 'OpenAI failed: ${_openAiParser.lastError}',
          );
        }
      } else {
        final geminiCommand = await _runGeminiParse(trimmed);
        if (geminiCommand != null) {
          final normalized = _normalizeLogSetFromTranscript(geminiCommand, trimmed);
          _setVoiceDebug(
            gemini: _describeCommand(normalized),
            decision: 'Gemini primary',
          );
          await _handleParsedCommand(
            normalized,
            transcript: trimmed,
            source: 'gemini',
          );
          return;
        }
        if (_geminiParser.lastError != null) {
          _setVoiceDebug(
            decision: 'Gemini failed: ${_geminiParser.lastError}',
          );
        }
      }
    } else if (_cloudEnabled) {
      _setVoiceDebug(decision: 'Cloud enabled but missing API key');
    }

    final llmCommand = _llmParser.enabled ? await _runLlmParse(trimmed) : null;
    if (llmCommand != null) {
      final normalized = _normalizeLogSetFromTranscript(llmCommand, trimmed);
      _setVoiceDebug(
        llm: _describeCommand(normalized),
        decision: 'Local LLM',
      );
      await _handleParsedCommand(
        normalized,
        transcript: trimmed,
        source: 'local_llm',
      );
      return;
    }

    final ruleCommand = _parser.parse(trimmed);
    if (ruleCommand != null) {
      final normalized = _normalizeLogSetFromTranscript(ruleCommand, trimmed);
      _setVoiceDebug(
        rule: _describeCommand(normalized),
        decision: 'Rule fallback',
      );
      await _handleParsedCommand(
        normalized,
        transcript: trimmed,
        source: 'rule',
      );
      return;
    }

    if (_llmParser.enabled && _llmParser.lastError != null) {
      _setVoiceDebug(
        decision: 'LLM failed: ${_llmParser.lastError}',
      );
      _showMessage('LLM parse failed: ${_llmParser.lastError}');
      return;
    }

    final fallbackParts = _parser.parseLogPartsWithOrderHints(trimmed);
    if (fallbackParts.reps != null || fallbackParts.weight != null) {
      final exerciseInfo = await _resolveExercise(trimmed);
      if (exerciseInfo != null) {
        await _logSetWithFill(
          exerciseInfo,
          reps: fallbackParts.reps,
          weight: fallbackParts.weight,
          weightUnit: fallbackParts.weightUnit,
          partials: fallbackParts.partials,
          rpe: fallbackParts.rpe,
          rir: fallbackParts.rir,
          source: 'fallback',
          transcript: trimmed,
        );
        return;
      }
    }

    _setVoiceDebug(decision: 'No parse matched');
    _showMessage('Could not parse command: "$trimmed"');
  }

  Future<bool> _handlePendingVoice(String input) async {
    final pending = _pending;
    if (pending == null) return false;
    final wantsSame = _wantsSameAsLast(input);
    final latest = await _workoutRepo.getLatestSetForSessionExercise(pending.exerciseInfo.sessionExerciseId);
    final lastReps = latest?['reps'] as int?;
    final lastWeight = latest?['weight_value'] as double?;
    final lastUnit = latest?['weight_unit'] as String?;

    if (wantsSame && latest != null) {
      if (lastReps != null && lastWeight != null) {
        await _logSet(
          pending.exerciseInfo,
          reps: lastReps,
          weight: lastWeight,
          weightUnit: lastUnit ?? 'lb',
          partials: pending.partials,
          rpe: pending.rpe,
          rir: pending.rir,
        );
        setState(() {
          _pending = null;
          _prompt = null;
        });
        _setVoiceDebug(decision: 'Pending resolved via last set');
        return true;
      }
    }

    final parts = _parser.parseLogPartsWithOrderHints(input);
    if (pending.missingField == _PendingField.weight) {
      final weight = parts.weight ?? _parser.parseWeightOnly(input);
      if (weight == null) {
        _showMessage('Need weight.');
        return true;
      }
      final reps = pending.reps ?? lastReps;
      if (reps == null) {
        _showMessage('Need reps.');
        return true;
      }
      await _logSet(
        pending.exerciseInfo,
        reps: reps,
        weight: weight,
        weightUnit: parts.weightUnit ?? pending.weightUnit ?? lastUnit ?? 'lb',
        partials: pending.partials,
        rpe: pending.rpe,
        rir: pending.rir,
      );
    } else {
      final reps = parts.reps;
      if (reps == null) {
        _showMessage('Need reps.');
        return true;
      }
      final weight = pending.weight ?? lastWeight;
      if (weight == null) {
        _showMessage('Need weight.');
        return true;
      }
      await _logSet(
        pending.exerciseInfo,
        reps: reps,
        weight: weight,
        weightUnit: pending.weightUnit ?? parts.weightUnit ?? lastUnit ?? 'lb',
        partials: pending.partials,
        rpe: pending.rpe,
        rir: pending.rir,
      );
    }
    setState(() {
      _pending = null;
      _prompt = null;
    });
    _setVoiceDebug(decision: 'Pending resolved');
    return true;
  }

  bool _wantsSameAsLast(String input) {
    final normalized = _parser.normalize(input);
    return normalized.contains('same as last') ||
        normalized.contains('same as previous') ||
        normalized.contains('repeat last') ||
        normalized.contains('same as before') ||
        normalized.contains('copy last') ||
        normalized == 'same set';
  }

  Future<void> _handleParsedCommand(
    NluCommand parsed, {
    String? transcript,
    String source = 'rule',
  }) async {
    switch (parsed.type) {
      case 'undo':
        await _undo();
        _setVoiceDebug(decision: 'Undo ($source)');
        return;
      case 'redo':
        await _redo();
        _setVoiceDebug(decision: 'Redo ($source)');
        return;
      case 'switch':
        if (parsed.exerciseRef == null) return;
        final exerciseInfo = await _resolveExercise(parsed.exerciseRef!);
        if (exerciseInfo != null) {
          _openExerciseModal(exerciseInfo);
          _setVoiceDebug(
            decision: 'Switch ($source)',
            resolved: 'exercise=${exerciseInfo.exerciseName}',
          );
        }
        return;
      case 'show_stats':
        _showMessage('Stats view not in demo.');
        _setVoiceDebug(decision: 'Show stats ($source)');
        return;
      case 'log_set':
        await _handleLogSetCommand(
          parsed,
          transcript ?? '',
          source: source,
        );
        return;
    }
  }

  Future<void> _handleLogSetCommand(
    NluCommand command,
    String transcript, {
    required String source,
  }) async {
    final normalized = _normalizeLogSetFromTranscript(command, transcript);
    final wantsSame = _wantsSameAsLast(transcript);
    final exerciseInfo = await _resolveExerciseForLogSet(normalized, transcript, wantsSame: wantsSame);
    if (exerciseInfo == null) {
      _setVoiceDebug(decision: 'No exercise match ($source)');
      _prompt = 'Which exercise?';
      _showMessage('No exercise match.');
      return;
    }

    await _logSetWithFill(
      exerciseInfo,
      reps: normalized.reps,
      weight: normalized.weight,
      weightUnit: normalized.weightUnit,
      partials: normalized.partials,
      rpe: normalized.rpe,
      rir: normalized.rir,
      source: source,
      transcript: transcript,
      wantsSame: wantsSame,
    );
  }

  Future<SessionExerciseInfo?> _resolveExerciseForLogSet(
    NluCommand command,
    String transcript, {
    required bool wantsSame,
  }) async {
    final ref = command.exerciseRef?.trim();
    if (ref != null && ref.isNotEmpty) {
      return _resolveExercise(ref);
    }
    if (wantsSame && _lastExerciseInfo != null) {
      return _lastExerciseInfo;
    }
    final inferred = await _resolveExercise(transcript);
    return inferred ?? _lastExerciseInfo;
  }

  Future<void> _logSetWithFill(
    SessionExerciseInfo exerciseInfo, {
    required int? reps,
    required double? weight,
    required String? weightUnit,
    required int? partials,
    required double? rpe,
    required double? rir,
    required String source,
    required String transcript,
    bool wantsSame = false,
  }) async {
    final latest = await _workoutRepo.getLatestSetForSessionExercise(exerciseInfo.sessionExerciseId);
    final lastReps = latest?['reps'] as int?;
    final lastWeight = latest?['weight_value'] as double?;
    final lastUnit = latest?['weight_unit'] as String?;

    var resolvedReps = reps;
    var resolvedWeight = weight;
    var resolvedUnit = weightUnit ?? lastUnit ?? 'lb';

    if (wantsSame && latest != null) {
      resolvedReps ??= lastReps;
      resolvedWeight ??= lastWeight;
      resolvedUnit = weightUnit ?? lastUnit ?? resolvedUnit;
    }

    if (latest != null) {
      if (resolvedWeight == null && resolvedReps != null) {
        resolvedWeight = lastWeight;
        resolvedUnit = weightUnit ?? lastUnit ?? resolvedUnit;
      }
      if (resolvedReps == null && resolvedWeight != null) {
        resolvedReps = lastReps;
      }
    }

    if (resolvedReps == null && resolvedWeight == null && latest == null) {
      final numbers = _parser.extractNumbers(transcript);
      if (numbers.length >= 2) {
        final sorted = List<double>.from(numbers)..sort();
        resolvedReps = sorted.first.round();
        resolvedWeight = sorted.last;
        resolvedUnit = weightUnit ?? resolvedUnit;
        _setVoiceDebug(decision: 'Assumed larger=weight ($source)');
      }
    }

    if (resolvedReps == null) {
      setState(() {
        _pending = _PendingLogSet(
          exerciseInfo: exerciseInfo,
          missingField: _PendingField.reps,
          weight: resolvedWeight,
          weightUnit: resolvedUnit,
          partials: partials,
          rpe: rpe,
          rir: rir,
        );
        _prompt = 'What reps?';
      });
      _setVoiceDebug(decision: 'Awaiting reps ($source)');
      return;
    }

    if (resolvedWeight == null) {
      setState(() {
        _pending = _PendingLogSet(
          exerciseInfo: exerciseInfo,
          missingField: _PendingField.weight,
          reps: resolvedReps,
          partials: partials,
          rpe: rpe,
          rir: rir,
        );
        _prompt = 'What weight?';
      });
      _setVoiceDebug(decision: 'Awaiting weight ($source)');
      return;
    }

    await _logSet(
      exerciseInfo,
      reps: resolvedReps,
      weight: resolvedWeight,
      weightUnit: resolvedUnit,
      partials: partials,
      rpe: rpe,
      rir: rir,
    );
    _setVoiceDebug(
      decision: 'Logged ($source)',
      resolved: 'exercise=${exerciseInfo.exerciseName} reps=$resolvedReps weight=$resolvedWeight unit=$resolvedUnit',
    );
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

  Future<NluCommand?> _runGeminiParse(String transcript) async {
    setState(() {
      _prompt = 'Thinking (cloud)...';
    });
    final apiKey = _cloudApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _prompt = null;
      });
      return null;
    }
    final result = await _geminiParser.parse(
      transcript: transcript,
      apiKey: apiKey,
      model: _cloudModel,
      currentDayExercises: _currentDayExerciseNames,
      otherDayExercises: _otherDayExerciseNames,
      catalogExercises: _catalogExerciseNames,
    );
    setState(() {
      _prompt = null;
    });
    if (_geminiParser.lastRawOutput != null) {
      _setVoiceDebug(geminiRaw: _geminiParser.lastRawOutput);
    }
    return result;
  }

  Future<NluCommand?> _runOpenAiParse(String transcript) async {
    setState(() {
      _prompt = 'Thinking (cloud)...';
    });
    final apiKey = _cloudApiKey;
    if (apiKey == null || apiKey.isEmpty) {
      setState(() {
        _prompt = null;
      });
      return null;
    }
    final result = await _openAiParser.parse(
      transcript: transcript,
      apiKey: apiKey,
      model: _cloudModel,
      currentDayExercises: _currentDayExerciseNames,
      otherDayExercises: _otherDayExerciseNames,
      catalogExercises: _catalogExerciseNames,
    );
    setState(() {
      _prompt = null;
    });
    if (_openAiParser.lastRawOutput != null) {
      _setVoiceDebug(openaiRaw: _openAiParser.lastRawOutput);
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
    String? gemini,
    String? openai,
    String? cloud,
    String? decision,
    String? parts,
    String? llmRaw,
    String? geminiRaw,
    String? openaiRaw,
    String? resolved,
  }) {
    final hints = _parser.parseLogPartsWithOrderHints(_debugTranscript ?? transcript ?? '');
    setState(() {
      _debugTranscript = transcript ?? _debugTranscript;
      _debugRule = rule ?? _debugRule;
      _debugLlm = llm ?? _debugLlm;
      _debugGemini = gemini ?? _debugGemini;
      _debugOpenAi = openai ?? _debugOpenAi;
      _debugCloud = cloud ?? _debugCloud;
      _debugDecision = decision ?? _debugDecision;
      _debugParts = parts ??
          'hints: weight=${hints.weight}, reps=${hints.reps}, unit=${hints.weightUnit}, partials=${hints.partials}';
      _debugLlmRaw = llmRaw ?? _debugLlmRaw;
      _debugGeminiRaw = geminiRaw ?? _debugGeminiRaw;
      _debugOpenAiRaw = openaiRaw ?? _debugOpenAiRaw;
      _debugResolved = resolved ?? _debugResolved;
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
    final normalized = _matcher.normalizeForCache(exerciseRef);
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
    String weightUnit = 'lb',
    int? partials,
    double? rpe,
    double? rir,
  }) async {
    final result = await _dispatcher.dispatch(
      LogSetEntry(
        sessionExerciseId: info.sessionExerciseId,
        weightUnit: weightUnit,
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
    final refTokens = _matcher.tokenize(exerciseRef);
    if (refTokens.isEmpty) return [];
    final scored = <_SessionMatchScore>[];
    for (final info in _sessionExercises) {
      final score = _matcher.scoreName(exerciseRef, info.exerciseName);
      if (score >= _sessionMatchThreshold) {
        scored.add(_SessionMatchScore(info, score));
      }
    }
    scored.sort((a, b) => b.score.compareTo(a.score));
    return scored.map((entry) => entry.info).toList();
  }

  SessionExerciseInfo? _guessSessionExercise(String utterance) {
    SessionExerciseInfo? best;
    double bestScore = 0.0;
    for (final info in _sessionExercises) {
      final score = _matcher.scoreName(utterance, info.exerciseName);
      if (score > bestScore) {
        bestScore = score;
        best = info;
      }
    }
    return bestScore >= _sessionGuessThreshold ? best : null;
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
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      barrierColor: Colors.black.withOpacity(0.4),
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
          onClose: () => Navigator.of(context).pop(),
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
      body: Stack(
        children: [
          const GlassBackground(),
          Column(
            children: [
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: _sessionExercises.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    final info = _sessionExercises[index];
                    final muscles = _musclesByExerciseId[info.exerciseId];
                    final tags = <String>[];
                    if (info.planBlocks.any((b) => b.amrapLastSet)) {
                      tags.add('AMRAP');
                    }
                    final muscleChips = <Widget>[];
                    final primary = muscles?.primary;
                    final primaryColor = Theme.of(context).colorScheme.primary;
                    final secondaryColor = Theme.of(context).colorScheme.secondary;
                    if (primary != null && primary.isNotEmpty) {
                      muscleChips.add(
                        Chip(
                          label: Text(primary),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: primaryColor.withOpacity(0.22),
                          labelStyle: TextStyle(color: primaryColor, fontWeight: FontWeight.w600),
                          side: BorderSide(color: primaryColor.withOpacity(0.6)),
                        ),
                      );
                    }
                    for (final secondary in muscles?.secondary ?? const []) {
                      muscleChips.add(
                        Chip(
                          label: Text(secondary),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: secondaryColor.withOpacity(0.18),
                          labelStyle: TextStyle(color: secondaryColor, fontWeight: FontWeight.w500),
                          side: BorderSide(color: secondaryColor.withOpacity(0.5)),
                        ),
                      );
                    }
                    for (final tag in tags) {
                      muscleChips.add(
                        Chip(
                          label: Text(tag),
                          visualDensity: VisualDensity.compact,
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                        ),
                      );
                    }
                    return GlassCard(
                      padding: EdgeInsets.zero,
                      child: ListTile(
                        title: Text(info.exerciseName),
                        subtitle: muscleChips.isEmpty
                            ? const Text('Tap to log sets')
                            : Padding(
                                padding: const EdgeInsets.only(top: 6),
                                child: Wrap(
                                  spacing: 6,
                                  runSpacing: 6,
                                  children: muscleChips,
                                ),
                              ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openExerciseModal(info),
                      ),
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
                    if (_wakeWordEnabled)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: Row(
                          children: const [
                            Icon(Icons.hearing, size: 16),
                            SizedBox(width: 6),
                            Text('Listening for “Hey Ora”'),
                          ],
                        ),
                      ),
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
                      GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Transcript: ${_debugTranscript ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Rule: ${_debugRule ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('LLM: ${_debugLlm ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Gemini: ${_debugGemini ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('OpenAI: ${_debugOpenAi ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Cloud: ${_debugCloud ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Hints: ${_debugParts ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Decision: ${_debugDecision ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Resolved: ${_debugResolved ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('LLM raw: ${_debugLlmRaw ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('Gemini raw: ${_debugGeminiRaw ?? '-'}'),
                            const SizedBox(height: 6),
                            Text('OpenAI raw: ${_debugOpenAiRaw ?? '-'}'),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
