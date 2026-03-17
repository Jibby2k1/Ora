import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db/db.dart';
import '../../../data/food/food_repository.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../data/repositories/recipe_repo.dart';
import '../../../domain/models/recipe_models.dart';
import '../../../domain/services/recipe_nutrition_service.dart';
import '../../widgets/diet/recipe_add_to_diary_sheet.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'recipe_builder_page.dart';

class RecipesPage extends StatefulWidget {
  const RecipesPage({
    super.key,
    required this.recipeRepo,
    required this.foodRepository,
    required this.dietRepo,
    this.pickForDiary = false,
    this.selectedDay,
    this.initialMealSlot,
  });

  static Future<bool?> showManage(
    BuildContext context, {
    DateTime? selectedDay,
  }) {
    final db = AppDatabase.instance;
    final dietRepo = DietRepo(db);
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipesPage(
          recipeRepo: RecipeRepo(db),
          foodRepository: FoodRepository(db: db, dietRepo: dietRepo),
          dietRepo: dietRepo,
          selectedDay: selectedDay,
        ),
      ),
    );
  }

  static Future<bool?> showForDiary(
    BuildContext context, {
    required FoodRepository foodRepository,
    required DietRepo dietRepo,
    DateTime? selectedDay,
    String? initialMealSlot,
  }) {
    final db = AppDatabase.instance;
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => RecipesPage(
          recipeRepo: RecipeRepo(db),
          foodRepository: foodRepository,
          dietRepo: dietRepo,
          pickForDiary: true,
          selectedDay: selectedDay,
          initialMealSlot: initialMealSlot,
        ),
      ),
    );
  }

  final RecipeRepo recipeRepo;
  final FoodRepository foodRepository;
  final DietRepo dietRepo;
  final bool pickForDiary;
  final DateTime? selectedDay;
  final String? initialMealSlot;

  @override
  State<RecipesPage> createState() => _RecipesPageState();
}

class _RecipesPageState extends State<RecipesPage> {
  final TextEditingController _searchController = TextEditingController();
  final RecipeNutritionService _nutritionService =
      const RecipeNutritionService();
  final DateFormat _updatedFormat = DateFormat('MMM d, y');

  bool _loading = true;
  List<RecipeModel> _recipes = const [];

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _loadRecipes();
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _loadRecipes(query: _searchController.text);
  }

  Future<void> _loadRecipes({String? query}) async {
    setState(() => _loading = true);
    final recipes = await widget.recipeRepo.listRecipes(query: query);
    if (!mounted) return;
    setState(() {
      _recipes = recipes;
      _loading = false;
    });
  }

  Future<void> _createRecipe() async {
    final changed = await RecipeBuilderPage.showCreate(
      context,
      recipeRepo: widget.recipeRepo,
      foodRepository: widget.foodRepository,
      dietRepo: widget.dietRepo,
      selectedDay: widget.selectedDay,
      initialMealSlot: widget.initialMealSlot,
    );
    if (!mounted || changed != true) return;
    await _loadRecipes(query: _searchController.text);
    if (!mounted) return;
    if (widget.pickForDiary) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _editRecipe(RecipeModel recipe) async {
    final changed = await RecipeBuilderPage.showEdit(
      context,
      recipeRepo: widget.recipeRepo,
      foodRepository: widget.foodRepository,
      dietRepo: widget.dietRepo,
      recipe: recipe,
      selectedDay: widget.selectedDay,
      initialMealSlot: widget.initialMealSlot,
    );
    if (!mounted || changed != true) return;
    await _loadRecipes(query: _searchController.text);
    if (!mounted) return;
    if (widget.pickForDiary) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _addRecipeToDiary(RecipeModel recipe) async {
    final added = await RecipeAddToDiarySheet.show(
      context,
      recipe: recipe,
      dietRepo: widget.dietRepo,
      selectedDay: widget.selectedDay ?? DateTime.now(),
      initialMealSlot: widget.initialMealSlot,
      nutritionService: _nutritionService,
    );
    if (!mounted || added != true) return;
    Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title:
            Text(widget.pickForDiary ? 'Add Recipe / Meal' : 'Saved Recipes'),
        actions: [
          IconButton(
            onPressed: _createRecipe,
            icon: const Icon(Icons.add),
            tooltip: 'Create recipe',
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  radius: 14,
                  child: TextField(
                    controller: _searchController,
                    decoration: InputDecoration(
                      hintText: 'Search recipes',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _searchController.text.trim().isEmpty
                          ? null
                          : IconButton(
                              onPressed: _searchController.clear,
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: _loading
                    ? const Center(child: CircularProgressIndicator())
                    : _recipes.isEmpty
                        ? _buildEmptyState(context)
                        : ListView.separated(
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            itemBuilder: (context, index) {
                              final recipe = _recipes[index];
                              final totals =
                                  _nutritionService.computeTotals(recipe);
                              return InkWell(
                                borderRadius: BorderRadius.circular(16),
                                onTap: () {
                                  if (widget.pickForDiary) {
                                    _addRecipeToDiary(recipe);
                                    return;
                                  }
                                  _editRecipe(recipe);
                                },
                                child: GlassCard(
                                  radius: 16,
                                  padding:
                                      const EdgeInsets.fromLTRB(12, 10, 12, 10),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              recipe.name,
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                              style: theme.textTheme.titleSmall
                                                  ?.copyWith(
                                                fontWeight: FontWeight.w800,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            '${totals.totalCalories.toStringAsFixed(0)} kcal',
                                            style: theme.textTheme.labelLarge
                                                ?.copyWith(
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        '${recipe.category.label} • '
                                        '${recipe.ingredients.length} ingredients • '
                                        '${recipe.servings.toStringAsFixed(1)} servings',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.72),
                                        ),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(
                                        'Protein ${totals.totalProtein.toStringAsFixed(1)} g • '
                                        'Carbs ${totals.totalCarbs.toStringAsFixed(1)} g • '
                                        'Fat ${totals.totalFat.toStringAsFixed(1)} g',
                                        style:
                                            theme.textTheme.bodySmall?.copyWith(
                                          color: theme.colorScheme.onSurface
                                              .withValues(alpha: 0.78),
                                        ),
                                      ),
                                      const SizedBox(height: 6),
                                      Row(
                                        children: [
                                          Text(
                                            'Updated ${_updatedFormat.format(recipe.updatedAt)}',
                                            style: theme.textTheme.labelSmall
                                                ?.copyWith(
                                              color: theme.colorScheme.onSurface
                                                  .withValues(alpha: 0.6),
                                            ),
                                          ),
                                          const Spacer(),
                                          IconButton(
                                            visualDensity: const VisualDensity(
                                              horizontal: -3,
                                              vertical: -3,
                                            ),
                                            onPressed: () =>
                                                _editRecipe(recipe),
                                            icon:
                                                const Icon(Icons.edit_outlined),
                                            tooltip: 'Edit',
                                          ),
                                          IconButton(
                                            visualDensity: const VisualDensity(
                                              horizontal: -3,
                                              vertical: -3,
                                            ),
                                            onPressed: () =>
                                                _addRecipeToDiary(recipe),
                                            icon:
                                                const Icon(Icons.playlist_add),
                                            tooltip: 'Add to diary',
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                            separatorBuilder: (_, __) =>
                                const SizedBox(height: 7),
                            itemCount: _recipes.length,
                          ),
              ),
            ],
          ),
        ],
      ),
      floatingActionButton: widget.pickForDiary
          ? null
          : FloatingActionButton(
              onPressed: _createRecipe,
              child: const Icon(Icons.add),
            ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: GlassCard(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.menu_book_outlined,
                size: 32,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
              const SizedBox(height: 10),
              Text(
                'No recipes saved yet',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Create a reusable meal with ingredients, servings, and live nutrition totals.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _createRecipe,
                icon: const Icon(Icons.add),
                label: const Text('Create Recipe'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
