import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/repositories/diet_repo.dart';
import '../../../domain/models/diet_entry.dart';
import '../../../domain/models/food_models.dart';
import '../../../domain/models/recipe_models.dart';
import '../../../domain/services/recipe_nutrition_service.dart';
import '../glass/glass_card.dart';

class RecipeAddToDiarySheet extends StatefulWidget {
  const RecipeAddToDiarySheet({
    super.key,
    required this.recipe,
    required this.dietRepo,
    required this.selectedDay,
    this.initialMealSlot,
    this.nutritionService = const RecipeNutritionService(),
  });

  static Future<bool?> show(
    BuildContext context, {
    required RecipeModel recipe,
    required DietRepo dietRepo,
    required DateTime selectedDay,
    String? initialMealSlot,
    RecipeNutritionService nutritionService = const RecipeNutritionService(),
  }) {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) => RecipeAddToDiarySheet(
        recipe: recipe,
        dietRepo: dietRepo,
        selectedDay: selectedDay,
        initialMealSlot: initialMealSlot,
        nutritionService: nutritionService,
      ),
    );
  }

  final RecipeModel recipe;
  final DietRepo dietRepo;
  final DateTime selectedDay;
  final String? initialMealSlot;
  final RecipeNutritionService nutritionService;

  @override
  State<RecipeAddToDiarySheet> createState() => _RecipeAddToDiarySheetState();
}

class _RecipeAddToDiarySheetState extends State<RecipeAddToDiarySheet> {
  static const List<String> _mealSlots = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
  ];

  final TextEditingController _servingsController =
      TextEditingController(text: '1');
  bool _saving = false;
  late String _mealSlot;
  late DateTime _loggedAt;

  @override
  void initState() {
    super.initState();
    final slot = widget.initialMealSlot?.trim();
    _mealSlot = _mealSlots.contains(slot) ? slot! : _mealSlots.first;
    _loggedAt = _defaultLoggedAt(widget.selectedDay);
  }

  @override
  void dispose() {
    _servingsController.dispose();
    super.dispose();
  }

  DateTime _defaultLoggedAt(DateTime day) {
    final normalized = DateTime(day.year, day.month, day.day);
    final now = DateTime.now();
    if (normalized.year == now.year &&
        normalized.month == now.month &&
        normalized.day == now.day) {
      return now;
    }
    return DateTime(day.year, day.month, day.day, 12);
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(_loggedAt),
    );
    if (picked == null) return;
    setState(() {
      _loggedAt = DateTime(
        _loggedAt.year,
        _loggedAt.month,
        _loggedAt.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  DietMealType _mealTypeFromSlot(String mealSlot) {
    switch (mealSlot.toLowerCase()) {
      case 'breakfast':
        return DietMealType.breakfast;
      case 'lunch':
        return DietMealType.lunch;
      case 'dinner':
        return DietMealType.dinner;
      case 'snacks':
      default:
        return DietMealType.snack;
    }
  }

  Future<void> _save() async {
    final consumedServings =
        double.tryParse(_servingsController.text.trim()) ?? 0;
    if (consumedServings <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Enter a valid serving amount.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    final totals = widget.nutritionService.computeTotals(widget.recipe);
    final scaledNutrients = <NutrientKey, double>{
      for (final entry in totals.perServingNutrients.entries)
        entry.key: entry.value * consumedServings,
    };

    final calories = scaledNutrients[NutrientKey.calories] ?? 0;
    final protein = scaledNutrients[NutrientKey.protein] ?? 0;
    final carbs = scaledNutrients[NutrientKey.carbs] ?? 0;
    final fat = scaledNutrients[NutrientKey.fatTotal] ?? 0;
    final fiber = scaledNutrients[NutrientKey.fiber] ?? 0;
    final sodium = scaledNutrients[NutrientKey.sodium] ?? 0;
    final micros = widget.nutritionService.toMicrosMap(scaledNutrients);

    await widget.dietRepo.addEntry(
      mealName: widget.recipe.name,
      loggedAt: _loggedAt,
      mealType: _mealTypeFromSlot(_mealSlot),
      calories: calories,
      proteinG: protein,
      carbsG: carbs,
      fatG: fat,
      fiberG: fiber,
      sodiumMg: sodium,
      micros: micros.isEmpty ? null : micros,
      notes: 'Meal: $_mealSlot\n'
          'Recipe: ${widget.recipe.name}\n'
          'Recipe ID: ${widget.recipe.id ?? '-'}\n'
          'Serving: $consumedServings recipe servings',
      foodSource: 'recipe',
      foodSourceId: 'recipe_${widget.recipe.id ?? 'draft'}',
      portionLabel: '$consumedServings recipe servings',
      portionAmount: consumedServings,
      portionUnit: 'serving',
    );

    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        12,
        12,
        12,
        media.viewInsets.bottom + 20,
      ),
      child: GlassCard(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Add Recipe to Diary',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              widget.recipe.name,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _servingsController,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Consumed servings',
                hintText: '1',
              ),
            ),
            const SizedBox(height: 10),
            DropdownButtonFormField<String>(
              initialValue: _mealSlot,
              decoration: const InputDecoration(labelText: 'Meal group'),
              items: [
                for (final slot in _mealSlots)
                  DropdownMenuItem<String>(
                    value: slot,
                    child: Text(slot),
                  ),
              ],
              onChanged: (value) {
                if (value == null) return;
                setState(() => _mealSlot = value);
              },
            ),
            const SizedBox(height: 10),
            InkWell(
              onTap: _pickTime,
              borderRadius: BorderRadius.circular(10),
              child: InputDecorator(
                decoration: const InputDecoration(labelText: 'Timestamp'),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        DateFormat('EEE, MMM d • h:mm a').format(_loggedAt),
                      ),
                    ),
                    Icon(
                      Icons.schedule_rounded,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 14),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed:
                      _saving ? null : () => Navigator.of(context).pop(false),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: _saving ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Add to Diary'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
