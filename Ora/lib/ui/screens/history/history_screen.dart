import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({super.key, this.initialExerciseId});

  final int? initialExerciseId;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('History'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
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
            ),
          ),
        ),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                                          final idx = value.toInt();
                                          if (idx == 0 ||
                                              idx == series.labels.length ~/ 2 ||
                                              idx == series.labels.length - 1) {
                                            return Text(series.labels[idx], style: const TextStyle(fontSize: 10));
                                          }
                                          return const SizedBox.shrink();
                                        },
                                      ),
                                    ),
                                    topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                    rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                                  ),
                                  borderData: FlBorderData(show: false),
                                  lineBarsData: [
                                    LineChartBarData(
                                      spots: series.spots,
                                      isCurved: true,
                                      color: Theme.of(context).colorScheme.primary,
                                      dotData: const FlDotData(show: false),
                                    ),
                                  ],
                                  minY: series.minY,
                                  maxY: series.maxY,
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text('Total sets: ${data.sets.length}'),
                            if (series.latestWeight != null)
                              Text('Latest: ${series.latestWeight} lb x ${series.latestReps ?? '-'}'),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
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
