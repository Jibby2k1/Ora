import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'session_edit_screen.dart';

enum HistoryMode { sessions, exercise }

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    this.initialExerciseId,
    this.embedded = false,
    this.mode = HistoryMode.sessions,
  });

  final int? initialExerciseId;
  final bool embedded;
  final HistoryMode mode;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  late final ExerciseRepo _exerciseRepo;
  late final WorkoutRepo _workoutRepo;

  Map<String, Object?>? _selectedExercise;
  String _range = 'Month';
  String _metric = 'Weight';
  late final Future<List<Map<String, Object?>>> _exerciseFuture;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _exerciseRepo = ExerciseRepo(db);
    _workoutRepo = WorkoutRepo(db);
    _exerciseFuture = _exerciseRepo.getAll();
  }

  Future<void> _pickExercise() async {
    final result = await showModalBottomSheet<Map<String, Object?>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _ExerciseSearchSheet(exerciseRepo: _exerciseRepo),
    );
    if (result == null) return;
    setState(() {
      _selectedExercise = result;
    });
  }

  DateTime _rangeStart(String range) {
    final now = DateTime.now();
    switch (range) {
      case 'Day':
        return now.subtract(const Duration(days: 1));
      case 'Week':
        return now.subtract(const Duration(days: 7));
      case '3 Months':
        return now.subtract(const Duration(days: 90));
      case 'Year':
        return now.subtract(const Duration(days: 365));
      case 'Month':
      default:
        return now.subtract(const Duration(days: 30));
    }
  }

  Future<_HistoryData> _loadData() async {
    final selected = _selectedExercise;
    if (selected == null) {
      return _HistoryData.empty();
    }
    final exerciseId = selected['id'] as int;
    final since = _rangeStart(_range);
    final sets = await _workoutRepo.getExerciseSetsSince(exerciseId, since);
    return _HistoryData(sets: sets, exerciseName: selected['canonical_name'] as String);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  String _formatDuration(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes;
    if (minutes < 1) return '<1 min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<void> _openSessionEditor(Map<String, Object?> row) async {
    final sessionId = row['id'] as int?;
    if (sessionId == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SessionEditScreen(sessionId: sessionId),
      ),
    );
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _deleteSession(Map<String, Object?> row) async {
    final sessionId = row['id'] as int?;
    if (sessionId == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Day?'),
          content: const Text('This will permanently remove the workout day and all its sets.'),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('Delete'),
            ),
          ],
        );
      },
    );
    if (confirmed != true) return;
    await _workoutRepo.deleteSession(sessionId);
    if (!mounted) return;
    setState(() {});
  }

  Widget _buildSessionHistoryContent({required bool includePadding}) {
    final content = FutureBuilder<List<Map<String, Object?>>>(
      future: _workoutRepo.getCompletedSessions(limit: 200),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        final rows = snapshot.data ?? [];
        if (rows.isEmpty) {
          return const Center(child: Text('No completed sessions yet.'));
        }
        return ListView.separated(
          itemCount: rows.length,
          separatorBuilder: (_, __) => const SizedBox(height: 8),
          itemBuilder: (context, index) {
            final row = rows[index];
            final startedAt = DateTime.tryParse(row['started_at'] as String? ?? '');
            final endedAt = DateTime.tryParse(row['ended_at'] as String? ?? '');
            final programName = row['program_name'] as String?;
            final dayName = row['day_name'] as String?;
            final dayIndex = row['day_index'] as int?;
            final notes = row['notes'] as String?;
            final exerciseCount = (row['exercise_count'] as int?) ?? 0;
            final setCount = (row['set_count'] as int?) ?? 0;

            final customTitle = notes == null || notes.trim().isEmpty ? null : notes.trim();
            final title = customTitle ??
                ((dayName != null && dayName.trim().isNotEmpty) ? dayName : (programName ?? 'Empty Day'));
            final programLabel = programName == null || programName.trim().isEmpty
                ? 'Empty Day'
                : (dayIndex == null ? programName : '$programName • Day ${dayIndex + 1}');
            final dateLabel =
                startedAt == null ? 'Unknown date' : _formatDate(startedAt);
            final durationLabel = (startedAt != null && endedAt != null)
                ? _formatDuration(startedAt, endedAt)
                : '—';
            final statLabel = '$setCount sets • $exerciseCount exercises';
            final showProgramLabel = programLabel != title;
            final titleStyle = Theme.of(context)
                .textTheme
                .titleSmall
                ?.copyWith(fontWeight: FontWeight.w600);
            final metaStyle =
                Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white70);
            final subStyle =
                Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.white60, height: 1.2);

            return GlassCard(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: InkWell(
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SessionDetailScreen(sessionId: row['id'] as int),
                    ),
                  );
                },
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(child: Text(title, style: titleStyle)),
                              Text(dateLabel, style: metaStyle),
                            ],
                          ),
                          if (showProgramLabel) ...[
                            const SizedBox(height: 4),
                            Text(programLabel, style: subStyle),
                          ],
                          const SizedBox(height: 2),
                          Text('$durationLabel • $statLabel', style: subStyle),
                        ],
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: const Icon(Icons.more_horiz, size: 18),
                      onSelected: (value) {
                        if (value == 'edit') {
                          _openSessionEditor(row);
                        } else if (value == 'delete') {
                          _deleteSession(row);
                        }
                      },
                      itemBuilder: (context) => [
                        const PopupMenuItem(
                          value: 'edit',
                          child: Text('Edit day'),
                        ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Text('Delete day'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    if (!includePadding) return content;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: content,
    );
  }

  Widget _buildSessionHistory({required bool showBackground}) {
    final body = _buildSessionHistoryContent(includePadding: true);
    if (!showBackground) {
      return _buildSessionHistoryContent(includePadding: false);
    }
    return Stack(
      children: [
        const GlassBackground(),
        body,
      ],
    );
  }

  Widget _buildHeaderControls() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: _pickExercise,
                child: Text(_selectedExercise == null
                    ? 'Pick Exercise'
                    : (_selectedExercise!['canonical_name'] as String)),
              ),
            ),
            const SizedBox(width: 8),
            DropdownButton<String>(
              value: _range,
              items: const [
                DropdownMenuItem(value: 'Day', child: Text('Day')),
                DropdownMenuItem(value: 'Week', child: Text('Week')),
                DropdownMenuItem(value: 'Month', child: Text('Month')),
                DropdownMenuItem(value: '3 Months', child: Text('3 Months')),
                DropdownMenuItem(value: 'Year', child: Text('Year')),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() {
                  _range = value;
                });
              },
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            ChoiceChip(
              label: const Text('Weight'),
              selected: _metric == 'Weight',
              onSelected: (_) => setState(() => _metric = 'Weight'),
            ),
            const SizedBox(width: 8),
            ChoiceChip(
              label: const Text('Weight × Reps'),
              selected: _metric == 'Volume',
              onSelected: (_) => setState(() => _metric = 'Volume'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBody({required bool showBackground, required bool includeHeader}) {
    final content = Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (includeHeader) ...[
            _buildHeaderControls(),
            const SizedBox(height: 16),
          ],
          FutureBuilder<List<Map<String, Object?>>>(
            future: _exerciseFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const SizedBox(height: 0);
              }
              final exercises = snapshot.data ?? [];
              if (exercises.isEmpty) return const SizedBox(height: 0);
              if (_selectedExercise == null) {
                WidgetsBinding.instance.addPostFrameCallback((_) {
                  if (!mounted) return;
                  final initial = widget.initialExerciseId == null
                      ? exercises.first
                      : exercises.firstWhere(
                          (ex) => ex['id'] == widget.initialExerciseId,
                          orElse: () => exercises.first,
                        );
                  setState(() {
                    _selectedExercise = initial;
                  });
                });
              }
              return const SizedBox(height: 0);
            },
          ),
          const SizedBox(height: 16),
          Expanded(
            child: FutureBuilder<_HistoryData>(
              future: _loadData(),
              builder: (context, snapshot) {
                final data = snapshot.data;
                if (_selectedExercise == null) {
                  return const Center(child: Text('Select an exercise to view history.'));
                }
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (data == null || data.sets.isEmpty) {
                  return const Center(child: Text('No sets in this range.'));
                }

                final series = _buildSeries(data.sets, metric: _metric);
                return GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        data.exerciseName,
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 180,
                        child: LineChart(
                          LineChartData(
                            gridData: const FlGridData(show: true),
                            titlesData: FlTitlesData(
                              leftTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 40,
                                  getTitlesWidget: (value, meta) {
                                    if (value == series.minY || value == series.maxY) {
                                      return Text(value.toStringAsFixed(0));
                                    }
                                    return const SizedBox.shrink();
                                  },
                                ),
                              ),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  reservedSize: 28,
                                  getTitlesWidget: (value, meta) {
                                    final index = value.toInt();
                                    if (index < 0 || index >= series.spots.length) {
                                      return const SizedBox.shrink();
                                    }
                                    final label = series.labels[index];
                                    return Text(label, style: const TextStyle(fontSize: 10));
                                  },
                                ),
                              ),
                              rightTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                              topTitles: const AxisTitles(
                                sideTitles: SideTitles(showTitles: false),
                              ),
                            ),
                            lineBarsData: [
                              LineChartBarData(
                                isCurved: true,
                                color: Theme.of(context).colorScheme.primary,
                                spots: series.spots,
                                dotData: const FlDotData(show: true),
                                belowBarData: BarAreaData(
                                  show: true,
                                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );

    if (!showBackground) return content;
    return Stack(
      children: [
        const GlassBackground(),
        content,
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.mode == HistoryMode.sessions) {
      if (widget.embedded) {
        return _buildSessionHistory(showBackground: false);
      }
      return Scaffold(
        appBar: AppBar(
          title: const Text('History'),
          actions: const [SizedBox(width: 72)],
        ),
        body: _buildSessionHistory(showBackground: true),
      );
    }
    if (widget.embedded) {
      return _buildBody(showBackground: false, includeHeader: true);
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        actions: const [SizedBox(width: 72)],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _buildHeaderControls(),
          ),
        ),
      ),
      body: _buildBody(showBackground: true, includeHeader: false),
    );
  }

  _Series _buildSeries(List<Map<String, Object?>> sets, {required String metric}) {
    final filtered = sets.where((row) => row['weight_value'] != null).toList();
    if (filtered.isEmpty) {
      return _Series(spots: const [], labels: const [], minY: 0, maxY: 0, latestWeight: null, latestReps: null);
    }

    final dayMax = <DateTime, double>{};
    for (final row in filtered) {
      final created = DateTime.tryParse(row['created_at'] as String? ?? '');
      if (created == null) continue;
      final dayKey = DateTime(created.year, created.month, created.day);
      final weight = (row['weight_value'] as num).toDouble();
      final reps = (row['reps'] as int?) ?? 0;
      final value = metric == 'Volume' ? weight * reps : weight;
      final current = dayMax[dayKey];
      if (current == null || value > current) {
        dayMax[dayKey] = value;
      }
    }

    final dates = dayMax.keys.toList()..sort();
    final labels = <String>[];
    final values = <double>[];
    for (final date in dates) {
      labels.add('${date.month}/${date.day}');
      values.add(dayMax[date] ?? 0);
    }

    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      maxY = minY + 1;
    }

    final latest = filtered.last;
    return _Series(
      spots: spots,
      labels: labels,
      minY: minY,
      maxY: maxY,
      latestWeight: latest['weight_value'],
      latestReps: latest['reps'],
    );
  }
}

class SessionDetailScreen extends StatefulWidget {
  const SessionDetailScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  State<SessionDetailScreen> createState() => _SessionDetailScreenState();
}

class _SessionDetailScreenState extends State<SessionDetailScreen> {
  late final WorkoutRepo _workoutRepo;

  @override
  void initState() {
    super.initState();
    _workoutRepo = WorkoutRepo(AppDatabase.instance);
  }

  String _formatDate(DateTime date) {
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    final month = months[date.month - 1];
    return '$month ${date.day}, ${date.year}';
  }

  String _formatDuration(DateTime start, DateTime end) {
    final minutes = end.difference(start).inMinutes;
    if (minutes < 1) return '<1 min';
    final hours = minutes ~/ 60;
    final mins = minutes % 60;
    if (hours == 0) return '${mins}m';
    if (mins == 0) return '${hours}h';
    return '${hours}h ${mins}m';
  }

  Future<_SessionDetailData> _loadDetail() async {
    final header = await _workoutRepo.getSessionHeader(widget.sessionId);
    final summaries = await _workoutRepo.getSessionExerciseSummaries(widget.sessionId);
    final sets = await _workoutRepo.getSessionSets(widget.sessionId);

    final bySessionExerciseId = <int, _SessionExerciseSummary>{};
    for (final row in summaries) {
      final sessionExerciseId = row['session_exercise_id'] as int;
      final orderIndex = row['order_index'] as int? ?? 0;
      final name = row['canonical_name'] as String? ?? 'Exercise';
      final setCount = (row['set_count'] as int?) ?? 0;
      final volume = (row['volume'] as num?)?.toDouble() ?? 0.0;
      final maxWeight = (row['max_weight'] as num?)?.toDouble();
      bySessionExerciseId[sessionExerciseId] = _SessionExerciseSummary(
        sessionExerciseId: sessionExerciseId,
        orderIndex: orderIndex,
        name: name,
        setCount: setCount,
        volume: volume,
        maxWeight: maxWeight,
        sets: [],
      );
    }

    for (final row in sets) {
      final sessionExerciseId = row['session_exercise_id'] as int?;
      if (sessionExerciseId == null) continue;
      final summary = bySessionExerciseId[sessionExerciseId];
      if (summary == null) continue;
      summary.sets.add(
        _SessionSetRow(
          setIndex: (row['set_index'] as int?) ?? 0,
          weightValue: (row['weight_value'] as num?)?.toDouble(),
          weightUnit: row['weight_unit'] as String?,
          reps: row['reps'] as int?,
          rpe: (row['rpe'] as num?)?.toDouble(),
          rir: (row['rir'] as num?)?.toDouble(),
          isWarmup: (row['flag_warmup'] as int?) == 1,
          isAmrap: (row['is_amrap'] as int?) == 1,
          restSecActual: row['rest_sec_actual'] as int?,
        ),
      );
    }

    final exercises = bySessionExerciseId.values.toList()
      ..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));

    var totalVolume = 0.0;
    for (final ex in exercises) {
      totalVolume += ex.volume;
    }

    return _SessionDetailData(
      header: header,
      exercises: exercises,
      totalSets: sets.length,
      totalExercises: exercises.length,
      totalVolume: totalVolume,
    );
  }

  String _formatWeight(double? value) {
    if (value == null) return '—';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(1);
  }

  Widget _buildSetLine(_SessionSetRow set) {
    final parts = <String>[];
    final weight = _formatWeight(set.weightValue);
    final reps = set.reps == null ? '—' : set.reps.toString();
    if (set.weightValue == null) {
      parts.add('Set ${set.setIndex + 1}: $reps reps');
    } else {
      final unit = (set.weightUnit ?? '').trim();
      final unitLabel = unit.isEmpty ? '' : ' $unit';
      parts.add('Set ${set.setIndex + 1}: $weight$unitLabel × $reps');
    }
    if (set.isWarmup) parts.add('Warmup');
    if (set.isAmrap) parts.add('AMRAP');
    if (set.rpe != null) parts.add('RPE ${set.rpe!.toStringAsFixed(1)}');
    if (set.rir != null) parts.add('RIR ${set.rir!.toStringAsFixed(1)}');
    if (set.restSecActual != null) parts.add('Rest ${set.restSecActual}s');
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Text(
        parts.join(' • '),
        style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white70,
              height: 1.2,
            ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Day Details'),
        actions: const [SizedBox(width: 72)],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          FutureBuilder<_SessionDetailData>(
            future: _loadDetail(),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final data = snapshot.data;
              if (data == null) {
                return const Center(child: Text('Session not found.'));
              }

              final header = data.header;
              final startedAt = DateTime.tryParse(header?['started_at'] as String? ?? '');
              final endedAt = DateTime.tryParse(header?['ended_at'] as String? ?? '');
              final programName = header?['program_name'] as String?;
              final dayName = header?['day_name'] as String?;
              final dayIndex = header?['day_index'] as int?;

              final title = (dayName != null && dayName.trim().isNotEmpty)
                  ? dayName
                  : (programName ?? 'Empty Day');
              final programLabel = programName == null || programName.trim().isEmpty
                  ? 'Empty Day'
                  : (dayIndex == null ? programName : '$programName • Day ${dayIndex + 1}');
              final dateLabel =
                  startedAt == null ? 'Unknown date' : _formatDate(startedAt);
              final durationLabel = (startedAt != null && endedAt != null)
                  ? _formatDuration(startedAt, endedAt)
                  : '—';
              final volumeLabel = data.totalVolume == 0
                  ? '—'
                  : data.totalVolume.toStringAsFixed(0);
              final titleStyle = Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700);
              final metaStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    letterSpacing: 0.2,
                  );
              final pillTextStyle = Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: Colors.white70,
                    fontWeight: FontWeight.w600,
                  );
              final showProgramLabel = programLabel != title;

              Widget statPill(String label) {
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface.withOpacity(0.18),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: Theme.of(context).colorScheme.onSurface.withOpacity(0.12),
                    ),
                  ),
                  child: Text(label, style: pillTextStyle),
                );
              }

              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: titleStyle,
                        ),
                        if (showProgramLabel) ...[
                          const SizedBox(height: 4),
                          Text(programLabel, style: metaStyle),
                        ],
                        const SizedBox(height: 2),
                        Text('$dateLabel • $durationLabel', style: metaStyle),
                        const SizedBox(height: 10),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            statPill('${data.totalExercises} exercises'),
                            statPill('${data.totalSets} sets'),
                            statPill('Volume $volumeLabel'),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  for (final exercise in data.exercises) ...[
                    GlassCard(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            exercise.name,
                            style: Theme.of(context)
                                .textTheme
                                .titleSmall
                                ?.copyWith(fontWeight: FontWeight.w600),
                          ),
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final summaryParts = <String>['${exercise.setCount} sets'];
                              if (exercise.maxWeight != null) {
                                summaryParts.add('Top ${_formatWeight(exercise.maxWeight)}');
                              }
                              if (exercise.volume > 0) {
                                summaryParts.add('Vol ${exercise.volume.toStringAsFixed(0)}');
                              }
                              return Text(
                                summaryParts.join(' • '),
                                style: metaStyle,
                              );
                            },
                          ),
                          const SizedBox(height: 8),
                          for (final set in exercise.sets) _buildSetLine(set),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _SessionDetailData {
  const _SessionDetailData({
    required this.header,
    required this.exercises,
    required this.totalSets,
    required this.totalExercises,
    required this.totalVolume,
  });

  final Map<String, Object?>? header;
  final List<_SessionExerciseSummary> exercises;
  final int totalSets;
  final int totalExercises;
  final double totalVolume;
}

class _SessionExerciseSummary {
  _SessionExerciseSummary({
    required this.sessionExerciseId,
    required this.orderIndex,
    required this.name,
    required this.setCount,
    required this.volume,
    required this.maxWeight,
    required this.sets,
  });

  final int sessionExerciseId;
  final int orderIndex;
  final String name;
  final int setCount;
  final double volume;
  final double? maxWeight;
  final List<_SessionSetRow> sets;
}

class _SessionSetRow {
  _SessionSetRow({
    required this.setIndex,
    required this.weightValue,
    required this.weightUnit,
    required this.reps,
    required this.rpe,
    required this.rir,
    required this.isWarmup,
    required this.isAmrap,
    required this.restSecActual,
  });

  final int setIndex;
  final double? weightValue;
  final String? weightUnit;
  final int? reps;
  final double? rpe;
  final double? rir;
  final bool isWarmup;
  final bool isAmrap;
  final int? restSecActual;
}

class _Series {
  _Series({
    required this.spots,
    required this.labels,
    required this.minY,
    required this.maxY,
    required this.latestWeight,
    required this.latestReps,
  });

  final List<FlSpot> spots;
  final List<String> labels;
  final double minY;
  final double maxY;
  final Object? latestWeight;
  final Object? latestReps;
}

class _HistoryData {
  _HistoryData({required this.sets, required this.exerciseName});

  final List<Map<String, Object?>> sets;
  final String exerciseName;

  factory _HistoryData.empty() => _HistoryData(sets: const [], exerciseName: '');
}

class _ExerciseSearchSheet extends StatefulWidget {
  const _ExerciseSearchSheet({required this.exerciseRepo});

  final ExerciseRepo exerciseRepo;

  @override
  State<_ExerciseSearchSheet> createState() => _ExerciseSearchSheetState();
}

class _ExerciseSearchSheetState extends State<_ExerciseSearchSheet> {
  final _controller = TextEditingController();
  List<Map<String, Object?>> _results = [];

  @override
  void initState() {
    super.initState();
    _search('');
  }

  Future<void> _search(String query) async {
    if (query.isEmpty) {
      final all = await widget.exerciseRepo.getAll();
      setState(() {
        _results = all.take(50).toList();
      });
      return;
    }
    final results = await widget.exerciseRepo.search(query, limit: 50);
    setState(() {
      _results = results;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _controller,
            decoration: const InputDecoration(
              labelText: 'Search exercises',
              border: OutlineInputBorder(),
            ),
            onChanged: _search,
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 360,
            child: ListView.separated(
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _results[index];
                return ListTile(
                  title: Text(item['canonical_name'] as String),
                  subtitle: Text(item['equipment_type'] as String),
                  onTap: () => Navigator.of(context).pop(item),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
