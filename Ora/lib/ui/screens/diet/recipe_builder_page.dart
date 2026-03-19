import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../data/food/food_repository.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../data/repositories/recipe_repo.dart';
import '../../../domain/models/food_detail_computed.dart';
import '../../../domain/models/food_models.dart';
import '../../../domain/models/recipe_models.dart';
import '../../../domain/services/food_detail_computer.dart';
import '../../../domain/services/food_nutrient_scaler.dart';
import '../../../domain/services/food_serving_converter.dart';
import '../../../domain/services/recipe_nutrition_service.dart';
import '../../widgets/diet/layered_progress_bar.dart';
import '../../widgets/diet/macro_donut_chart.dart';
import '../../widgets/diet/recipe_add_to_diary_sheet.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'food_search_page.dart';

class RecipeBuilderPage extends StatefulWidget {
  const RecipeBuilderPage({
    super.key,
    required this.recipeRepo,
    required this.foodRepository,
    required this.dietRepo,
    this.initialRecipe,
    this.selectedDay,
    this.initialMealSlot,
  });

  static Future<bool?> showCreate(
    BuildContext context, {
    required RecipeRepo recipeRepo,
    required FoodRepository foodRepository,
    required DietRepo dietRepo,
    DateTime? selectedDay,
    String? initialMealSlot,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipeBuilderPage(
          recipeRepo: recipeRepo,
          foodRepository: foodRepository,
          dietRepo: dietRepo,
          selectedDay: selectedDay,
          initialMealSlot: initialMealSlot,
        ),
      ),
    );
  }

  static Future<bool?> showEdit(
    BuildContext context, {
    required RecipeRepo recipeRepo,
    required FoodRepository foodRepository,
    required DietRepo dietRepo,
    required RecipeModel recipe,
    DateTime? selectedDay,
    String? initialMealSlot,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipeBuilderPage(
          recipeRepo: recipeRepo,
          foodRepository: foodRepository,
          dietRepo: dietRepo,
          initialRecipe: recipe,
          selectedDay: selectedDay,
          initialMealSlot: initialMealSlot,
        ),
      ),
    );
  }

  final RecipeRepo recipeRepo;
  final FoodRepository foodRepository;
  final DietRepo dietRepo;
  final RecipeModel? initialRecipe;
  final DateTime? selectedDay;
  final String? initialMealSlot;

  @override
  State<RecipeBuilderPage> createState() => _RecipeBuilderPageState();
}

class _RecipeBuilderPageState extends State<RecipeBuilderPage> {
  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final TextEditingController _servingsController =
      TextEditingController(text: '1');

  final RecipeNutritionService _nutritionService =
      const RecipeNutritionService();
  final FoodServingConverter _servingConverter = const FoodServingConverter();

  RecipeCategory _category = RecipeCategory.meal;
  List<RecipeIngredientModel> _ingredients = const [];
  bool _saving = false;
  bool _deleteBusy = false;

  bool get _isEditing => widget.initialRecipe?.id != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialRecipe;
    if (initial != null) {
      _nameController.text = initial.name;
      _notesController.text = initial.notes ?? '';
      _servingsController.text = _formatNumber(initial.servings);
      _category = initial.category;
      _ingredients = initial.ingredients
          .map(_nutritionService.normalizeIngredient)
          .toList(growable: false);
    }
    _servingsController.addListener(_onFormChanged);
    _nameController.addListener(_onFormChanged);
  }

  @override
  void dispose() {
    _nameController
      ..removeListener(_onFormChanged)
      ..dispose();
    _notesController.dispose();
    _servingsController
      ..removeListener(_onFormChanged)
      ..dispose();
    super.dispose();
  }

  void _onFormChanged() {
    if (!mounted) return;
    setState(() {});
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2);
  }

  double _scaledCaloriesWithFallback(FoodScaledView scaled) {
    final explicit = scaled.calories;
    if (explicit > 0) return explicit;
    final derived =
        (scaled.protein * 4) + (scaled.carbs * 4) + (scaled.fat * 9);
    return derived > 0 ? derived : 0;
  }

  double get _servingsValue {
    final parsed = double.tryParse(_servingsController.text.trim());
    if (parsed == null || parsed <= 0) return 1;
    return parsed;
  }

  RecipeModel _buildDraftRecipe() {
    final now = DateTime.now();
    return RecipeModel(
      id: widget.initialRecipe?.id,
      name: _nameController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      category: _category,
      servings: _servingsValue,
      ingredients: _ingredients,
      isFavorite: widget.initialRecipe?.isFavorite ?? false,
      createdAt: widget.initialRecipe?.createdAt ?? now,
      updatedAt: now,
    );
  }

  FoodDetailComputedData _computeNutrientView(
    Map<NutrientKey, double> nutrients,
  ) {
    final scaledNutrients = <NutrientKey, NutrientValue>{};
    for (final entry in nutrients.entries) {
      if (entry.value <= 0) continue;
      scaledNutrients[entry.key] = NutrientValue(
        key: entry.key,
        amount: entry.value,
        unit: entry.key.defaultUnit,
      );
    }

    final targets = <NutrientKey, double>{
      NutrientKey.calories: 2500,
      NutrientKey.protein: 180,
      NutrientKey.carbs: 250,
      NutrientKey.fatTotal: 70,
      ...FoodDetailComputer.defaultMicronutrientTargets,
    };

    return const FoodDetailComputer().compute(
      scaledNutrients: scaledNutrients,
      diary: FoodDiarySnapshot(
        day: DateTime(2000, 1, 1),
        consumed: {},
        targets: targets,
        totalEntries: 0,
        entriesWithMicros: 0,
      ),
      showAllNutrients: true,
    );
  }

  Future<void> _addIngredient() async {
    final food = await FoodSearchPage.showForSelection(
      context,
      foodRepository: widget.foodRepository,
      dietRepo: widget.dietRepo,
    );
    if (!mounted || food == null) return;

    final added = await _openIngredientEditor(
        food: food, orderIndex: _ingredients.length);
    if (!mounted || added == null) return;
    setState(() {
      _ingredients = [..._ingredients, added];
    });
  }

  Future<void> _editIngredient(int index) async {
    final current = _ingredients[index];
    final edited = await _openIngredientEditor(
      food: current.food,
      orderIndex: index,
      initial: current,
    );
    if (!mounted || edited == null) return;
    setState(() {
      final next = List<RecipeIngredientModel>.from(_ingredients);
      next[index] = edited;
      _ingredients = next;
    });
  }

  Future<RecipeIngredientModel?> _openIngredientEditor({
    required FoodItem food,
    required int orderIndex,
    RecipeIngredientModel? initial,
  }) async {
    final catalog = _servingConverter.buildCatalog(food);
    var selectedChoiceId = initial?.servingChoiceId ?? catalog.defaultChoiceId;
    if (catalog.byId(selectedChoiceId) == null) {
      FoodServingChoice? fallback;
      if (initial != null) {
        for (final choice in catalog.choices) {
          final sameLabel = choice.label == initial.servingLabel;
          final sameUnit = initial.servingUnit != null &&
              initial.servingUnit!.isNotEmpty &&
              choice.unitLabel.toLowerCase() ==
                  initial.servingUnit!.toLowerCase();
          if (sameLabel || sameUnit) {
            fallback = choice;
            break;
          }
        }
      }
      selectedChoiceId = fallback?.id ?? catalog.defaultChoiceId;
    }
    final amountController = TextEditingController(
      text: _formatNumber(initial?.amount ?? 1),
    );

    RecipeIngredientModel? output;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final choice =
                catalog.byId(selectedChoiceId) ?? catalog.defaultChoice;
            final amount = double.tryParse(amountController.text.trim()) ?? 1;
            final preview = _servingConverter.scale(
              food: food,
              choice: choice,
              amount: amount <= 0 ? 1 : amount,
            );
            return Padding(
              padding: EdgeInsets.fromLTRB(
                12,
                12,
                12,
                MediaQuery.of(context).viewInsets.bottom + 16,
              ),
              child: SingleChildScrollView(
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        initial == null ? 'Add Ingredient' : 'Edit Ingredient',
                        style:
                            Theme.of(context).textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        food.name,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.78),
                            ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                            decimal: true),
                        decoration: const InputDecoration(
                          labelText: 'Amount',
                          hintText: '1',
                        ),
                        onChanged: (_) => setSheetState(() {}),
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<String>(
                        initialValue: selectedChoiceId,
                        decoration:
                            const InputDecoration(labelText: 'Serving size'),
                        items: [
                          for (final choice in catalog.choices)
                            DropdownMenuItem<String>(
                              value: choice.id,
                              child: Text(choice.label),
                            ),
                        ],
                        onChanged: (value) {
                          if (value == null) return;
                          setSheetState(() => selectedChoiceId = value);
                        },
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Preview: ${_scaledCaloriesWithFallback(preview.scaled).toStringAsFixed(0)} kcal • '
                        'Protein: ${preview.scaled.protein.toStringAsFixed(1)} g • '
                        'Carbs: ${preview.scaled.carbs.toStringAsFixed(1)} g • '
                        'Fat: ${preview.scaled.fat.toStringAsFixed(1)} g',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurface
                                  .withValues(alpha: 0.75),
                            ),
                      ),
                      const SizedBox(height: 14),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          TextButton(
                            onPressed: () => Navigator.of(context).pop(),
                            child: const Text('Cancel'),
                          ),
                          const SizedBox(width: 8),
                          ElevatedButton(
                            onPressed: () {
                              final parsed = double.tryParse(
                                      amountController.text.trim()) ??
                                  0;
                              if (parsed <= 0) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Enter a valid amount.'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: Duration(seconds: 2),
                                  ),
                                );
                                return;
                              }
                              final built =
                                  _nutritionService.buildIngredientFromFood(
                                food: food,
                                servingChoiceId: selectedChoiceId,
                                amount: parsed,
                                orderIndex: orderIndex,
                              );
                              output = built.copyWith(
                                id: initial?.id,
                                recipeId: initial?.recipeId,
                                createdAt: initial?.createdAt ?? DateTime.now(),
                              );
                              Navigator.of(context).pop();
                            },
                            child: const Text('Save'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
    unawaited(
      Future<void>.delayed(
        const Duration(milliseconds: 400),
        amountController.dispose,
      ),
    );
    return output;
  }

  void _removeIngredient(int index) {
    final removed = _ingredients[index];
    setState(() {
      final next = List<RecipeIngredientModel>.from(_ingredients)
        ..removeAt(index);
      _ingredients = next;
    });
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: const Text('Ingredient removed'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () {
            if (!mounted) return;
            setState(() {
              final next = List<RecipeIngredientModel>.from(_ingredients);
              final insertAt = index.clamp(0, next.length);
              next.insert(insertAt, removed);
              _ingredients = next;
            });
          },
        ),
      ),
    );
  }

  Future<RecipeModel?> _saveRecipe() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Recipe name is required.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return null;
    }
    if (_ingredients.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Add at least one ingredient.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
      return null;
    }

    setState(() => _saving = true);
    final normalized = _nutritionService.normalizeRecipe(_buildDraftRecipe());
    final recipeId = await widget.recipeRepo.saveRecipe(normalized);
    if (!mounted) return null;
    final saved = normalized.copyWith(id: recipeId);
    setState(() {
      _ingredients = saved.ingredients;
      _saving = false;
    });
    return saved;
  }

  Future<void> _saveAndClose() async {
    final saved = await _saveRecipe();
    if (!mounted || saved == null) return;
    Navigator.of(context).pop(true);
  }

  Future<void> _saveAndAddToDiary() async {
    final saved = await _saveRecipe();
    if (!mounted || saved == null) return;
    final recipeForSheet =
        (await widget.recipeRepo.getRecipe(saved.id!)) ?? saved;
    if (!mounted) return;
    final added = await RecipeAddToDiarySheet.show(
      context,
      recipe: recipeForSheet,
      dietRepo: widget.dietRepo,
      selectedDay: widget.selectedDay ?? DateTime.now(),
      initialMealSlot: widget.initialMealSlot,
      nutritionService: _nutritionService,
    );
    if (!mounted) return;
    if (added == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _deleteRecipe() async {
    final id = widget.initialRecipe?.id;
    if (id == null) return;
    final shouldDelete = await showDialog<bool>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Delete Recipe'),
          content: const Text('Delete this recipe permanently?'),
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
    if (!mounted || shouldDelete != true) return;
    setState(() => _deleteBusy = true);
    await widget.recipeRepo.deleteRecipe(id);
    if (!mounted) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final draft = _buildDraftRecipe();
    final totals = _nutritionService.computeTotals(draft);
    final perServingComputed = _computeNutrientView(totals.perServingNutrients);
    final totalComputed = _computeNutrientView(totals.totalNutrients);

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? 'Edit Recipe' : 'Create Recipe'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          ListView(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 120),
            children: [
              _RecipeInfoCard(
                nameController: _nameController,
                notesController: _notesController,
                servingsController: _servingsController,
              ),
              const SizedBox(height: 8),
              _RecipeIngredientsCard(
                ingredients: _ingredients,
                onAddIngredient: _addIngredient,
                onEditIngredient: _editIngredient,
                onDeleteIngredient: _removeIngredient,
              ),
              const SizedBox(height: 8),
              _RecipeMacroSummaryCard(
                totals: totals,
              ),
              const SizedBox(height: 8),
              _RecipeMicronutrientPreviewCard(
                perServingComputed: perServingComputed,
                totalComputed: totalComputed,
              ),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saving ? null : _saveAndClose,
                  child: Text(_saving ? 'Saving...' : 'Save Recipe'),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton(
                  onPressed: _saving ? null : _saveAndAddToDiary,
                  child: const Text('Save & Add to Diary'),
                ),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 6),
                TextButton(
                  onPressed: _deleteBusy ? null : _deleteRecipe,
                  child: Text(_deleteBusy ? 'Deleting...' : 'Delete Recipe'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RecipeInfoCard extends StatelessWidget {
  const _RecipeInfoCard({
    required this.nameController,
    required this.notesController,
    required this.servingsController,
  });

  final TextEditingController nameController;
  final TextEditingController notesController;
  final TextEditingController servingsController;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entry Controls',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
          const SizedBox(height: 10),
          TextField(
            controller: nameController,
            decoration: const InputDecoration(labelText: 'Recipe name'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: notesController,
            maxLines: 2,
            decoration: const InputDecoration(labelText: 'Notes (optional)'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: servingsController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: const InputDecoration(labelText: 'Servings'),
          ),
        ],
      ),
    );
  }
}

class _RecipeIngredientsCard extends StatelessWidget {
  const _RecipeIngredientsCard({
    required this.ingredients,
    required this.onAddIngredient,
    required this.onEditIngredient,
    required this.onDeleteIngredient,
  });

  final List<RecipeIngredientModel> ingredients;
  final VoidCallback onAddIngredient;
  final ValueChanged<int> onEditIngredient;
  final ValueChanged<int> onDeleteIngredient;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Ingredients',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          if (ingredients.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 10),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: theme.colorScheme.surface.withValues(alpha: 0.14),
                border: Border.all(
                  color: theme.colorScheme.outline.withValues(alpha: 0.2),
                ),
              ),
              child: Text(
                'No ingredients yet. Add your first ingredient.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                ),
              ),
            )
          else
            Column(
              children: [
                for (var index = 0; index < ingredients.length; index++) ...[
                  Dismissible(
                    key: ValueKey(
                        'recipe-ingredient-${ingredients[index].id ?? index}'),
                    direction: DismissDirection.endToStart,
                    onDismissed: (_) => onDeleteIngredient(index),
                    background: Container(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.error.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.centerRight,
                      padding: const EdgeInsets.only(right: 12),
                      child: const Icon(Icons.delete_outline),
                    ),
                    child: InkWell(
                      onTap: () => onEditIngredient(index),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color:
                              theme.colorScheme.surface.withValues(alpha: 0.15),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    ingredients[index].food.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${ingredients[index].amount.toStringAsFixed(2)} x '
                                    '${ingredients[index].servingLabel}',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.7),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 10),
                            Text(
                              '${_ingredientCalories(ingredients[index]).toStringAsFixed(0)} kcal',
                              style: theme.textTheme.labelLarge?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  if (index < ingredients.length - 1) const SizedBox(height: 6),
                ],
              ],
            ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: onAddIngredient,
              icon: const Icon(Icons.add),
              label: const Text('Add Ingredient'),
            ),
          ),
        ],
      ),
    );
  }

  double _ingredientCalories(RecipeIngredientModel ingredient) {
    final nutrients = ingredient.nutrients;
    final explicit = nutrients[NutrientKey.calories]?.amount ?? 0;
    if (explicit > 0) return explicit;
    final protein = nutrients[NutrientKey.protein]?.amount ?? 0;
    final carbs = nutrients[NutrientKey.carbs]?.amount ?? 0;
    final fat = nutrients[NutrientKey.fatTotal]?.amount ?? 0;
    final derived = (protein * 4) + (carbs * 4) + (fat * 9);
    return derived > 0 ? derived : 0;
  }
}

class _RecipeMicronutrientPreviewCard extends StatelessWidget {
  const _RecipeMicronutrientPreviewCard({
    required this.perServingComputed,
    required this.totalComputed,
  });

  final FoodDetailComputedData perServingComputed;
  final FoodDetailComputedData totalComputed;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final totalBySection = <NutrientSectionType, NutrientSectionRows>{
      for (final section in totalComputed.micronutrientSections)
        section.type: section,
    };
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Complete Nutrient Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          for (var sectionIndex = 0;
              sectionIndex < perServingComputed.micronutrientSections.length;
              sectionIndex++) ...[
            Text(
              perServingComputed.micronutrientSections[sectionIndex].title
                  .toUpperCase(),
              style: theme.textTheme.labelMedium?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                letterSpacing: 0.8,
              ),
            ),
            const SizedBox(height: 8),
            for (var rowIndex = 0;
                rowIndex <
                    perServingComputed
                        .micronutrientSections[sectionIndex].rows.length;
                rowIndex++) ...[
              () {
                final perSection =
                    perServingComputed.micronutrientSections[sectionIndex];
                final totalSection = totalBySection[perSection.type];
                final perRow = perSection.rows[rowIndex];
                final totalRow = totalSection?.rows.firstWhere(
                        (row) => row.id == perRow.id,
                        orElse: () => perRow) ??
                    perRow;
                return _microRow(
                  context: context,
                  perServingRow: perRow,
                  totalRow: totalRow,
                );
              }(),
              if (rowIndex <
                  perServingComputed
                          .micronutrientSections[sectionIndex].rows.length -
                      1)
                const SizedBox(height: 8),
            ],
            if (sectionIndex <
                perServingComputed.micronutrientSections.length - 1)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: 12),
                child: Divider(height: 1),
              ),
          ],
        ],
      ),
    );
  }

  String _formatValue(double value, String unit) {
    if (unit == 'kcal') return value.toStringAsFixed(0);
    if (value.abs() >= 100 || value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  Widget _microRow({
    required BuildContext context,
    required NutrientProgressRowData perServingRow,
    required NutrientProgressRowData totalRow,
  }) {
    final theme = Theme.of(context);
    final perServingProgress = perServingRow.projectedProgress;
    final totalProgress = totalRow.projectedProgress;
    final totalDelta =
        math.max(0.0, totalRow.projected - perServingRow.projected);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                perServingRow.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              perServingRow.hasTarget
                  ? '${(perServingProgress * 100).round()}%'
                  : 'No target',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          perServingRow.hasTarget
              ? '${_formatValue(perServingRow.projected, perServingRow.unit)} / ${_formatValue(perServingRow.target ?? 0, perServingRow.unit)} ${perServingRow.unit} • '
                  '+${_formatValue(totalDelta, perServingRow.unit)}'
              : '${_formatValue(perServingRow.projected, perServingRow.unit)} ${perServingRow.unit} • '
                  '+${_formatValue(totalDelta, perServingRow.unit)}',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 6),
        LayeredProgressBar(
          baseProgress: perServingProgress,
          projectedProgress: math.max(perServingProgress, totalProgress),
          baseColor: theme.colorScheme.primary,
          addedColor: theme.colorScheme.primary.withValues(alpha: 0.45),
          height: 8,
        ),
      ],
    );
  }
}

class _RecipeMacroSummaryCard extends StatelessWidget {
  const _RecipeMacroSummaryCard({
    required this.totals,
  });

  final RecipeComputedTotals totals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const proteinColor = Color(0xFF4CAF50);
    const carbsColor = Color(0xFF2196F3);
    const fatColor = Color(0xFFF44336);
    final proteinKcal = totals.totalProtein * 4;
    final carbsKcal = totals.totalCarbs * 4;
    final fatKcal = totals.totalFat * 9;
    final macroTotal = proteinKcal + carbsKcal + fatKcal;
    final segments = [
      MacroPieSegment(
        label: 'Protein',
        grams: totals.totalProtein,
        calories: proteinKcal,
        percent: macroTotal <= 0 ? 0 : proteinKcal / macroTotal,
      ),
      MacroPieSegment(
        label: 'Carbs',
        grams: totals.totalCarbs,
        calories: carbsKcal,
        percent: macroTotal <= 0 ? 0 : carbsKcal / macroTotal,
      ),
      MacroPieSegment(
        label: 'Fat',
        grams: totals.totalFat,
        calories: fatKcal,
        percent: macroTotal <= 0 ? 0 : fatKcal / macroTotal,
      ),
    ];
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Nutrition Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final legend = Column(
                children: [
                  _macroLegendRow(
                    context: context,
                    color: proteinColor,
                    label: 'Protein',
                    grams: totals.totalProtein,
                    percent: segments[0].percent,
                  ),
                  const SizedBox(height: 8),
                  _macroLegendRow(
                    context: context,
                    color: carbsColor,
                    label: 'Carbs',
                    grams: totals.totalCarbs,
                    percent: segments[1].percent,
                  ),
                  const SizedBox(height: 8),
                  _macroLegendRow(
                    context: context,
                    color: fatColor,
                    label: 'Fat',
                    grams: totals.totalFat,
                    percent: segments[2].percent,
                  ),
                ],
              );
              if (compact) {
                return Column(
                  children: [
                    MacroDonutChart(
                      segments: segments,
                      totalCalories: totals.totalCalories,
                      proteinColor: proteinColor,
                      carbsColor: carbsColor,
                      fatColor: fatColor,
                    ),
                    const SizedBox(height: 8),
                    legend,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: MacroDonutChart(
                      segments: segments,
                      totalCalories: totals.totalCalories,
                      proteinColor: proteinColor,
                      carbsColor: carbsColor,
                      fatColor: fatColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: legend,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Total recipe: ${totals.totalCalories.toStringAsFixed(0)} kcal',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Per serving: ${totals.perServingCalories.toStringAsFixed(0)} kcal',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _macroLegendRow({
    required BuildContext context,
    required Color color,
    required String label,
    required double grams,
    required double percent,
  }) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        Text(
          '${grams.toStringAsFixed(1)} g',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
        const SizedBox(width: 12),
        Text(
          '${(percent * 100).round()}%',
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.82),
          ),
        ),
      ],
    );
  }
}
