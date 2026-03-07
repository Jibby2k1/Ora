import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/diet_repo.dart';
import '../../../domain/models/diet_entry.dart';
import '../../../domain/models/food_models.dart';
import '../../../domain/services/food_nutrient_scaler.dart';
import '../../widgets/diet/food_source_badge.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class FoodDetailPage extends StatefulWidget {
  const FoodDetailPage({
    super.key,
    required this.food,
    required this.dietRepo,
    this.initialMealSlot,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FoodItem food,
    required DietRepo dietRepo,
    String? initialMealSlot,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodDetailPage(
          food: food,
          dietRepo: dietRepo,
          initialMealSlot: initialMealSlot,
        ),
      ),
    );
  }

  final FoodItem food;
  final DietRepo dietRepo;
  final String? initialMealSlot;

  @override
  State<FoodDetailPage> createState() => _FoodDetailPageState();
}

class _FoodDetailPageState extends State<FoodDetailPage> {
  final FoodNutrientScaler _scaler = const FoodNutrientScaler();
  final NumberFormat _decimal = NumberFormat('#,##0.##');
  final TextEditingController _quantityController =
      TextEditingController(text: '1');

  static const List<String> _mealSlots = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
  ];

  String? _selectedServingId;
  double _quantity = 1;
  String _mealSlot = _mealSlots.first;
  bool _showAllNutrients = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedServingId = widget.food.defaultServing.id;
    final initialSlot = widget.initialMealSlot?.trim();
    if (initialSlot != null && _mealSlots.contains(initialSlot)) {
      _mealSlot = initialSlot;
    }
  }

  @override
  void dispose() {
    _quantityController.dispose();
    super.dispose();
  }

  ServingOption get _selectedServing {
    final servingId = _selectedServingId;
    return widget.food.servingOptions.firstWhere(
      (serving) => serving.id == servingId,
      orElse: () => widget.food.defaultServing,
    );
  }

  FoodScaledView get _scaledView => _scaler.scale(
        food: widget.food,
        serving: _selectedServing,
        quantity: _quantity,
      );

  Future<void> _addToDiary() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });

    final scaled = _scaledView;
    final notes = [
      'Meal: $_mealSlot',
      'Source: ${widget.food.source.label}',
      'Serving: ${_formatNumber(_quantity)} x ${_selectedServing.label}',
      if (widget.food.barcode != null && widget.food.barcode!.isNotEmpty)
        'Barcode: ${widget.food.barcode}',
      if (scaled.isApproximateConversion)
        'Serving conversion uses an estimate.',
    ].join('\n');

    final micros = <String, double>{};
    for (final entry in scaled.nutrients.entries) {
      final key = entry.key;
      if (key == NutrientKey.calories ||
          key == NutrientKey.protein ||
          key == NutrientKey.carbs ||
          key == NutrientKey.fatTotal ||
          key == NutrientKey.fiber ||
          key == NutrientKey.sodium) {
        continue;
      }
      micros[key.id] = entry.value.amount;
    }

    await widget.dietRepo.addEntry(
      mealName: widget.food.name,
      loggedAt: DateTime.now(),
      mealType: _mealTypeFromSlot(_mealSlot),
      calories: scaled.calories,
      proteinG: scaled.protein,
      carbsG: scaled.carbs,
      fatG: scaled.fat,
      fiberG: scaled.fiber,
      sodiumMg: scaled.sodium,
      micros: micros.isEmpty ? null : micros,
      notes: notes,
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Food added to diary.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
    Navigator.of(context).pop(true);
  }

  DietMealType _mealTypeFromSlot(String mealSlot) {
    switch (mealSlot.trim().toLowerCase()) {
      case 'breakfast':
        return DietMealType.breakfast;
      case 'lunch':
        return DietMealType.lunch;
      case 'dinner':
        return DietMealType.dinner;
      case 'snacks':
      case 'snack':
      default:
        return DietMealType.snack;
    }
  }

  void _adjustQuantity(double delta) {
    final next = (_quantity + delta).clamp(0.1, 999.0);
    _quantityController.text = _formatNumber(next);
    setState(() {
      _quantity = next;
    });
  }

  void _applyQuantityText() {
    final parsed = double.tryParse(_quantityController.text.trim());
    if (parsed == null || parsed <= 0) {
      _quantityController.text = _formatNumber(_quantity);
      return;
    }
    setState(() {
      _quantity = parsed;
    });
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatNutrientAmount(double amount) {
    if (amount.abs() >= 1000) {
      return _decimal.format(amount);
    }
    if (amount == amount.roundToDouble()) {
      return amount.toStringAsFixed(0);
    }
    if (amount.abs() >= 100) {
      return amount.toStringAsFixed(1);
    }
    return amount
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  Map<NutrientGroup, List<NutrientValue>> _groupedNutrients(
      FoodScaledView scaled) {
    final grouped = <NutrientGroup, List<NutrientValue>>{
      for (final group in NutrientGroup.values) group: <NutrientValue>[],
    };

    Iterable<NutrientKey> keys;
    if (_showAllNutrients) {
      keys = NutrientKey.values;
    } else {
      keys = scaled.nutrients.entries
          .where((entry) => entry.value.amount > 0)
          .map((entry) => entry.key);
    }

    for (final key in keys) {
      final value = scaled.nutrients[key] ??
          NutrientValue(
            key: key,
            amount: 0,
            unit: key.defaultUnit,
          );
      grouped[key.group]?.add(value);
    }

    for (final group in grouped.keys) {
      grouped[group]!
          .sort((left, right) => left.key.label.compareTo(right.key.label));
    }

    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scaled = _scaledView;
    final grouped = _groupedNutrients(scaled);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Food Detail'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                widget.food.name,
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              if (widget.food.brand != null &&
                                  widget.food.brand!.trim().isNotEmpty)
                                Padding(
                                  padding: const EdgeInsets.only(top: 4),
                                  child: Text(
                                    widget.food.brand!,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        FoodSourceBadge(source: widget.food.source),
                      ],
                    ),
                    if (widget.food.barcode != null &&
                        widget.food.barcode!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        'Barcode: ${widget.food.barcode}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                    if (widget.food.ingredientsText != null &&
                        widget.food.ingredientsText!.trim().isNotEmpty) ...[
                      const SizedBox(height: 10),
                      Text(
                        widget.food.ingredientsText!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.68),
                        ),
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Serving',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<String>(
                      initialValue: _selectedServing.id,
                      decoration: const InputDecoration(
                        labelText: 'Serving size',
                      ),
                      items: [
                        for (final serving in widget.food.servingOptions)
                          DropdownMenuItem<String>(
                            value: serving.id,
                            child: Text(serving.label),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedServingId = value;
                        });
                      },
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        IconButton(
                          onPressed: () => _adjustQuantity(-0.25),
                          icon: const Icon(Icons.remove_circle_outline),
                        ),
                        Expanded(
                          child: TextField(
                            controller: _quantityController,
                            textAlign: TextAlign.center,
                            keyboardType: const TextInputType.numberWithOptions(
                                decimal: true),
                            decoration:
                                const InputDecoration(labelText: 'Quantity'),
                            onSubmitted: (_) => _applyQuantityText(),
                            onEditingComplete: _applyQuantityText,
                          ),
                        ),
                        IconButton(
                          onPressed: () => _adjustQuantity(0.25),
                          icon: const Icon(Icons.add_circle_outline),
                        ),
                      ],
                    ),
                    if (scaled.isApproximateConversion)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          'Approximate conversion: source did not provide full gram weight details for this serving.',
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _formatNutrientAmount(scaled.calories),
                      style: theme.textTheme.displaySmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        height: 1,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Calories',
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.68),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Expanded(child: _macroCell('P', scaled.protein, 'g')),
                        Expanded(child: _macroCell('C', scaled.carbs, 'g')),
                        Expanded(child: _macroCell('F', scaled.fat, 'g')),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Nutrients',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                        Text(
                          'Show all',
                          style: theme.textTheme.bodySmall,
                        ),
                        Switch(
                          value: _showAllNutrients,
                          onChanged: (value) {
                            setState(() {
                              _showAllNutrients = value;
                            });
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    for (final group in NutrientGroup.values) ...[
                      if (grouped[group]!.isNotEmpty)
                        _NutrientSection(
                          title: _sectionTitle(group),
                          nutrients: grouped[group]!,
                          formatter: _formatNutrientAmount,
                        ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: _mealSlot,
                      decoration: const InputDecoration(labelText: 'Meal'),
                      items: [
                        for (final slot in _mealSlots)
                          DropdownMenuItem<String>(
                            value: slot,
                            child: Text(slot),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _mealSlot = value;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    ElevatedButton(
                      onPressed: _saving ? null : _addToDiary,
                      child: Text(_saving ? 'Adding...' : 'Add to Diary'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content:
                                Text('Copy to Custom Food is coming soon.'),
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      },
                      child: const Text('Copy to Custom Food'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        ],
      ),
    );
  }

  Widget _macroCell(String label, double value, String unit) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.66),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          '${_formatNutrientAmount(value)} $unit',
          style: theme.textTheme.titleMedium
              ?.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }

  String _sectionTitle(NutrientGroup group) {
    return switch (group) {
      NutrientGroup.general => 'General',
      NutrientGroup.carbs => 'Carbs',
      NutrientGroup.lipids => 'Lipids',
      NutrientGroup.protein => 'Protein',
      NutrientGroup.minerals => 'Minerals',
      NutrientGroup.vitamins => 'Vitamins',
    };
  }
}

class _NutrientSection extends StatelessWidget {
  const _NutrientSection({
    required this.title,
    required this.nutrients,
    required this.formatter,
  });

  final String title;
  final List<NutrientValue> nutrients;
  final String Function(double amount) formatter;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          for (var index = 0; index < nutrients.length; index++) ...[
            Row(
              children: [
                Expanded(
                  child: Text(
                    nutrients[index].label,
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
                Text(
                  '${formatter(nutrients[index].amount)} ${nutrients[index].unit}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
            if (index < nutrients.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }
}
