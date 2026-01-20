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
    required this.onStartRest,
  });

  final SessionExerciseInfo info;
  final WorkoutRepo workoutRepo;
  final Future<void> Function({double? weight, required int reps, int? partials, double? rpe, double? rir}) onAddSet;
  final Future<void> Function(int id, {double? weight, int? reps, int? partials, double? rpe, double? rir}) onUpdateSet;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onStartRest;

  @override
  State<ExerciseModal> createState() => _ExerciseModalState();
}

class _ExerciseModalState extends State<ExerciseModal> {
  final _weightController = TextEditingController();
  final _repsController = TextEditingController(text: '8');
  final _partialsController = TextEditingController(text: '0');
  final _rpeController = TextEditingController();
  final _rirController = TextEditingController();

  final _weightFocus = FocusNode();
  final _repsFocus = FocusNode();
  final _partialsFocus = FocusNode();
  final _rpeFocus = FocusNode();
  final _rirFocus = FocusNode();

  TextEditingController? _activeController;
  int _reloadTick = 0;
  bool _showPartials = false;
  bool _showRpeRir = false;
  String _chartMetric = 'Weight';

  @override
  void initState() {
    super.initState();
    _activeController = _weightController;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _partialsController.dispose();
    _rpeController.dispose();
    _rirController.dispose();
    _weightFocus.dispose();
    _repsFocus.dispose();
    _partialsFocus.dispose();
    _rpeFocus.dispose();
    _rirFocus.dispose();
    super.dispose();
  }

  void _setActive(TextEditingController controller) {
    setState(() {
      _activeController = controller;
    });
  }

  void _appendKey(String key) {
    final controller = _activeController;
    if (controller == null) return;
    final text = controller.text;
    if (key == 'back') {
      if (text.isNotEmpty) {
        controller.text = text.substring(0, text.length - 1);
      }
      return;
    }
    if (key == '.') {
      final allowsDecimal = controller == _weightController || controller == _rpeController || controller == _rirController;
      if (!allowsDecimal) return;
      if (text.contains('.')) return;
      controller.text = text.isEmpty ? '0.' : '$text.';
      return;
    }
    controller.text = '$text$key';
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

    await widget.onAddSet(
      weight: weight,
      reps: reps,
      partials: _showPartials ? int.tryParse(_partialsController.text.trim()) : 0,
      rpe: _showRpeRir ? double.tryParse(_rpeController.text.trim()) : null,
      rir: _showRpeRir ? double.tryParse(_rirController.text.trim()) : null,
    );
    setState(() {
      _reloadTick++;
    });
  }

  Future<void> _editSet(Map<String, Object?> setRow) async {
    final updated = await showModalBottomSheet<_SetEditResult>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SetEditSheet(setRow: setRow),
    );
    if (updated == null) return;
    await widget.onUpdateSet(
      setRow['id'] as int,
      weight: updated.weight,
      reps: updated.reps,
      partials: updated.partials,
      rpe: updated.rpe,
      rir: updated.rir,
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
        final rpeRange = (block.targetRpeMin != null || block.targetRpeMax != null)
            ? 'RPE ${block.targetRpeMin ?? ''}-${block.targetRpeMax ?? ''}'
            : null;
        final rirRange = (block.targetRirMin != null || block.targetRirMax != null)
            ? 'RIR ${block.targetRirMin ?? ''}-${block.targetRirMax ?? ''}'
            : null;
        final partialsRange = (block.partialsTargetMin != null || block.partialsTargetMax != null)
            ? 'Partials ${block.partialsTargetMin ?? ''}-${block.partialsTargetMax ?? ''}'
            : null;
        final extras = [rpeRange, rirRange, partialsRange].whereType<String>().join(' • ');
        final label = '${block.role} • ${block.setCount} sets • $repsRange • $restRange';
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label),
              if (extras.isNotEmpty) Text(extras, style: const TextStyle(color: Colors.white70)),
            ],
          ),
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
    final labels = <String>[];
    final values = <double>[];
    for (var i = 0; i < last.length; i++) {
      final weight = (last[i]['weight_value'] as num).toDouble();
      final reps = (last[i]['reps'] as int?) ?? 0;
      final value = _chartMetric == 'Volume' ? weight * reps : weight;
      values.add(value);
      spots.add(FlSpot(i.toDouble(), value));
      final created = DateTime.tryParse(last[i]['created_at'] as String? ?? '');
      if (created != null) {
        labels.add('${created.month}/${created.day}');
      } else {
        labels.add('${i + 1}');
      }
    }
    var minY = values.reduce((a, b) => a < b ? a : b);
    var maxY = values.reduce((a, b) => a > b ? a : b);
    if (minY == maxY) {
      maxY = minY + 1;
    }

    return SizedBox(
      height: 160,
      child: LineChart(
        LineChartData(
          gridData: const FlGridData(show: true),
          titlesData: FlTitlesData(
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 40,
                getTitlesWidget: (value, meta) {
                  if (value == minY || value == maxY) {
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
                  if (idx == 0 || idx == labels.length ~/ 2 || idx == labels.length - 1) {
                    return Text(labels[idx], style: const TextStyle(fontSize: 10));
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
              spots: spots,
              isCurved: true,
              color: Theme.of(context).colorScheme.primary,
              dotData: const FlDotData(show: false),
            ),
          ],
          minY: minY,
          maxY: maxY,
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
                if (data != null) _buildChart(data.history) else const SizedBox(height: 160),
                const SizedBox(height: 8),
                Row(
                  children: [
                    ChoiceChip(
                      label: const Text('Weight'),
                      selected: _chartMetric == 'Weight',
                      onSelected: (_) => setState(() => _chartMetric = 'Weight'),
                    ),
                    const SizedBox(width: 8),
                    ChoiceChip(
                      label: const Text('Weight × Reps'),
                      selected: _chartMetric == 'Volume',
                      onSelected: (_) => setState(() => _chartMetric = 'Volume'),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                const Text('Sets', style: TextStyle(fontWeight: FontWeight.w600)),
                if (sets.isEmpty)
                  const Text('No sets yet.')
                else
                  Column(
                    children: sets.map((set) {
                      final role = set['set_role'] as String;
                      final amrap = (set['is_amrap'] as int? ?? 0) == 1;
                      final partials = (set['partial_reps'] as int? ?? 0) > 0;
                      final rpe = set['rpe'];
                      final rir = set['rir'];
                      return Card(
                        child: ListTile(
                          onTap: () => _editSet(set),
                          title: Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children: [
                              Chip(label: Text(role)),
                              if (amrap) const Chip(label: Text('AMRAP')),
                              if (partials) const Chip(label: Text('Partials')),
                              if (rpe != null) Chip(label: Text('RPE $rpe')),
                              if (rir != null) Chip(label: Text('RIR $rir')),
                            ],
                          ),
                          subtitle: Text(
                            'Wt ${set['weight_value'] ?? '-'} • Reps ${set['reps'] ?? '-'} • P ${set['partial_reps'] ?? 0} • RPE ${set['rpe'] ?? '-'} • RIR ${set['rir'] ?? '-'}',
                          ),
                          trailing: const Icon(Icons.edit),
                        ),
                      );
                    }).toList(),
                  ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _weightController,
                        focusNode: _weightFocus,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Weight (lb)',
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _setActive(_weightController),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: TextField(
                        controller: _repsController,
                        focusNode: _repsFocus,
                        readOnly: true,
                        decoration: const InputDecoration(
                          labelText: 'Reps',
                          border: OutlineInputBorder(),
                        ),
                        onTap: () => _setActive(_repsController),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    FilterChip(
                      label: const Text('Partials'),
                      selected: _showPartials,
                      onSelected: (value) {
                        setState(() {
                          _showPartials = value;
                          if (!value) {
                            _partialsController.text = '0';
                          }
                        });
                      },
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: const Text('RPE/RIR'),
                      selected: _showRpeRir,
                      onSelected: (value) {
                        setState(() {
                          _showRpeRir = value;
                          if (!value) {
                            _rpeController.clear();
                            _rirController.clear();
                          }
                        });
                      },
                    ),
                  ],
                ),
                if (_showPartials) ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: _partialsController,
                    focusNode: _partialsFocus,
                    readOnly: true,
                    decoration: const InputDecoration(
                      labelText: 'Partials',
                      border: OutlineInputBorder(),
                    ),
                    onTap: () => _setActive(_partialsController),
                  ),
                ],
                if (_showRpeRir) ...[
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _rpeController,
                          focusNode: _rpeFocus,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'RPE',
                            border: OutlineInputBorder(),
                          ),
                          onTap: () => _setActive(_rpeController),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: TextField(
                          controller: _rirController,
                          focusNode: _rirFocus,
                          readOnly: true,
                          decoration: const InputDecoration(
                            labelText: 'RIR',
                            border: OutlineInputBorder(),
                          ),
                          onTap: () => _setActive(_rirController),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 8),
                _NumericKeypad(onKey: _appendKey),
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
                        onPressed: widget.onStartRest,
                        child: const Text('Start Rest (120s)'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('End Exercise'),
                    ),
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

class _NumericKeypad extends StatelessWidget {
  const _NumericKeypad({required this.onKey});

  final void Function(String) onKey;

  @override
  Widget build(BuildContext context) {
    final keys = [
      '1', '2', '3',
      '4', '5', '6',
      '7', '8', '9',
      '.', '0', 'back',
    ];
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: keys.length,
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 6,
        crossAxisSpacing: 6,
        childAspectRatio: 2.2,
      ),
      itemBuilder: (context, index) {
        final key = keys[index];
        return _KeypadButton(
          label: key == 'back' ? 'DEL' : key,
          onTap: () => onKey(key),
        );
      },
    );
  }
}

class _SetEditSheet extends StatefulWidget {
  const _SetEditSheet({required this.setRow});

  final Map<String, Object?> setRow;

  @override
  State<_SetEditSheet> createState() => _SetEditSheetState();
}

class _SetEditSheetState extends State<_SetEditSheet> {
  late final TextEditingController _weightController;
  late final TextEditingController _repsController;
  late final TextEditingController _partialsController;
  late final TextEditingController _rpeController;
  late final TextEditingController _rirController;
  TextEditingController? _activeController;

  @override
  void initState() {
    super.initState();
    _weightController = TextEditingController(text: widget.setRow['weight_value']?.toString() ?? '');
    _repsController = TextEditingController(text: widget.setRow['reps']?.toString() ?? '');
    _partialsController = TextEditingController(text: widget.setRow['partial_reps']?.toString() ?? '0');
    _rpeController = TextEditingController(text: widget.setRow['rpe']?.toString() ?? '');
    _rirController = TextEditingController(text: widget.setRow['rir']?.toString() ?? '');
    _activeController = _weightController;
  }

  @override
  void dispose() {
    _weightController.dispose();
    _repsController.dispose();
    _partialsController.dispose();
    _rpeController.dispose();
    _rirController.dispose();
    super.dispose();
  }

  void _setActive(TextEditingController controller) {
    setState(() => _activeController = controller);
  }

  void _appendKey(String key) {
    final controller = _activeController;
    if (controller == null) return;
    final text = controller.text;
    if (key == 'back') {
      if (text.isNotEmpty) {
        controller.text = text.substring(0, text.length - 1);
      }
      return;
    }
    if (key == '.') {
      final allowsDecimal = controller == _weightController || controller == _rpeController || controller == _rirController;
      if (!allowsDecimal) return;
      if (text.contains('.')) return;
      controller.text = text.isEmpty ? '0.' : '$text.';
      return;
    }
    controller.text = '$text$key';
  }

  void _save() {
    Navigator.of(context).pop(_SetEditResult(
      weight: double.tryParse(_weightController.text.trim()),
      reps: int.tryParse(_repsController.text.trim()),
      partials: int.tryParse(_partialsController.text.trim()),
      rpe: double.tryParse(_rpeController.text.trim()),
      rir: double.tryParse(_rirController.text.trim()),
    ));
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
          const Text('Edit Set', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Weight'),
                  onTap: () => _setActive(_weightController),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _repsController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Reps'),
                  onTap: () => _setActive(_repsController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _partialsController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'Partials'),
                  onTap: () => _setActive(_partialsController),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _rpeController,
                  readOnly: true,
                  decoration: const InputDecoration(labelText: 'RPE'),
                  onTap: () => _setActive(_rpeController),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _rirController,
            readOnly: true,
            decoration: const InputDecoration(labelText: 'RIR'),
            onTap: () => _setActive(_rirController),
          ),
          const SizedBox(height: 8),
          _NumericKeypad(onKey: _appendKey),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
              const Spacer(),
              ElevatedButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class _SetEditResult {
  _SetEditResult({this.weight, this.reps, this.partials, this.rpe, this.rir});

  final double? weight;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onTap,
      child: Text(label, style: const TextStyle(fontSize: 18)),
    );
  }
}

class _ExerciseModalData {
  _ExerciseModalData({required this.sets, required this.history});

  final List<Map<String, Object?>> sets;
  final List<Map<String, Object?>> history;
}
