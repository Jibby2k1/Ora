import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/pr_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/models/session_exercise_info.dart';
import '../../../domain/services/set_plan_service.dart';

class ExerciseModal extends StatefulWidget {
  const ExerciseModal({
    super.key,
    required this.info,
    required this.workoutRepo,
    required this.onAddSet,
    required this.onUpdateSet,
    required this.onUndo,
    required this.onRedo,
  });

  final SessionExerciseInfo info;
  final WorkoutRepo workoutRepo;
  final Future<void> Function(double? weight, int reps) onAddSet;
  final Future<void> Function(int id, {double? weight, int? reps, int? partials, double? rpe, double? rir}) onUpdateSet;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  State<ExerciseModal> createState() => _ExerciseModalState();
}

class _ExerciseModalState extends State<ExerciseModal> {
  final _weightController = TextEditingController();
  final _repsController = TextEditingController(text: '8');
  int _reloadTick = 0;
  Timer? _restTimer;
  int _restRemaining = 0;

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _restTimer?.cancel();
    super.dispose();
  }

  Future<void> _handleAddSet() async {
    final reps = int.tryParse(_repsController.text.trim());
    if (reps == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter reps.')),
      );
      return;
    }
    final weightText = _weightController.text.trim();
    final weight = weightText.isEmpty ? null : double.tryParse(weightText);

    await widget.onAddSet(weight, reps);
    setState(() {
      _reloadTick++;
    });
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

  Future<void> _editSet(Map<String, Object?> setRow) async {
    final weightController = TextEditingController(text: setRow['weight_value']?.toString() ?? '');
    final repsController = TextEditingController(text: setRow['reps']?.toString() ?? '');
    final partialsController = TextEditingController(text: setRow['partial_reps']?.toString() ?? '0');
    final rpeController = TextEditingController(text: setRow['rpe']?.toString() ?? '');
    final rirController = TextEditingController(text: setRow['rir']?.toString() ?? '');

    final updated = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Edit Set'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: weightController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Weight'),
              ),
              TextField(
                controller: repsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Reps'),
              ),
              TextField(
                controller: partialsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Partials'),
              ),
              TextField(
                controller: rpeController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RPE'),
              ),
              TextField(
                controller: rirController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'RIR'),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
            ElevatedButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Save')),
          ],
        );
      },
    );

    if (updated != true) return;
    await widget.onUpdateSet(
      setRow['id'] as int,
      weight: double.tryParse(weightController.text.trim()),
      reps: int.tryParse(repsController.text.trim()),
      partials: int.tryParse(partialsController.text.trim()),
      rpe: double.tryParse(rpeController.text.trim()),
      rir: double.tryParse(rirController.text.trim()),
    );

    setState(() {
      _reloadTick++;
    });
  }

  Future<_ExerciseModalData> _loadData() async {
    final sets = await widget.workoutRepo.getSetsForSessionExercise(widget.info.sessionExerciseId);
    final history = await PrRepo(AppDatabase.instance).getSetsForExercise(widget.info.exerciseId);
    return _ExerciseModalData(sets: sets, history: history);
  }

  Widget _buildPrescription() {
    if (widget.info.planBlocks.isEmpty) {
      return const Text('No prescription blocks yet.');
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: widget.info.planBlocks.map((block) {
        final repsRange = (block.repsMin != null || block.repsMax != null)
            ? '${block.repsMin ?? ''}-${block.repsMax ?? ''} reps'
            : 'Reps open';
        final restRange = (block.restSecMin != null || block.restSecMax != null)
            ? '${block.restSecMin ?? ''}-${block.restSecMax ?? ''}s rest'
            : 'Rest open';
        final label = '${block.role} • ${block.setCount} sets • $repsRange • $restRange';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Text(label),
        );
      }).toList(),
    );
  }

  Widget _buildChart(List<Map<String, Object?>> history) {
    final weighted = history.where((row) => row['weight_value'] != null).toList();
    if (weighted.isEmpty) {
      return const Text('No history yet.');
    }
    final last = weighted.reversed.take(10).toList().reversed.toList();
    final spots = <FlSpot>[];
    for (var i = 0; i < last.length; i++) {
      final weight = (last[i]['weight_value'] as num).toDouble();
      spots.add(FlSpot(i.toDouble(), weight));
    }

    return SizedBox(
      height: 140,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: false),
          titlesData: const FlTitlesData(show: false),
          borderData: FlBorderData(show: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
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
      child: FutureBuilder<_ExerciseModalData>(
        future: _loadData(),
        key: ValueKey(_reloadTick),
        builder: (context, snapshot) {
          final data = snapshot.data;
          final sets = data?.sets ?? [];
          final planResult = SetPlanService().nextExpected(blocks: widget.info.planBlocks, existingSets: sets);
          final nextLabel = planResult == null ? 'TOP' : planResult.nextRole;

          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.info.exerciseName,
                  style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                Text('Next: $nextLabel${planResult?.isAmrap == true ? ' (AMRAP)' : ''}'),
                const SizedBox(height: 12),
                const Text('Prescription', style: TextStyle(fontWeight: FontWeight.w600)),
                _buildPrescription(),
                const SizedBox(height: 12),
                const Text('Recent History', style: TextStyle(fontWeight: FontWeight.w600)),
                if (data != null) _buildChart(data.history) else const SizedBox(height: 140),
                const SizedBox(height: 12),
                const Text('Sets', style: TextStyle(fontWeight: FontWeight.w600)),
                if (sets.isEmpty)
                  const Text('No sets yet.')
                else
                  DataTable(
                    columns: const [
                      DataColumn(label: Text('Role')),
                      DataColumn(label: Text('Wt')),
                      DataColumn(label: Text('Reps')),
                      DataColumn(label: Text('P')),
                      DataColumn(label: Text('RPE')),
                      DataColumn(label: Text('RIR')),
                    ],
                    rows: sets
                        .map((set) => DataRow(
                              cells: [
                                DataCell(Text(set['set_role'] as String)),
                                DataCell(Text((set['weight_value'] ?? '-').toString())),
                                DataCell(Text((set['reps'] ?? '-').toString())),
                                DataCell(Text((set['partial_reps'] ?? 0).toString())),
                                DataCell(Text((set['rpe'] ?? '-').toString())),
                                DataCell(Text((set['rir'] ?? '-').toString())),
                              ],
                              onSelectChanged: (_) => _editSet(set),
                            ))
                        .toList(),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Weight (lb)',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _repsController,
                        keyboardType: TextInputType.number,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                ElevatedButton(
                  onPressed: _handleAddSet,
                  child: const Text('Add Set'),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        onPressed: () => _startRestTimer(120),
                        child: Text(_restRemaining > 0 ? 'Rest: $_restRemaining s' : 'Start Rest (120s)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      onPressed: widget.onUndo,
                      icon: const Icon(Icons.undo),
                    ),
                    IconButton(
                      onPressed: widget.onRedo,
                      icon: const Icon(Icons.redo),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ExerciseModalData {
  _ExerciseModalData({required this.sets, required this.history});

  final List<Map<String, Object?>> sets;
  final List<Map<String, Object?>> history;
}
