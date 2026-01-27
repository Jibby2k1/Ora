import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter/services.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/program_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/services/calorie_service.dart';
import '../../../domain/services/session_service.dart';
import '../day_picker/day_picker_screen.dart';
import '../history/exercise_catalog_screen.dart';
import '../session/session_screen.dart';
import '../shell/app_shell_controller.dart';
import '../../../core/input/input_router.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'program_editor_screen.dart';

class _ProgramDayMatch {
  const _ProgramDayMatch({
    required this.dayId,
    required this.dayIndex,
    required this.dayName,
    required this.matchingExercises,
  });

  final int dayId;
  final int dayIndex;
  final String dayName;
  final List<String> matchingExercises;
}

enum _VoiceDayChoiceType { freeStyle, programDay }


class _VoiceDayChoice {
  const _VoiceDayChoice.freeStyle() : type = _VoiceDayChoiceType.freeStyle, programDayId = null;
  const _VoiceDayChoice.programDay(this.programDayId) : type = _VoiceDayChoiceType.programDay;

  final _VoiceDayChoiceType type;
  final int? programDayId;
}

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  static const int _createProgramId = -1;

  late final ProgramRepo _programRepo;
  late final WorkoutRepo _workoutRepo;
  late final SessionService _sessionService;
  late final SettingsRepo _settingsRepo;
  late final CalorieService _calorieService;
  int? _selectedProgramId;
  String? _selectedProgramName;
  bool _appearanceProfileEnabled = false;
  String _appearanceSex = 'neutral';
  List<String> _relevantMuscles = const [];
  List<Map<String, Object?>> _programDays = const [];
  int? _selectedDayId;
  String? _selectedDayName;
  bool _handlingInput = false;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _programRepo = ProgramRepo(db);
    _workoutRepo = WorkoutRepo(db);
    _sessionService = SessionService(db);
    _settingsRepo = SettingsRepo(db);
    _calorieService = CalorieService(db);
    AppShellController.instance.appearanceProfileEnabled.addListener(_syncAppearancePrefsFromController);
    AppShellController.instance.appearanceProfileSex.addListener(_syncAppearancePrefsFromController);
    AppShellController.instance.pendingInput.addListener(_handlePendingInput);
    AppShellController.instance.programsRevision.addListener(_handleProgramsRefresh);
    _loadAppearancePrefs();
    _loadProgramDays();
  }

  @override
  void dispose() {
    AppShellController.instance.appearanceProfileEnabled.removeListener(_syncAppearancePrefsFromController);
    AppShellController.instance.appearanceProfileSex.removeListener(_syncAppearancePrefsFromController);
    AppShellController.instance.pendingInput.removeListener(_handlePendingInput);
    AppShellController.instance.programsRevision.removeListener(_handleProgramsRefresh);
    super.dispose();
  }

  void _handleProgramsRefresh() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _handlePendingInput() async {
    if (!mounted || _handlingInput) return;
    final dispatch = AppShellController.instance.pendingInput.value;
    if (dispatch == null) return;
    if (dispatch.intent != InputIntent.trainingLog) {
      return;
    }
    _handlingInput = true;
    AppShellController.instance.clearPendingInput();
    final transcript = dispatch.event.text?.trim();
    if (transcript != null && transcript.isNotEmpty) {
      final displayText = dispatch.entity ?? transcript;
      if (dispatch.event.source == InputSource.mic) {
        final hasActive = await _workoutRepo.hasActiveSession();
        if (hasActive) {
          await _resumeActiveSessionWithVoice(transcript);
        } else {
          await _promptVoiceLogDaySelection(transcript, entity: dispatch.entity);
        }
      } else {
        await _confirmTrainingText(displayText, voiceTranscript: transcript);
      }
    }
    _handlingInput = false;
  }

  Future<void> _confirmTrainingText(String text, {String? voiceTranscript}) async {
    final approved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Training input'),
                const SizedBox(height: 8),
                Text(text),
                const SizedBox(height: 12),
                Row(
                  children: [
                    ElevatedButton.icon(
                      onPressed: () => Navigator.of(context).pop(true),
                      icon: const Icon(Icons.play_arrow),
                      label: const Text('Pick Day'),
                    ),
                    const SizedBox(width: 12),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(null),
                      child: const Text('Exercise'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(false),
                      child: const Text('Dismiss'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (approved == null) {
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ExerciseCatalogScreen(initialQuery: text)),
      );
      return;
    }
    if (approved != true) return;
    if (_selectedProgramId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a program first.')),
      );
      return;
    }
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DayPickerScreen(
          programId: _selectedProgramId!,
          initialVoiceInput: voiceTranscript,
        ),
      ),
    );
    await _syncActiveSessionBanner();
  }

  Future<void> _promptVoiceLogDaySelection(String text, {String? entity}) async {
    final programId = _selectedProgramId;
    if (programId == null) {
      await _confirmTrainingText(entity ?? text, voiceTranscript: text);
      return;
    }
    final matches = await _findMatchingProgramDays(
      programId: programId,
      text: text,
      entity: entity,
    );
    if (!mounted) return;
    final choice = await showModalBottomSheet<_VoiceDayChoice>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select day for logging'),
                const SizedBox(height: 8),
                Text(text),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(const _VoiceDayChoice.freeStyle()),
                    icon: const Icon(Icons.bolt),
                    label: const Text('Free Style'),
                  ),
                ),
                const SizedBox(height: 12),
                if (matches.isEmpty)
                  Text(
                    'No matching program day found.',
                    style: Theme.of(context).textTheme.bodySmall,
                  )
                else
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 240),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: matches.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 8),
                      itemBuilder: (context, index) {
                        final match = matches[index];
                        final preview = match.matchingExercises.take(3).join(', ');
                        final dayLabel = 'Day ${match.dayIndex + 1}';
                        final subtitle = preview.isEmpty ? dayLabel : '$dayLabel • $preview';
                        return ListTile(
                          tileColor: Theme.of(context).colorScheme.surface.withOpacity(0.2),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          title: Text(match.dayName),
                          subtitle: Text(subtitle),
                          trailing: const Icon(Icons.chevron_right),
                          onTap: () => Navigator.of(context).pop(_VoiceDayChoice.programDay(match.dayId)),
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (choice == null) return;
    if (choice.type == _VoiceDayChoiceType.freeStyle) {
      await _startFreeStyleSession(programId: programId, initialVoiceInput: text);
    } else if (choice.programDayId != null) {
      await _startProgramDaySession(choice.programDayId!, initialVoiceInput: text);
    }
  }

  Future<List<_ProgramDayMatch>> _findMatchingProgramDays({
    required int programId,
    required String text,
    String? entity,
  }) async {
    final days = await _programRepo.getProgramDays(programId);
    final namesByDay = await _programRepo.getExerciseNamesByDayForProgram(programId);
    final loweredText = text.toLowerCase();
    final loweredEntity = (entity ?? '').toLowerCase().trim();
    final matches = <_ProgramDayMatch>[];
    for (final day in days) {
      final dayId = day['id'] as int;
      final dayIndex = day['day_index'] as int;
      final dayName = day['day_name'] as String;
      final names = namesByDay[dayId] ?? const <String>[];
      final matched = <String>[];
      for (final name in names) {
        final loweredName = name.toLowerCase();
        final entityMatch = loweredEntity.isNotEmpty &&
            (loweredName == loweredEntity ||
                loweredName.contains(loweredEntity) ||
                loweredEntity.contains(loweredName));
        final textMatch = loweredText.contains(loweredName);
        if (entityMatch || textMatch) {
          matched.add(name);
        }
      }
      if (matched.isNotEmpty) {
        matches.add(
          _ProgramDayMatch(
            dayId: dayId,
            dayIndex: dayIndex,
            dayName: dayName,
            matchingExercises: matched,
          ),
        );
      }
    }
    return matches;
  }

  Future<void> _startFreeStyleSession({int? programId, String? initialVoiceInput}) async {
    final contextData = await _sessionService.startFreeSession(programId: programId);
    if (!mounted) return;
    if (initialVoiceInput != null && initialVoiceInput.trim().isNotEmpty) {
      AppShellController.instance.setPendingSessionVoice(initialVoiceInput.trim());
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
    await _syncActiveSessionBanner();
  }

  Future<void> _startProgramDaySession(int programDayId, {String? initialVoiceInput}) async {
    final programId = _selectedProgramId;
    if (programId == null) return;
    final contextData = await _sessionService.startSessionForProgramDay(
      programId: programId,
      programDayId: programDayId,
    );
    if (!mounted) return;
    if (initialVoiceInput != null && initialVoiceInput.trim().isNotEmpty) {
      AppShellController.instance.setPendingSessionVoice(initialVoiceInput.trim());
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
    await _syncActiveSessionBanner();
  }

  Future<void> _resumeActiveSessionWithVoice(String transcript) async {
    final contextData = await _sessionService.resumeActiveSession();
    if (contextData == null || !mounted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No active session found.')),
        );
      }
      return;
    }
    AppShellController.instance.setPendingSessionVoice(transcript.trim());
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
    await _syncActiveSessionBanner();
  }


  Future<void> _loadAppearancePrefs() async {
    final enabled = await _settingsRepo.getAppearanceProfileEnabled();
    final sex = await _settingsRepo.getAppearanceProfileSex();
    AppShellController.instance.setAppearanceProfileEnabled(enabled);
    AppShellController.instance.setAppearanceProfileSex(sex);
    _syncAppearancePrefsFromController();
  }

  void _syncAppearancePrefsFromController() {
    if (!mounted) return;
    final enabled = AppShellController.instance.appearanceProfileEnabled.value;
    final sex = AppShellController.instance.appearanceProfileSex.value;
    if (enabled == _appearanceProfileEnabled && sex == _appearanceSex) {
      return;
    }
    setState(() {
      _appearanceProfileEnabled = enabled;
      _appearanceSex = sex;
    });
  }

  Future<void> _syncActiveSessionBanner() async {
    final hasActive = await _workoutRepo.hasActiveSession();
    if (!mounted) return;
    AppShellController.instance.setActiveSession(hasActive);
    AppShellController.instance.setActiveSessionIndicatorHidden(false);
    AppShellController.instance.refreshActiveSession();
  }

  Future<void> _createProgram() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Program'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Program name'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final name = result ?? '';
    if (name.isEmpty) return;
    final programId = await _programRepo.createProgram(name: name);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProgramEditorScreen(programId: programId)),
    );
    setState(() {});
  }

  DateTimeRange _todayRange() {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    return DateTimeRange(start: start, end: end);
  }

  Widget _buildWorkoutCaloriesCard() {
    final range = _todayRange();
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: FutureBuilder<WorkoutCalorieEstimate>(
        future: _calorieService.estimateWorkoutCaloriesForRange(range.start, range.end),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final estimate = snapshot.data;
          if (estimate == null || estimate.setCount == 0) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Workout Burn (estimate)'),
                const SizedBox(height: 8),
                Text(
                  'No logged sets today yet.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          }
          final workout = estimate.workoutCalories;
          final bmr = estimate.bmrCalories;
          final total = estimate.totalCalories;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Workout Burn (estimate)'),
              const SizedBox(height: 8),
              Text(
                '${total.toStringAsFixed(0)} kcal',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              _CaloriesBar(workoutCalories: workout, bmrCalories: bmr),
              const SizedBox(height: 8),
              Wrap(
                spacing: 16,
                runSpacing: 8,
                children: [
                  Text('Workout ${workout.toStringAsFixed(0)} kcal'),
                  Text('BMR ${bmr.toStringAsFixed(0)} kcal'),
                  Text('${estimate.durationMinutes.toStringAsFixed(0)} min'),
                ],
              ),
              if (estimate.usedDefaultWeight || !estimate.bmrAvailable) ...[
                const SizedBox(height: 6),
                Text(
                  'Add age/height/weight in Profile for more accurate BMR.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _startManualDay() async {
    if (_selectedProgramId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a program first.')),
      );
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => DayPickerScreen(programId: _selectedProgramId!)),
    );
    await _syncActiveSessionBanner();
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _startSmartDay() async {
    if (_selectedProgramId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pick a program first.')),
      );
      return;
    }
    final days = await _programRepo.getProgramDays(_selectedProgramId!);
    if (days.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No days yet. Add one in the program editor.')),
      );
      return;
    }
    final lastIndex = await _workoutRepo.getLastCompletedDayIndex(_selectedProgramId!);
    final nextIndex = lastIndex == null ? 0 : (lastIndex + 1) % days.length;
    final day = days.firstWhere((d) => d['day_index'] == nextIndex, orElse: () => days.first);
    final contextData = await _sessionService.startSessionForProgramDay(
      programId: _selectedProgramId!,
      programDayId: day['id'] as int,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
    await _syncActiveSessionBanner();
  }

  Future<void> _loadProgramDays() async {
    if (_selectedProgramId == null) return;
    final days = await _programRepo.getProgramDays(_selectedProgramId!);
    if (days.isEmpty) {
      if (!mounted) return;
      setState(() => _relevantMuscles = const []);
      return;
    }
    final lastIndex = await _workoutRepo.getLastCompletedDayIndex(_selectedProgramId!);
    final nextIndex = lastIndex == null ? 0 : (lastIndex + 1) % days.length;
    final day = days.firstWhere((d) => d['day_index'] == nextIndex, orElse: () => days.first);
    _selectedDayId ??= day['id'] as int;
    _selectedDayName ??= day['day_name'] as String;
    _programDays = days;
    await _loadRelevantMuscles();
  }

  Future<void> _loadRelevantMuscles() async {
    if (_selectedDayId == null) return;
    final muscles = await _programRepo.getMusclesForProgramDay(_selectedDayId!);
    if (!mounted) return;
    setState(() {
      _relevantMuscles = muscles;
    });
  }

  void _showMuscleStats(String muscle) {
    final stats = _muscleStats[muscle] ?? const _MuscleStats(pr: '—', volume: '—', prCount: '—');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          muscle,
                          style: Theme.of(context).textTheme.titleLarge,
                        ),
                      ),
                      IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _AnatomyPreview(
                    muscle: muscle,
                    sex: _appearanceProfileEnabled ? _appearanceSex : 'neutral',
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _StatPill(label: 'PR', value: stats.pr),
                      _StatPill(label: 'Volume', value: stats.volume),
                      _StatPill(label: 'PR Count', value: stats.prCount),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Metrics include top set PRs, total volume, and PR count for the most recent automatic day.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Training'),
        actions: [
          IconButton(
            icon: const Icon(Icons.list),
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ExerciseCatalogScreen()),
              );
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          FutureBuilder<List<Map<String, Object?>>>(
            future: _programRepo.getPrograms(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final programs = snapshot.data ?? [];
              if (programs.isEmpty) {
                _selectedProgramId = null;
                _selectedProgramName = null;
                _selectedDayId = null;
                _selectedDayName = null;
                _programDays = [];
              } else {
                final selectedExists = _selectedProgramId != null &&
                    programs.any((program) => program['id'] == _selectedProgramId);
                if (!selectedExists) {
                  final first = programs.first;
                  _selectedProgramId = first['id'] as int;
                  _selectedProgramName = first['name'] as String;
                  _selectedDayId = null;
                  _selectedDayName = null;
                  _loadProgramDays();
                }
              }
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Start New Day'),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Program',
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedProgramId,
                              isExpanded: true,
                              items: programs
                                  .map(
                                    (program) => DropdownMenuItem<int>(
                                      value: program['id'] as int,
                                      child: Text(program['name'] as String),
                                    ),
                                  )
                                  .followedBy(
                                    const [
                                      DropdownMenuItem<int>(
                                        value: _createProgramId,
                                        child: Text('Create new program...'),
                                      ),
                                    ],
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                if (value == _createProgramId) {
                                  _createProgram();
                                  return;
                                }
                                final program = programs.firstWhere((p) => p['id'] == value);
                                setState(() {
                                  _selectedProgramId = value;
                                  _selectedProgramName = program['name'] as String;
                                  _selectedDayId = null;
                                  _selectedDayName = null;
                                });
                                _loadProgramDays();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _startManualDay,
                                icon: const Icon(Icons.view_list),
                                label: const Text('Manual Day'),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: _startSmartDay,
                                icon: const Icon(Icons.auto_awesome),
                                label: const Text('Smart Day'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _startFreeStyleSession(),
                            icon: const Icon(Icons.bolt),
                            label: const Text('Free day'),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Stats'),
                        const SizedBox(height: 12),
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Day',
                          ),
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<int>(
                              value: _selectedDayId,
                              isExpanded: true,
                              items: _programDays
                                  .map(
                                    (day) => DropdownMenuItem<int>(
                                      value: day['id'] as int,
                                      child: Text(day['day_name'] as String),
                                    ),
                                  )
                                  .toList(),
                              onChanged: (value) {
                                if (value == null) return;
                                final day = _programDays.firstWhere((d) => d['id'] == value);
                                setState(() {
                                  _selectedDayId = value;
                                  _selectedDayName = day['day_name'] as String;
                                });
                                _loadRelevantMuscles();
                              },
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                        GridView.count(
                          crossAxisCount: 2,
                          mainAxisSpacing: 8,
                          crossAxisSpacing: 8,
                          childAspectRatio: 3.0,
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          children: (_relevantMuscles.isEmpty ? _muscleOrder : _relevantMuscles)
                              .map(
                                (muscle) => OutlinedButton(
                                  onPressed: () => _showMuscleStats(muscle),
                                  style: OutlinedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                    visualDensity: VisualDensity.compact,
                                    textStyle: const TextStyle(fontSize: 12),
                                  ),
                                  child: Text(muscle, maxLines: 1, overflow: TextOverflow.ellipsis),
                                ),
                              )
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: programs.isEmpty
                        ? const Center(child: Text('Create your first program.'))
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Programs'),
                              const SizedBox(height: 8),
                              ...programs.map((program) {
                                final id = program['id'] as int;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: GlassCard(
                                    padding: EdgeInsets.zero,
                                    child: ListTile(
                                      title: Text(program['name'] as String),
                                      subtitle: const Text('Tap to start or edit days'),
                                      onTap: () async {
                                        await Navigator.of(context).push(
                                          MaterialPageRoute(builder: (_) => DayPickerScreen(programId: id)),
                                        );
                                        await _syncActiveSessionBanner();
                                        if (!mounted) return;
                                        setState(() {});
                                      },
                                      trailing: PopupMenuButton<String>(
                                        onSelected: (value) async {
                                          if (value == 'edit') {
                                            await Navigator.of(context).push(
                                              MaterialPageRoute(
                                                builder: (_) => ProgramEditorScreen(programId: id),
                                              ),
                                            );
                                            setState(() {});
                                          } else if (value == 'delete') {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (context) {
                                                return AlertDialog(
                                                  title: const Text('Delete program?'),
                                                  content: const Text(
                                                    'This removes the program and its days. Sessions remain in history.',
                                                  ),
                                                  actions: [
                                                    TextButton(
                                                      onPressed: () => Navigator.of(context).pop(false),
                                                      child: const Text('Cancel'),
                                                    ),
                                                    ElevatedButton(
                                                      onPressed: () => Navigator.of(context).pop(true),
                                                      child: const Text('Delete'),
                                                    ),
                                                  ],
                                                );
                                              },
                                            );
                                            if (confirm == true) {
                                              await _programRepo.deleteProgram(id);
                                              setState(() {});
                                            }
                                          }
                                        },
                                        itemBuilder: (_) => const [
                                          PopupMenuItem(value: 'edit', child: Text('Edit')),
                                          PopupMenuItem(value: 'delete', child: Text('Delete')),
                                        ],
                                      ),
                                    ),
                                  ),
                                );
                              }),
                            ],
                          ),
                  ),
                  const SizedBox(height: 24),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _StatPill extends StatelessWidget {
  const _StatPill({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Theme.of(context).colorScheme.primary.withOpacity(0.4)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(value, style: Theme.of(context).textTheme.titleMedium),
        ],
      ),
    );
  }
}

class _CaloriesBar extends StatelessWidget {
  const _CaloriesBar({required this.workoutCalories, required this.bmrCalories});

  final double workoutCalories;
  final double bmrCalories;

  @override
  Widget build(BuildContext context) {
    final total = (workoutCalories + bmrCalories).clamp(0.0, double.infinity);
    if (total <= 0) {
      return const SizedBox(height: 10);
    }
    final workoutFrac = (workoutCalories / total).clamp(0.0, 1.0);
    final bmrFrac = (bmrCalories / total).clamp(0.0, 1.0);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final workoutWidth = width * workoutFrac;
        final bmrWidth = width * bmrFrac;
        return SizedBox(
          height: 12,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Container(color: Theme.of(context).colorScheme.surface.withOpacity(0.4)),
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: workoutWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.primary.withOpacity(0.85),
                          Theme.of(context).colorScheme.primary.withOpacity(0.55),
                        ],
                      ),
                    ),
                  ),
                ),
                Positioned(
                  left: workoutWidth,
                  top: 0,
                  bottom: 0,
                  width: bmrWidth,
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Theme.of(context).colorScheme.secondary.withOpacity(0.7),
                          Theme.of(context).colorScheme.secondary.withOpacity(0.4),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AnatomyPreview extends StatefulWidget {
  const _AnatomyPreview({required this.muscle, required this.sex});

  final String muscle;
  final String sex;

  @override
  State<_AnatomyPreview> createState() => _AnatomyPreviewState();
}

class _AnatomyPreviewState extends State<_AnatomyPreview> {
  bool _showBack = false;
  Future<String>? _svgFuture;

  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _refreshSvg();
  }

  @override
  void didUpdateWidget(covariant _AnatomyPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.muscle != widget.muscle || oldWidget.sex != widget.sex) {
      _refreshSvg();
    }
  }

  void _refreshSvg() {
    final targets = _muscleTargets[widget.muscle] ??
        _muscleTargets[widget.muscle.toLowerCase()] ??
        const _MuscleSvgTargets(front: [], back: []);
    final highlightIds = _showBack ? targets.back : targets.front;
    final assets = _resolveAnatomyAssets(sex: widget.sex, isBack: _showBack);
    final future = _buildHighlightedSvg(
      asset: assets.primary,
      fallbackAsset: assets.fallback,
      highlightIds: highlightIds,
      highlightColor: Theme.of(context).colorScheme.primary,
    );
    if (!mounted) return;
    setState(() {
      _svgFuture = future;
    });
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 1.6).clamp(220.0, 320.0);
        return SizedBox(
          height: height,
          child: Stack(
            children: [
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: FutureBuilder<String>(
                    future: _svgFuture,
                    builder: (context, snapshot) {
                      if (snapshot.hasError) {
                        return Center(
                          child: Text(
                            'Unable to load anatomy asset.',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        );
                      }
                      if (!snapshot.hasData) {
                        return const Center(child: CircularProgressIndicator());
                      }
                      return SvgPicture.string(
                        snapshot.data!,
                        width: width,
                        height: height,
                        fit: BoxFit.contain,
                      );
                    },
                  ),
                ),
              ),
              Positioned(
                left: 0,
                top: 0,
                child: SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('Front')),
                    ButtonSegment(value: true, label: Text('Back')),
                  ],
                  selected: {_showBack},
                  onSelectionChanged: (value) {
                    setState(() {
                      _showBack = value.first;
                    });
                    _refreshSvg();
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _MuscleStats {
  const _MuscleStats({required this.pr, required this.volume, required this.prCount});

  final String pr;
  final String volume;
  final String prCount;
}

const List<String> _muscleOrder = [
  'Upper Chest',
  'Lower Chest',
  'Traps',
  'Lats',
  'Front Delts',
  'Side Delts',
  'Rear Delts',
  'Biceps',
  'Triceps',
  'Forearms',
  'Abs',
  'Glutes',
  'Quads',
  'Hamstrings',
  'Calves',
];

const Map<String, _MuscleStats> _muscleStats = {
  'Upper Chest': _MuscleStats(pr: '225 lb', volume: '8,200 lb', prCount: '2'),
  'Lower Chest': _MuscleStats(pr: '205 lb', volume: '6,300 lb', prCount: '1'),
  'Traps': _MuscleStats(pr: '365 lb', volume: '9,900 lb', prCount: '1'),
  'Lats': _MuscleStats(pr: '180 lb', volume: '7,100 lb', prCount: '2'),
  'Front Delts': _MuscleStats(pr: '95 lb', volume: '4,100 lb', prCount: '1'),
  'Side Delts': _MuscleStats(pr: '40 lb', volume: '2,900 lb', prCount: '0'),
  'Rear Delts': _MuscleStats(pr: '55 lb', volume: '2,200 lb', prCount: '0'),
  'Biceps': _MuscleStats(pr: '55 lb', volume: '3,400 lb', prCount: '1'),
  'Triceps': _MuscleStats(pr: '120 lb', volume: '4,000 lb', prCount: '1'),
  'Forearms': _MuscleStats(pr: '65 lb', volume: '1,900 lb', prCount: '0'),
  'Abs': _MuscleStats(pr: '90 lb', volume: '2,600 lb', prCount: '1'),
  'Glutes': _MuscleStats(pr: '315 lb', volume: '10,800 lb', prCount: '2'),
  'Quads': _MuscleStats(pr: '365 lb', volume: '11,200 lb', prCount: '2'),
  'Hamstrings': _MuscleStats(pr: '275 lb', volume: '8,900 lb', prCount: '1'),
  'Calves': _MuscleStats(pr: '160 lb', volume: '3,800 lb', prCount: '0'),
};

class _MuscleSvgTargets {
  const _MuscleSvgTargets({required this.front, required this.back});

  final List<String> front;
  final List<String> back;
}

const Map<String, _MuscleSvgTargets> _muscleTargets = {
  'Upper Chest': _MuscleSvgTargets(front: ['pectoralis_major'], back: []),
  'Lower Chest': _MuscleSvgTargets(front: ['pectoralis_major'], back: []),
  'Chest': _MuscleSvgTargets(front: ['pectoralis_major'], back: []),
  'Traps': _MuscleSvgTargets(front: ['trapezius'], back: ['trapezius_lower']),
  'Lats': _MuscleSvgTargets(front: [], back: ['latissimus_dorsi']),
  'Back': _MuscleSvgTargets(front: [], back: ['latissimus_dorsi', 'trapezius_lower']),
  'Front Delts': _MuscleSvgTargets(front: ['deltoid'], back: []),
  'Side Delts': _MuscleSvgTargets(front: ['deltoid'], back: ['deltoid']),
  'Rear Delts': _MuscleSvgTargets(front: [], back: ['deltoid']),
  'Biceps': _MuscleSvgTargets(front: ['biceps'], back: []),
  'Triceps': _MuscleSvgTargets(front: ['triceps'], back: ['triceps']),
  'Forearms': _MuscleSvgTargets(front: ['brachioradialis', 'finger_flexors'], back: ['brachioradialis', 'finger_flexors']),
  'Abs': _MuscleSvgTargets(front: ['abdominals', 'external_oblique'], back: []),
  'Glutes': _MuscleSvgTargets(front: [], back: ['gluteus_maximus']),
  'Quads': _MuscleSvgTargets(front: ['quadriceps'], back: []),
  'Hamstrings': _MuscleSvgTargets(front: [], back: ['hamstrings']),
  'Calves': _MuscleSvgTargets(front: ['gastrocnemius'], back: ['gastrocnemius', 'soleus']),
};

class _AnatomyAssetSet {
  const _AnatomyAssetSet({required this.primary, required this.fallback});

  final String primary;
  final String fallback;
}

_AnatomyAssetSet _resolveAnatomyAssets({required String sex, required bool isBack}) {
  final primaryBase =
      'assets/anatomy/codecanyon/codecanyon-I0qdAu3M-interactive-human-body-muscle-diagram-male-and-female-diagrams/source/with_tooltip_and_colours';
  final fallbackBase =
      'assets/anatomy/codecanyon/codecanyon-I0qdAu3M-interactive-human-body-muscle-diagram-male-and-female-diagrams/source/no_tooltip';
  if (sex == 'female') {
    return _AnatomyAssetSet(
      primary: isBack ? '$primaryBase/woman-back.svg' : '$primaryBase/woman-front.svg',
      fallback: isBack ? '$fallbackBase/woman-back.svg' : '$fallbackBase/woman-front.svg',
    );
  }
  return _AnatomyAssetSet(
    primary: isBack ? '$primaryBase/man-back.svg' : '$primaryBase/man-front.svg',
    fallback: isBack ? '$fallbackBase/man-back.svg' : '$fallbackBase/man-front.svg',
  );
}

Future<String> _buildHighlightedSvg({
  required String asset,
  String? fallbackAsset,
  required List<String> highlightIds,
  required Color highlightColor,
}) async {
  try {
    final raw = await rootBundle.loadString(asset);
    final base = _dimAllMuscles(raw);
    if (highlightIds.isEmpty) return base;
    var updated = base;
    for (final id in highlightIds) {
      updated = _highlightMuscle(updated, id, highlightColor);
    }
    return updated;
  } catch (error) {
    debugPrint('[Anatomy] Asset load failed: $asset ($error)');
    if (fallbackAsset != null) {
      try {
        final raw = await rootBundle.loadString(fallbackAsset);
        final base = _dimAllMuscles(raw);
        if (highlightIds.isEmpty) return base;
        var updated = base;
        for (final id in highlightIds) {
          updated = _highlightMuscle(updated, id, highlightColor);
        }
        return updated;
      } catch (fallbackError) {
        debugPrint('[Anatomy] Fallback asset load failed: $fallbackAsset ($fallbackError)');
      }
    }
    return '<svg xmlns=\"http://www.w3.org/2000/svg\" viewBox=\"0 0 260 80\">'
        '<text x=\"10\" y=\"44\" fill=\"#999\">Asset load failed</text>'
        '</svg>';
  }
}

String _dimAllMuscles(String svg) {
  return svg.replaceAllMapped(
    RegExp(r'<g id=\"([^\"]+)\" class=\"muscle\">'),
    (match) => '<g id=\"${match.group(1)}\" class=\"muscle\" opacity=\"0.18\">',
  );
}

String _highlightMuscle(String svg, String id, Color color) {
  final hex = '#${color.value.toRadixString(16).substring(2)}';
  final start = svg.indexOf('<g id=\"$id\"');
  if (start == -1) return svg;
  final end = svg.indexOf('</g>', start);
  if (end == -1) return svg;
  var segment = svg.substring(start, end);
  segment = segment.replaceFirst(
    RegExp(r'<g id=\"' + RegExp.escape(id) + r'\" class=\"muscle\"[^>]*>'),
    '<g id=\"$id\" class=\"muscle\" opacity=\"0.9\">',
  );
  segment = segment.replaceAllMapped(
    RegExp(r'fill=\"[^\"]+\"'),
    (_) => 'fill=\"$hex\"',
  );
  return svg.replaceRange(start, end, segment);
}
