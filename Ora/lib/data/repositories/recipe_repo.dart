import 'dart:convert';

import '../../domain/models/food_models.dart';
import '../../domain/models/recipe_models.dart';
import '../db/db.dart';

class RecipeRepo {
  RecipeRepo(this._db);

  final AppDatabase _db;

  Future<List<RecipeModel>> listRecipes({String? query}) async {
    final db = await _db.database;
    final normalizedQuery = query?.trim();
    final rows = await db.query(
      'recipe',
      where: (normalizedQuery == null || normalizedQuery.isEmpty)
          ? null
          : 'lower(name) LIKE ?',
      whereArgs: (normalizedQuery == null || normalizedQuery.isEmpty)
          ? null
          : ['%${normalizedQuery.toLowerCase()}%'],
      orderBy: 'updated_at DESC',
    );

    final recipes = <RecipeModel>[];
    for (final row in rows) {
      final recipeId = row['id'] as int;
      recipes.add(
        RecipeModel(
          id: recipeId,
          name: row['name']?.toString() ?? 'Recipe',
          notes: row['notes']?.toString(),
          category: RecipeCategoryX.fromStorage(row['category']?.toString()),
          servings: _asDouble(row['servings']) ?? 1,
          isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
          ingredients: await _loadIngredients(recipeId),
          createdAt: _asDateTime(row['created_at']) ?? DateTime.now(),
          updatedAt: _asDateTime(row['updated_at']) ?? DateTime.now(),
        ),
      );
    }
    return recipes;
  }

  Future<RecipeModel?> getRecipe(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'recipe',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return RecipeModel(
      id: id,
      name: row['name']?.toString() ?? 'Recipe',
      notes: row['notes']?.toString(),
      category: RecipeCategoryX.fromStorage(row['category']?.toString()),
      servings: _asDouble(row['servings']) ?? 1,
      isFavorite: (row['is_favorite'] as int? ?? 0) == 1,
      ingredients: await _loadIngredients(id),
      createdAt: _asDateTime(row['created_at']) ?? DateTime.now(),
      updatedAt: _asDateTime(row['updated_at']) ?? DateTime.now(),
    );
  }

  Future<int> saveRecipe(RecipeModel recipe) async {
    final db = await _db.database;
    final now = DateTime.now();
    return db.transaction<int>((txn) async {
      late final int recipeId;
      final recipePayload = <String, Object?>{
        'name':
            recipe.name.trim().isEmpty ? 'Untitled Recipe' : recipe.name.trim(),
        'notes': recipe.notes,
        'category': recipe.category.storageValue,
        'servings': recipe.servings <= 0 ? 1 : recipe.servings,
        'is_favorite': recipe.isFavorite ? 1 : 0,
        'updated_at': now.toIso8601String(),
      };

      if (recipe.id == null) {
        recipePayload['created_at'] = now.toIso8601String();
        recipeId = await txn.insert('recipe', recipePayload);
      } else {
        recipeId = recipe.id!;
        await txn.update(
          'recipe',
          recipePayload,
          where: 'id = ?',
          whereArgs: [recipeId],
        );
      }

      await txn.delete(
        'recipe_ingredient',
        where: 'recipe_id = ?',
        whereArgs: [recipeId],
      );

      for (var index = 0; index < recipe.ingredients.length; index++) {
        final ingredient = recipe.ingredients[index];
        await txn.insert(
          'recipe_ingredient',
          {
            'recipe_id': recipeId,
            'order_index': index,
            'food_id': ingredient.food.id,
            'food_source': ingredient.food.source.cacheKey,
            'food_name': ingredient.food.name,
            'food_json': jsonEncode(ingredient.food.toJson()),
            'serving_choice_id': ingredient.servingChoiceId,
            'serving_label': ingredient.servingLabel,
            'serving_unit': ingredient.servingUnit,
            'serving_gram_weight': ingredient.servingGramWeight,
            'amount': ingredient.amount,
            'is_approximate': ingredient.isApproximate ? 1 : 0,
            'nutrients_json': jsonEncode(
              ingredient.nutrients
                  .map((key, value) => MapEntry(key.id, value.toJson())),
            ),
            'created_at': ingredient.createdAt.toIso8601String(),
            'updated_at': now.toIso8601String(),
          },
        );
      }

      return recipeId;
    });
  }

  Future<void> deleteRecipe(int id) async {
    final db = await _db.database;
    await db.transaction((txn) async {
      await txn.delete(
        'recipe_ingredient',
        where: 'recipe_id = ?',
        whereArgs: [id],
      );
      await txn.delete(
        'recipe',
        where: 'id = ?',
        whereArgs: [id],
      );
    });
  }

  Future<List<RecipeIngredientModel>> _loadIngredients(int recipeId) async {
    final db = await _db.database;
    final rows = await db.query(
      'recipe_ingredient',
      where: 'recipe_id = ?',
      whereArgs: [recipeId],
      orderBy: 'order_index ASC',
    );
    final ingredients = <RecipeIngredientModel>[];
    for (final row in rows) {
      final foodJson = row['food_json']?.toString();
      if (foodJson == null || foodJson.trim().isEmpty) continue;
      final decodedFood = jsonDecode(foodJson);
      if (decodedFood is! Map) continue;
      final food = FoodItem.fromJson(
        Map<String, dynamic>.from(decodedFood),
      );

      final nutrients = <NutrientKey, NutrientValue>{};
      final nutrientsJson = row['nutrients_json']?.toString();
      if (nutrientsJson != null && nutrientsJson.trim().isNotEmpty) {
        final decoded = jsonDecode(nutrientsJson);
        if (decoded is Map) {
          for (final entry in decoded.entries) {
            final keyName = entry.key.toString();
            final key = NutrientKey.values.firstWhere(
              (value) => value.id == keyName,
              orElse: () => NutrientKey.calories,
            );
            if (entry.value is Map<String, dynamic>) {
              nutrients[key] =
                  NutrientValue.fromJson(entry.value as Map<String, dynamic>);
            } else if (entry.value is Map) {
              nutrients[key] = NutrientValue.fromJson(
                Map<String, dynamic>.from(entry.value as Map<dynamic, dynamic>),
              );
            }
          }
        }
      }

      ingredients.add(
        RecipeIngredientModel(
          id: row['id'] as int?,
          recipeId: recipeId,
          orderIndex: (row['order_index'] as int?) ?? ingredients.length,
          food: food,
          servingChoiceId:
              row['serving_choice_id']?.toString() ?? food.defaultServing.id,
          servingLabel:
              row['serving_label']?.toString() ?? food.defaultServing.label,
          servingUnit: row['serving_unit']?.toString(),
          servingGramWeight: _asDouble(row['serving_gram_weight']),
          amount: _asDouble(row['amount']) ?? 1,
          isApproximate: (row['is_approximate'] as int? ?? 0) == 1,
          nutrients: nutrients,
          createdAt: _asDateTime(row['created_at']) ?? DateTime.now(),
          updatedAt: _asDateTime(row['updated_at']) ?? DateTime.now(),
        ),
      );
    }
    return ingredients;
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  DateTime? _asDateTime(Object? value) {
    if (value == null) return null;
    return DateTime.tryParse(value.toString());
  }
}
