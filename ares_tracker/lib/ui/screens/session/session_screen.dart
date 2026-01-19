import 'package:flutter/material.dart';

import '../../../core/command_bus/command.dart';
import '../../../core/command_bus/dispatcher.dart';
import '../../../core/command_bus/session_command_reducer.dart';
import '../../../core/command_bus/undo_redo.dart';
import '../../../core/voice/nlu_parser.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/models/last_logged_set.dart';
import '../../../domain/models/session_context.dart';
import '../../../domain/models/session_exercise_info.dart';
import '../../../domain/services/exercise_matcher.dart';
import '../../widgets/confirmation_card/confirmation_card.dart';
import '../../widgets/exercise_modal/exercise_modal.dart';

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
  late final WorkoutRepo _workoutRepo;
  late final ExerciseMatcher _matcher;
  late final Map<int, SessionExerciseInfo> _exerciseById;
  late final Map<int, SessionExerciseInfo> _sessionExerciseById;
  late final Map<String, int> _cacheRefToExerciseId;
  late final CommandDispatcher _dispatcher;
  final UndoRedoStack _undoRedo = UndoRedoStack();

  _PendingLogSet? _pending;
  LastLoggedSet? _lastLogged;
  String? _prompt;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _workoutRepo = WorkoutRepo(db);
    _matcher = ExerciseMatcher(ExerciseRepo(db));
    _exerciseById = {for (final info in widget.contextData.exercises) info.exerciseId: info};
    _sessionExerciseById = {for (final info in widget.contextData.exercises) info.sessionExerciseId: info};
    _cacheRefToExerciseId = {};
    _dispatcher = CommandDispatcher(
      SessionCommandReducer(
        workoutRepo: _workoutRepo,
        sessionExerciseById: _sessionExerciseById,
      ).call,
    );
  }

  @override
  void dispose() {
    _voiceController.dispose();
    super.dispose();
  }

  Future<void> _handleVoiceInput(String input) async {
    final trimmed = input.trim();
    if (trimmed.isEmpty) return;

    final pending = _pending;
    if (pending != null) {
      final weight = double.tryParse(trimmed);
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
    if (parsed == null) {
      _showMessage('Could not parse command.');
      return;
    }

    switch (parsed.type) {
      case 'undo':
        await _undo();
        return;
      case 'redo':
        await _redo();
        return;
      case 'rest':
        _showMessage('Rest ${parsed.restSeconds ?? 0}s');
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
        if (parsed.exerciseRef == null || parsed.reps == null) {
          _showMessage('Need exercise and reps.');
          return;
        }
        final exerciseInfo = await _resolveExercise(parsed.exerciseRef!);
        if (exerciseInfo == null) return;

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

  Future<SessionExerciseInfo?> _resolveExercise(String exerciseRef) async {
    final normalized = _matcher.normalize(exerciseRef);
    final cached = _cacheRefToExerciseId[normalized];
    if (cached != null) {
      return _exerciseById[cached];
    }

    final match = await _matcher.match(exerciseRef);
    if (match.isNone) {
      _showMessage('No exercise match.');
      return null;
    }

    ExerciseMatch? selected;
    if (match.isSingle) {
      selected = match.matches.first;
    } else {
      selected = await _showDisambiguation(match.matches);
      if (selected == null) return null;
    }

    final info = _exerciseById[selected.id];
    if (info == null) {
      _showMessage('Exercise not in session.');
      return null;
    }

    _cacheRefToExerciseId[normalized] = selected.id;
    return info;
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

  void _showMessage(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  void _openExerciseModal(SessionExerciseInfo info) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) {
        return ExerciseModal(
          info: info,
          workoutRepo: _workoutRepo,
          onAddSet: (weight, reps) => _logSet(info, reps: reps, weight: weight),
          onUpdateSet: _updateSet,
          onUndo: _undo,
          onRedo: _redo,
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
      body: Column(
        children: [
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: widget.contextData.exercises.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final info = widget.contextData.exercises[index];
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
                undoCount: _undoRedo.undoCount,
                redoCount: _undoRedo.redoCount,
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
              ],
            ),
          ),
        ],
      ),
    );
  }
}
