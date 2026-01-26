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
import '../../../domain/services/set_plan_service.dart';
import '../shell/app_shell_controller.dart';
import '../history/exercise_catalog_screen.dart';
import '../../widgets/confirmation_card/confirmation_card.dart';
import '../../widgets/exercise_modal/exercise_modal.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class SessionScreen extends StatefulWidget {
  const SessionScreen({super.key, required this.contextData, this.isEditing = false});

  final SessionContext contextData;
  final bool isEditing;

  @override
  State<SessionScreen> createState() => _SessionScreenState();
}

class _DraftSet {
  final TextEditingController weight = TextEditingController();
  final TextEditingController reps = TextEditingController();

  void dispose() {
    weight.dispose();
    reps.dispose();
  }
}

class _InlineSetData {
  _InlineSetData({required this.sets, required this.previousSets});

  final List<Map<String, Object?>> sets;
  final List<Map<String, Object?>> previousSets;
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
  bool _isLoggingSet = false;
  final List<String> _setDebugNotes = [];
  bool _showSetDebug = false;
  final Map<int, _InlineSetData> _inlineSetCache = {};
  final Map<int, Future<_InlineSetData>> _inlineSetFutures = {};
  final Map<int, String> _inlineDebugSnapshot = {};
  final Map<int, int> _restSecondsByExerciseId = {};
  Timer? _inlineRestTicker;
  DateTime _inlineRestNow = DateTime.now();
  DateTime? _sessionStartedAt;
  DateTime? _sessionEndedAt;
  bool _listening = false;
  String? _voicePartial;
  final Map<int, List<_DraftSet>> _draftSetsByExerciseId = {};

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
  bool _sessionEnded = false;
  String _weightUnit = 'lb';
  bool _handlingPendingSessionVoice = false;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    if (!widget.isEditing) {
      AppShellController.instance.setActiveSession(true);
      AppShellController.instance.setActiveSessionIndicatorHidden(false);
    }
    AppShellController.instance.pendingSessionVoice.addListener(_handlePendingSessionVoice);
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
    Future.microtask(_loadUnitPref);
    Future.microtask(_loadSessionHeader);
    Future.microtask(_seedInitialDraftSets);
    _inlineRestNow = DateTime.now();
    _inlineRestTicker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() {
        _inlineRestNow = DateTime.now();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingSessionVoice();
    });
  }

  @override
  void dispose() {
    _voiceController.dispose();
    _inlineRestTicker?.cancel();
    AppShellController.instance.pendingSessionVoice.removeListener(_handlePendingSessionVoice);
    for (final drafts in _draftSetsByExerciseId.values) {
      for (final draft in drafts) {
        draft.dispose();
      }
    }
    if (!widget.isEditing && !_sessionEnded) {
      AppShellController.instance.setActiveSession(true);
      AppShellController.instance.setActiveSessionIndicatorHidden(false);
      AppShellController.instance.refreshActiveSession();
    }
    if (_sessionEnded && !widget.isEditing) {
      AppShellController.instance.setActiveSession(false);
    }
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

  Future<void> _loadSessionHeader() async {
    final header = await _workoutRepo.getSessionHeader(widget.contextData.sessionId);
    if (!mounted) return;
    setState(() {
      _sessionStartedAt = DateTime.tryParse(header?['started_at'] as String? ?? '');
      _sessionEndedAt = DateTime.tryParse(header?['ended_at'] as String? ?? '');
    });
  }

  Future<void> _seedInitialDraftSets() async {
    if (widget.isEditing) return;
    if (widget.contextData.programDayId == null) return;
    var added = false;
    for (final info in _sessionExercises) {
      if (_draftSetsByExerciseId.containsKey(info.sessionExerciseId)) continue;
      final sets = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
      if (sets.isNotEmpty) continue;
      _draftSetsByExerciseId.putIfAbsent(info.sessionExerciseId, () => []).add(_DraftSet());
      added = true;
    }
    if (!mounted || !added) return;
    setState(() {});
  }

  Future<void> _loadExerciseHints() async {
    try {
      final programId = widget.contextData.programId;
      final programDayId = widget.contextData.programDayId;
      if (programId == null) return;
      final byDay = await _programRepo.getExerciseNamesByDayForProgram(programId);
      final other = <String>[];
      byDay.forEach((dayId, names) {
        if (programDayId == null || dayId != programDayId) {
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

  Future<void> _loadUnitPref() async {
    final unit = await _settingsRepo.getUnit();
    if (!mounted) return;
    setState(() {
      _weightUnit = unit;
    });
  }

  Future<void> _showQuickAddSet(SessionExerciseInfo info) async {
    final list = _draftSetsByExerciseId.putIfAbsent(info.sessionExerciseId, () => []);
    list.add(_DraftSet());
    if (!mounted) return;
    setState(() {});
  }

  String _formatSetWeight(num? weight) {
    if (weight == null) return '—';
    final value = weight.toDouble();
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  String _formatPrevious(Map<String, Object?>? row) {
    if (row == null) return '—';
    final weight = row['weight_value'] as num?;
    final reps = row['reps'] as int?;
    if (weight == null || reps == null) return '—';
    final unit = (row['weight_unit'] as String?)?.trim();
    final unitLabel = unit == null || unit.isEmpty ? '' : ' $unit';
    return '${_formatSetWeight(weight)}$unitLabel × $reps';
  }

  int? _planRestSeconds(SessionExerciseInfo info) {
    int? restMax;
    int? restMin;
    for (final block in info.planBlocks) {
      if (block.restSecMax != null) {
        if (restMax == null || block.restSecMax! > restMax) {
          restMax = block.restSecMax;
        }
      }
      if (block.restSecMin != null) {
        if (restMin == null || block.restSecMin! < restMin!) {
          restMin = block.restSecMin;
        }
      }
    }
    return restMax ?? restMin;
  }

  int _restSecondsForExercise(SessionExerciseInfo info) {
    final cached = _restSecondsByExerciseId[info.exerciseId];
    if (cached != null) return cached;
    const fallback = 90;
    final value = _planRestSeconds(info) ?? fallback;
    _restSecondsByExerciseId[info.exerciseId] = value;
    return value;
  }

  String _formatRestShort(int seconds) {
    if (seconds <= 0) return '0:00';
    final mins = seconds ~/ 60;
    final secs = seconds % 60;
    return '${mins}:${secs.toString().padLeft(2, '0')}';
  }

  String _formatSessionTimer(Duration elapsed) {
    final totalSeconds = elapsed.inSeconds.clamp(0, 86400 * 7);
    final hours = totalSeconds ~/ 3600;
    final minutes = (totalSeconds % 3600) ~/ 60;
    final seconds = totalSeconds % 60;
    if (hours > 0) {
      return '${hours}:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    }
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _startInlineRest({
    required int setId,
    required int restSeconds,
    required int exerciseId,
  }) {
    if (restSeconds <= 0) return;
    AppShellController.instance.startRestTimer(
      seconds: restSeconds,
      setId: setId,
      exerciseId: exerciseId,
    );
    if (!mounted) return;
    setState(() {});
  }

  void _completeInlineRest() {
    if (AppShellController.instance.restActiveSetId == null) return;
    AppShellController.instance.completeRestTimer();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _undoCompletedSet(SessionExerciseInfo info, Map<String, Object?> row) async {
    final id = row['id'] as int?;
    if (id == null) return;
    final weight = row['weight_value'] as num?;
    final reps = row['reps'] as int?;
    await _deleteSet(id, info);
    final draft = _DraftSet();
    if (weight != null) {
      draft.weight.text = _formatSetWeight(weight);
    }
    if (reps != null) {
      draft.reps.text = reps.toString();
    }
    _draftSetsByExerciseId.putIfAbsent(info.sessionExerciseId, () => []).add(draft);
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _showRestPicker(SessionExerciseInfo info, int currentSeconds) async {
    final controller = TextEditingController(text: currentSeconds.toString());
    final quickOptions = [30, 45, 60, 90, 120, 180];
    final selected = await showDialog<int>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Rest Timer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: controller,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Seconds',
                  isDense: true,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final seconds in quickOptions)
                    OutlinedButton(
                      onPressed: () => controller.text = seconds.toString(),
                      child: Text('${seconds}s'),
                    ),
                ],
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () {
                final value = int.tryParse(controller.text.trim());
                if (value == null || value < 0) {
                  _showMessage('Enter a valid rest time.');
                  return;
                }
                Navigator.of(context).pop(value);
              },
              child: const Text('Save'),
            ),
          ],
        );
      },
    );
    if (selected == null || !mounted) return;
    setState(() {
      _restSecondsByExerciseId[info.exerciseId] = selected;
    });
  }

  Future<_InlineSetData> _loadInlineSetData(SessionExerciseInfo info) async {
    try {
      final sets = List<Map<String, Object?>>.from(
        await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId),
      );
      sets.sort((a, b) {
        final aIndex = (a['set_index'] as int?) ?? 0;
        final bIndex = (b['set_index'] as int?) ?? 0;
        if (aIndex != bIndex) return aIndex.compareTo(bIndex);
        final aId = (a['id'] as int?) ?? 0;
        final bId = (b['id'] as int?) ?? 0;
        return aId.compareTo(bId);
      });
      final previousSets = List<Map<String, Object?>>.from(
        await _workoutRepo.getPreviousSetsForExercise(
          exerciseId: info.exerciseId,
          excludeSessionId: widget.contextData.sessionId,
        ),
      );
      final drafts = _draftSetsByExerciseId[info.sessionExerciseId] ?? const [];
      _logInlineSnapshot(info, sets, previousSets, drafts, source: 'load');
      return _InlineSetData(sets: sets, previousSets: previousSets);
    } catch (error, stack) {
      _pushSetDebug(
        '[load] ex=${info.sessionExerciseId} error=${error.runtimeType} '
        '${error.toString().split('\n').first}',
      );
      debugPrint(stack.toString());
      final cached = _inlineSetCache[info.sessionExerciseId];
      if (cached != null) return cached;
      return _InlineSetData(sets: const [], previousSets: const []);
    }
  }

  Future<_InlineSetData> _getInlineSetFuture(SessionExerciseInfo info) {
    final existing = _inlineSetFutures[info.sessionExerciseId];
    if (existing != null) {
      _pushSetDebug(
        '[future] ex=${info.sessionExerciseId} reuse future=${existing.hashCode}',
      );
      return existing;
    }
    final future = _loadInlineSetData(info).then((data) {
      _inlineSetCache[info.sessionExerciseId] = data;
      return data;
    });
    _inlineSetFutures[info.sessionExerciseId] = future;
    _pushSetDebug(
      '[future] ex=${info.sessionExerciseId} create future=${future.hashCode}',
    );
    return future;
  }

  void _refreshInlineSetData(SessionExerciseInfo info) {
    final previous = _inlineSetFutures[info.sessionExerciseId];
    final future = _loadInlineSetData(info).then((data) {
      _inlineSetCache[info.sessionExerciseId] = data;
      _pushSetDebug(
        '[refresh] ex=${info.sessionExerciseId} done sets=${data.sets.length} '
        'rows=${_summarizeSetRows(data.sets)}',
      );
      return data;
    });
    _inlineSetFutures[info.sessionExerciseId] = future;
    _pushSetDebug(
      '[refresh] ex=${info.sessionExerciseId} start future=${future.hashCode} '
      'prev=${previous?.hashCode}',
    );
  }

  Future<void> _commitDraftSet(SessionExerciseInfo info, _DraftSet draft) async {
    final reps = int.tryParse(draft.reps.text.trim());
    if (reps == null || reps <= 0) {
      _showMessage('Enter valid reps.');
      return;
    }
    final weightRaw = draft.weight.text.trim();
    final weight = weightRaw.isEmpty ? null : double.tryParse(weightRaw);
    _pushSetDebug(
      '[commit] start ex=${info.sessionExerciseId} reps=$reps weight=$weight',
    );
    _isLoggingSet = true;
    try {
      final beforeSets = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
      _pushSetDebug('[commit] beforeCount=${beforeSets.length} rows=${_summarizeSetRows(beforeSets)}');
      await _logInlineSet(info, reps: reps, weight: weight);
      final afterSets = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
      _pushSetDebug('[commit] afterCount=${afterSets.length} rows=${_summarizeSetRows(afterSets)}');
      if (afterSets.length <= beforeSets.length) {
        _showMessage('Set not saved. Try again.');
        return;
      }
      final list = _draftSetsByExerciseId[info.sessionExerciseId];
      list?.remove(draft);
      draft.dispose();
      _refreshInlineSetData(info);
      if (!mounted) return;
      setState(() {});
    } finally {
      _isLoggingSet = false;
    }
  }

  void _pushSetDebug(String message) {
    if (!_showSetDebug) return;
    final stamp = DateTime.now().toIso8601String().split('T').last;
    final entry = '$stamp $message';
    _setDebugNotes.add(entry);
    if (_setDebugNotes.length > 12) {
      _setDebugNotes.removeRange(0, _setDebugNotes.length - 12);
    }
    debugPrint(entry);
  }

  String _summarizeParts(List<String> parts, {int max = 6}) {
    if (parts.isEmpty) return '—';
    if (parts.length <= max) return parts.join(', ');
    final preview = parts.take(max).join(', ');
    return '$preview, …+${parts.length - max}';
  }

  String _summarizeSetRows(List<Map<String, Object?>> rows) {
    final parts = <String>[];
    for (final row in rows) {
      final id = row['id'] as int?;
      final index = row['set_index'] as int?;
      final reps = row['reps'] as int?;
      final weight = row['weight_value'] as num?;
      final weightLabel = _formatSetWeight(weight);
      parts.add('${id ?? '?'}:${index ?? '?'} ${weightLabel}x${reps ?? '?'}');
    }
    return _summarizeParts(parts);
  }

  String _summarizePreviousRows(List<Map<String, Object?>> rows) {
    final parts = <String>[];
    for (final row in rows) {
      final index = row['set_index'] as int?;
      final reps = row['reps'] as int?;
      final weight = row['weight_value'] as num?;
      final weightLabel = _formatSetWeight(weight);
      parts.add('${index ?? '?'}:${weightLabel}x${reps ?? '?'}');
    }
    return _summarizeParts(parts);
  }

  void _logInlineSnapshot(
    SessionExerciseInfo info,
    List<Map<String, Object?>> sets,
    List<Map<String, Object?>> previousSets,
    List<_DraftSet> drafts, {
    required String source,
  }) {
    if (!_showSetDebug) return;
    final draftCount = drafts.length;
    final summary =
        '[snapshot:$source] ex=${info.sessionExerciseId} sets=${sets.length} '
        '(${_summarizeSetRows(sets)}) '
        'prev=${previousSets.length} (${_summarizePreviousRows(previousSets)}) '
        'drafts=$draftCount';
    final last = _inlineDebugSnapshot[info.sessionExerciseId];
    if (last == summary) return;
    _inlineDebugSnapshot[info.sessionExerciseId] = summary;
    _pushSetDebug(summary);
  }

  Widget _buildInlineSets(
    BuildContext context,
    SessionExerciseInfo info,
    List<Map<String, Object?>> sets,
    List<Map<String, Object?>> previousSets,
    List<_DraftSet> drafts, {
    String renderSource = 'render',
  }
  ) {
    var volume = 0.0;
    for (final row in sets) {
      final weight = row['weight_value'] as num?;
      final reps = row['reps'] as int?;
      if (weight != null && reps != null) {
        volume += weight.toDouble() * reps;
      }
    }
    _logInlineSnapshot(info, sets, previousSets, drafts, source: renderSource);
    final restSeconds = _restSecondsForExercise(info);
    final volumeLabel = volume == 0 ? '—' : volume.toStringAsFixed(0);
    const setColWidth = 32.0;
    const prevColWidth = 96.0;
    const weightColWidth = 64.0;
    const repsColWidth = 52.0;
    const checkColWidth = 32.0;
    const colGap = 10.0;
    final headerStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          letterSpacing: 0.4,
        );
    final restController = AppShellController.instance;
    final activeRestSetId = restController.restActiveSetId;
    final activeRestStartedAt = restController.restStartedAt;
    final activeRestDuration = restController.restDurationSeconds;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Sets ${sets.length + drafts.length}'),
            const SizedBox(width: 12),
            Text('Volume $volumeLabel'),
            const Spacer(),
            TextButton.icon(
              onPressed: () => _showRestPicker(info, restSeconds),
              icon: const Icon(Icons.timer, size: 16),
              label: Text('Rest ${_formatRestShort(restSeconds)}'),
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                visualDensity: VisualDensity.compact,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        if (sets.isEmpty && drafts.isEmpty)
          Text(
            'No sets yet.',
            style: Theme.of(context).textTheme.bodySmall,
          )
        else ...[
          Container(
            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surface.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                SizedBox(
                  width: setColWidth,
                  child: Center(child: Text('Set', style: headerStyle)),
                ),
                const SizedBox(width: colGap),
                SizedBox(
                  width: prevColWidth,
                  child: Center(child: Text('Previous', style: headerStyle)),
                ),
                const SizedBox(width: colGap),
                SizedBox(
                  width: weightColWidth,
                  child: Center(child: Text(_weightUnit, style: headerStyle)),
                ),
                const SizedBox(width: colGap),
                SizedBox(
                  width: repsColWidth,
                  child: Center(child: Text('Reps', style: headerStyle)),
                ),
                const SizedBox(width: colGap),
                SizedBox(
                  width: checkColWidth,
                  child: Text('', style: headerStyle),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          for (var i = 0; i < sets.length; i++)
            Builder(
              builder: (context) {
                final row = sets[i];
                final setNumber = i + 1;
                final previousRow = i < previousSets.length ? previousSets[i] : null;
                final restSecondsActual =
                    (row['rest_sec_actual'] as int?) ?? _restSecondsForExercise(info);
                final createdAt = DateTime.tryParse((row['created_at'] as String?) ?? '');
                final rowId = row['id'] as int?;
                final isActive = rowId != null && rowId == activeRestSetId;
                final effectiveRestSeconds =
                    isActive && activeRestDuration > 0 ? activeRestDuration : restSecondsActual;
                final hasRest = effectiveRestSeconds > 0;
                final startedAt = isActive ? activeRestStartedAt ?? createdAt : null;
                final elapsed = startedAt == null ? 0 : _inlineRestNow.difference(startedAt).inSeconds;
                final remaining = isActive && hasRest
                    ? (effectiveRestSeconds - elapsed).clamp(0, effectiveRestSeconds)
                    : 0;
                final progress = isActive && hasRest && effectiveRestSeconds > 0
                    ? remaining / effectiveRestSeconds
                    : 0.0;
                final displayProgress = hasRest ? (isActive ? progress : 1.0) : 0.0;
                final rowContent = Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                      decoration: BoxDecoration(
                        color: Colors.green.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Row(
                        children: [
                          SizedBox(
                            width: setColWidth,
                            child: Center(child: Text('$setNumber')),
                          ),
                          const SizedBox(width: colGap),
                          SizedBox(
                            width: prevColWidth,
                            child: Center(child: Text(_formatPrevious(previousRow))),
                          ),
                          const SizedBox(width: colGap),
                          SizedBox(
                            width: weightColWidth,
                            child: Center(
                              child: Text(_formatSetWeight(row['weight_value'] as num?)),
                            ),
                          ),
                          const SizedBox(width: colGap),
                          SizedBox(
                            width: repsColWidth,
                            child: Center(
                              child: Text((row['reps'] as int?)?.toString() ?? '—'),
                            ),
                          ),
                          const SizedBox(width: colGap),
                          SizedBox(
                            width: checkColWidth,
                            child: Center(
                              child: IconButton(
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                icon: Icon(
                                  Icons.check_circle,
                                  size: 18,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                                tooltip: 'Undo set',
                                onPressed: () => _undoCompletedSet(info, row),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (hasRest)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 2, 8, 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: TweenAnimationBuilder<double>(
                                tween: Tween(begin: displayProgress, end: displayProgress),
                                duration: const Duration(milliseconds: 250),
                                builder: (context, value, _) {
                                  return ClipRRect(
                                    borderRadius: BorderRadius.circular(6),
                                    child: LinearProgressIndicator(
                                      value: value,
                                      minHeight: 6,
                                      backgroundColor:
                                          Theme.of(context).colorScheme.surface.withOpacity(0.25),
                                      color: isActive
                                          ? Theme.of(context).colorScheme.primary
                                          : Colors.greenAccent.shade400,
                                    ),
                                  );
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              isActive ? _formatRestShort(remaining) : 'Done',
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: isActive ? null : Colors.greenAccent.shade200,
                                  ),
                            ),
                            if (isActive) ...[
                              const SizedBox(width: 6),
                              IconButton(
                                onPressed: _completeInlineRest,
                                padding: EdgeInsets.zero,
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.check_circle, size: 18),
                                tooltip: 'Complete rest',
                              ),
                            ] else if (rowId != null) ...[
                              const SizedBox(width: 6),
                              TextButton(
                                onPressed: () => _startInlineRest(
                                  setId: rowId,
                                  restSeconds: restSecondsActual,
                                  exerciseId: info.exerciseId,
                                ),
                                style: TextButton.styleFrom(
                                  padding: EdgeInsets.zero,
                                  minimumSize: Size.zero,
                                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                  visualDensity: VisualDensity.compact,
                                ),
                                child: const Text('Undo'),
                              ),
                            ],
                          ],
                        ),
                      ),
                  ],
                );
                final setId = row['id'] as int?;
                if (setId == null) return rowContent;
                return Dismissible(
                  key: ValueKey('set-$setId'),
                  direction: DismissDirection.startToEnd,
                  dismissThresholds: const {
                    DismissDirection.startToEnd: 0.35,
                  },
                  confirmDismiss: (_) async {
                    _pushSetDebug('[swipe] saved id=$setId');
                    return !_isLoggingSet;
                  },
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => _deleteSet(setId, info),
                  child: rowContent,
                );
              },
            ),
          for (var i = 0; i < drafts.length; i++)
            Builder(
              builder: (context) {
                final setNumber = sets.length + i + 1;
                final previousRow =
                    (sets.length + i) < previousSets.length ? previousSets[sets.length + i] : null;
                final rowContent = Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
                  child: Row(
                    children: [
                      SizedBox(
                        width: setColWidth,
                        child: Center(child: Text('$setNumber')),
                      ),
                      const SizedBox(width: colGap),
                      SizedBox(
                        width: prevColWidth,
                        child: Center(child: Text(_formatPrevious(previousRow))),
                      ),
                      const SizedBox(width: colGap),
                      SizedBox(
                        width: weightColWidth,
                        child: TextField(
                          controller: drafts[i].weight,
                          keyboardType: const TextInputType.numberWithOptions(decimal: true),
                          textAlign: TextAlign.center,
                          onTap: () => _setActiveExercise(info),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: colGap),
                      SizedBox(
                        width: repsColWidth,
                        child: TextField(
                          controller: drafts[i].reps,
                          keyboardType: TextInputType.number,
                          textAlign: TextAlign.center,
                          onTap: () => _setActiveExercise(info),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                            border: OutlineInputBorder(),
                          ),
                        ),
                      ),
                      const SizedBox(width: colGap),
                      SizedBox(
                        width: checkColWidth,
                        child: IconButton(
                          padding: EdgeInsets.zero,
                          visualDensity: VisualDensity.compact,
                          icon: Icon(
                            Icons.check_circle,
                            size: 20,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          onPressed: () {
                            _setActiveExercise(info);
                            _commitDraftSet(info, drafts[i]);
                          },
                        ),
                      ),
                    ],
                  ),
                );
                return Dismissible(
                  key: ValueKey('draft-${info.sessionExerciseId}-$i-${drafts[i].hashCode}'),
                  direction: DismissDirection.startToEnd,
                  dismissThresholds: const {
                    DismissDirection.startToEnd: 0.45,
                  },
                  confirmDismiss: (_) async {
                    _pushSetDebug('[swipe] draft ex=${info.sessionExerciseId} idx=$i');
                    return !_isLoggingSet;
                  },
                  background: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    alignment: Alignment.centerLeft,
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withOpacity(0.35),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.delete_outline),
                  ),
                  onDismissed: (_) => _removeDraftSet(info, drafts[i]),
                  child: rowContent,
                );
              },
            ),
        ],
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton(
            onPressed: () {
              _setActiveExercise(info);
              _showQuickAddSet(info);
            },
            style: OutlinedButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.surface.withOpacity(0.2),
              padding: const EdgeInsets.symmetric(vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('+ Add Set'),
          ),
        ),
      ],
    );
  }

  Future<void> _logInlineSet(
    SessionExerciseInfo info, {
    required int reps,
    double? weight,
  }) async {
    final existing = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    var maxIndex = 0;
    for (final row in existing) {
      final value = row['set_index'] as int?;
      if (value != null && value > maxIndex) {
        maxIndex = value;
      }
    }
    final setIndex = maxIndex + 1;
    final planResult = SetPlanService().nextExpected(
      blocks: info.planBlocks,
      existingSets: existing,
    );
    final role = planResult?.nextRole ?? 'TOP';
    final isAmrap = planResult?.isAmrap ?? false;
    final restSeconds = _restSecondsForExercise(info);
    _pushSetDebug(
      '[log] ex=${info.sessionExerciseId} setIndex=$setIndex role=$role reps=$reps weight=$weight',
    );
    final id = await _workoutRepo.addSetEntry(
      sessionExerciseId: info.sessionExerciseId,
      setIndex: setIndex,
      setRole: role,
      weightValue: weight,
      weightUnit: _weightUnit,
      weightMode: info.weightModeDefault,
      reps: reps,
      partialReps: 0,
      rpe: null,
      rir: null,
      flagWarmup: role == 'WARMUP',
      flagPartials: false,
      isAmrap: isAmrap,
      restSecActual: restSeconds,
    );
    _startInlineRest(setId: id, restSeconds: restSeconds, exerciseId: info.exerciseId);
    _pushSetDebug('[log] inserted id=$id');
    final latest = await _workoutRepo.getSetEntryById(id);
    final setsForExercise = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    _pushSetDebug(
      '[log] ex=${info.sessionExerciseId} nowCount=${setsForExercise.length} '
      'rows=${_summarizeSetRows(setsForExercise)}',
    );
    final roleLabel = latest?['set_role'] as String? ?? 'TOP';
    final isAmrapLabel = (latest?['is_amrap'] as int? ?? 0) == 1;
    if (!mounted) return;
    setState(() {
      _lastLogged = LastLoggedSet(
        exerciseName: info.exerciseName,
        reps: reps,
        weight: weight,
        role: roleLabel,
        isAmrap: isAmrapLabel,
        sessionSetCount: setsForExercise.length,
      );
      _lastExerciseInfo = info;
      _prompt = null;
      _pending = null;
    });
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
        await _logSetFromVoice(
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
      await _logSetFromVoice(
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
      await _logSetFromVoice(
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
    if (_lastExerciseInfo == null && _sessionExercises.length == 1) {
      return _sessionExercises.first;
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

    await _logSetFromVoice(
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

  Future<void> _logSetFromVoice(
    SessionExerciseInfo info, {
    required int reps,
    double? weight,
    String weightUnit = 'lb',
    int? partials,
    double? rpe,
    double? rir,
  }) async {
    final drafts = _draftSetsByExerciseId[info.sessionExerciseId];
    final canUseDraft = (drafts != null && drafts.isNotEmpty) &&
        (partials == null && rpe == null && rir == null) &&
        (weight == null || weightUnit == _weightUnit);
    if (canUseDraft) {
      final draft = drafts!.first;
      draft.reps.text = reps.toString();
      draft.weight.text = weight == null ? '' : _formatSetWeight(weight);
      await _commitDraftSet(info, draft);
      return;
    }
    await _logSet(
      info,
      reps: reps,
      weight: weight,
      weightUnit: weightUnit,
      partials: partials,
      rpe: rpe,
      rir: rir,
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
    final restSeconds = _restSecondsForExercise(info);
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
        restSecActual: restSeconds,
      ),
    );
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    final latest = await _workoutRepo.getLatestSetForSessionExercise(info.sessionExerciseId);
    final setsForExercise = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    final role = latest?['set_role'] as String? ?? 'TOP';
    final isAmrap = (latest?['is_amrap'] as int? ?? 0) == 1;
    final latestId = latest?['id'] as int?;
    if (latestId != null) {
      _startInlineRest(
        setId: latestId,
        restSeconds: restSeconds,
        exerciseId: info.exerciseId,
      );
    }
    _refreshInlineSetData(info);
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

  Future<void> _updateSet(
    int id, {
    double? weight,
    int? reps,
    int? partials,
    double? rpe,
    double? rir,
    int? restSecActual,
  }) async {
    final result = await _dispatcher.dispatch(
      UpdateSetEntry(
        id: id,
        weight: weight,
        reps: reps,
        partials: partials,
        rpe: rpe,
        rir: rir,
        restSecActual: restSecActual,
      ),
    );
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    setState(() {});
  }

  Future<void> _deleteSet(int id, SessionExerciseInfo info) async {
    if (_isLoggingSet) return;
    final beforeSets = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    _pushSetDebug(
      '[delete] ex=${info.sessionExerciseId} id=$id beforeCount=${beforeSets.length} '
      'rows=${_summarizeSetRows(beforeSets)}',
    );
    final result = await _dispatcher.dispatch(DeleteSetEntry(id));
    if (result.inverse != null) {
      _undoRedo.pushUndo(result.inverse!);
    }
    final afterSets = await _workoutRepo.getSetsForSessionExercise(info.sessionExerciseId);
    _pushSetDebug(
      '[delete] ex=${info.sessionExerciseId} id=$id afterCount=${afterSets.length} '
      'rows=${_summarizeSetRows(afterSets)}',
    );
    _refreshInlineSetData(info);
    if (AppShellController.instance.restActiveSetId == id) {
      _completeInlineRest();
    }
    if (!mounted) return;
    setState(() {});
  }

  void _removeDraftSet(SessionExerciseInfo info, _DraftSet draft) {
    final list = _draftSetsByExerciseId[info.sessionExerciseId];
    if (list == null) return;
    _pushSetDebug('[draft-delete] ex=${info.sessionExerciseId}');
    list.remove(draft);
    draft.dispose();
    if (!mounted) return;
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

  void _setActiveExercise(SessionExerciseInfo info) {
    if (_lastExerciseInfo?.sessionExerciseId == info.sessionExerciseId) return;
    _lastExerciseInfo = info;
  }

  void _startRestTimer([int seconds = 120]) {
    AppShellController.instance.startRestTimer(seconds: seconds);
  }

  void _stopRestTimer() {
    AppShellController.instance.completeRestTimer();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handlePendingSessionVoice() async {
    if (!mounted || _handlingPendingSessionVoice) return;
    final pending = AppShellController.instance.pendingSessionVoice.value;
    if (pending == null || pending.trim().isEmpty) return;
    _handlingPendingSessionVoice = true;
    AppShellController.instance.clearPendingSessionVoice();
    try {
      await _handleVoiceInput(pending.trim());
    } finally {
      _handlingPendingSessionVoice = false;
    }
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
          final text = error.toString();
          if (text.contains('Microphone permission denied')) {
            _showMessage('Microphone access is disabled. Enable it in Settings > Ora.');
          } else {
            _showMessage('Voice error: $error');
          }
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
      _draftSetsByExerciseId.putIfAbsent(info.sessionExerciseId, () => []).add(_DraftSet());
      _currentDayExerciseNames = _sessionExercises.map((e) => e.exerciseName).toList();
      _lastExerciseInfo = info;
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

  Future<void> _promptAddExercise() async {
    final match = await Navigator.of(context).push<ExerciseMatch>(
      MaterialPageRoute(
        builder: (_) => const ExerciseCatalogScreen(selectionMode: true),
      ),
    );
    if (match == null || !mounted) return;
    final existing = _exerciseById[match.id];
    if (existing != null) {
      return;
    }
    await _addExerciseToSession(match);
  }

  @override
  Widget build(BuildContext context) {
    final startedAt = _sessionStartedAt;
    final endedAt = _sessionEndedAt;
    final sessionTimer = startedAt == null
        ? null
        : _formatSessionTimer((endedAt ?? _inlineRestNow).difference(startedAt));
    return Scaffold(
      appBar: AppBar(
        centerTitle: true,
        title: sessionTimer == null
            ? const Text('Session')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Session'),
                  Text(
                    sessionTimer,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70),
                  ),
                ],
              ),
        actions: [
          if (widget.isEditing) ...[
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Finish'),
            ),
            const SizedBox(width: 12),
          ] else ...[
            TextButton(
              onPressed: () async {
                await _workoutRepo.deleteSession(widget.contextData.sessionId);
                _sessionEnded = true;
                AppShellController.instance.setActiveSession(false);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Cancel'),
            ),
            const SizedBox(width: 8),
            ElevatedButton(
              onPressed: () async {
                await _workoutRepo.endSession(widget.contextData.sessionId);
                _sessionEnded = true;
                AppShellController.instance.setActiveSession(false);
                if (!mounted) return;
                Navigator.of(context).pop();
              },
              child: const Text('Finish'),
            ),
            const SizedBox(width: 12),
          ],
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
                  itemCount: _sessionExercises.length + 1,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, index) {
                    if (index == _sessionExercises.length) {
                      return GlassCard(
                        padding: const EdgeInsets.all(12),
                        child: InkWell(
                          borderRadius: BorderRadius.circular(12),
                          onTap: _promptAddExercise,
                          child: SizedBox(
                            width: double.infinity,
                            child: Row(
                              children: [
                                const Icon(Icons.add_circle_outline, size: 18),
                                const SizedBox(width: 8),
                                Text(
                                  'Add Exercise',
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                        ),
                      );
                    }
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
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                          backgroundColor: primaryColor.withOpacity(0.22),
                          labelStyle: TextStyle(
                            color: primaryColor,
                            fontWeight: FontWeight.w600,
                            fontSize: 11,
                          ),
                          side: BorderSide(color: primaryColor.withOpacity(0.6)),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }
                    for (final secondary in muscles?.secondary ?? const []) {
                      muscleChips.add(
                        Chip(
                          label: Text(secondary),
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                          backgroundColor: secondaryColor.withOpacity(0.18),
                          labelStyle: TextStyle(
                            color: secondaryColor,
                            fontWeight: FontWeight.w500,
                            fontSize: 11,
                          ),
                          side: BorderSide(color: secondaryColor.withOpacity(0.5)),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }
                    for (final tag in tags) {
                      muscleChips.add(
                        Chip(
                          label: Text(tag, style: const TextStyle(fontSize: 11)),
                          visualDensity: const VisualDensity(horizontal: -2, vertical: -2),
                          backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.2),
                          labelPadding: const EdgeInsets.symmetric(horizontal: 6),
                          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        ),
                      );
                    }
                    return GlassCard(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  info.exerciseName,
                                  style: Theme.of(context).textTheme.titleMedium,
                                ),
                              ),
                              IconButton(
                                onPressed: () => _openExerciseModal(info),
                                icon: const Icon(Icons.edit, size: 18),
                                tooltip: 'Edit sets',
                                visualDensity: VisualDensity.compact,
                              ),
                            ],
                          ),
                          if (muscleChips.isNotEmpty)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Wrap(
                                spacing: 6,
                                runSpacing: 6,
                                children: muscleChips,
                              ),
                            ),
                          const SizedBox(height: 8),
                          FutureBuilder<_InlineSetData>(
                            future: _getInlineSetFuture(info),
                            builder: (context, snapshot) {
                              final cached = _inlineSetCache[info.sessionExerciseId];
                              if (snapshot.hasError) {
                                _pushSetDebug(
                                  '[builder] ex=${info.sessionExerciseId} error=${snapshot.error}',
                                );
                              }
                              final useCache = (snapshot.connectionState != ConnectionState.done ||
                                      snapshot.hasError ||
                                      snapshot.data == null) &&
                                  cached != null;
                              final sets = useCache ? cached!.sets : snapshot.data?.sets ?? [];
                              final previousSets =
                                  useCache ? cached!.previousSets : snapshot.data?.previousSets ?? [];
                              final drafts =
                                  _draftSetsByExerciseId[info.sessionExerciseId] ?? const <_DraftSet>[];
                              return _buildInlineSets(
                                context,
                                info,
                                sets,
                                previousSets,
                                drafts,
                                renderSource: useCache ? 'render-cache' : 'render-snapshot',
                              );
                            },
                          ),
                        ],
                      ),
                    );
                  },
                ),
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
