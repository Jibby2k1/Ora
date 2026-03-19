import 'package:flutter/foundation.dart';

import 'food_models.dart';

enum RecipeCategory {
  meal,
  snack,
  drink,
  sauce,
  dessert,
}

extension RecipeCategoryX on RecipeCategory {
  String get storageValue => switch (this) {
        RecipeCategory.meal => 'meal',
        RecipeCategory.snack => 'snack',
        RecipeCategory.drink => 'drink',
        RecipeCategory.sauce => 'sauce',
        RecipeCategory.dessert => 'dessert',
      };

  String get label => switch (this) {
        RecipeCategory.meal => 'Meal',
        RecipeCategory.snack => 'Snack',
        RecipeCategory.drink => 'Drink',
        RecipeCategory.sauce => 'Sauce',
        RecipeCategory.dessert => 'Dessert',
      };

  static RecipeCategory fromStorage(String? raw) {
    for (final value in RecipeCategory.values) {
      if (value.storageValue == raw?.trim().toLowerCase()) {
        return value;
      }
    }
    return RecipeCategory.meal;
  }
}

@immutable
class RecipeIngredientModel {
  const RecipeIngredientModel({
    this.id,
    this.recipeId,
    required this.orderIndex,
    required this.food,
    required this.servingChoiceId,
    required this.servingLabel,
    required this.amount,
    this.servingUnit,
    this.servingGramWeight,
    this.isApproximate = false,
    this.nutrients = const {},
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final int? recipeId;
  final int orderIndex;
  final FoodItem food;
  final String servingChoiceId;
  final String servingLabel;
  final String? servingUnit;
  final double? servingGramWeight;
  final double amount;
  final bool isApproximate;
  final Map<NutrientKey, NutrientValue> nutrients;
  final DateTime createdAt;
  final DateTime updatedAt;

  ServingOption get servingOption => ServingOption(
        id: servingChoiceId,
        label: servingLabel,
        amount: 1,
        unit: servingUnit,
        gramWeight: servingGramWeight,
        isDefault: true,
      );

  RecipeIngredientModel copyWith({
    int? id,
    int? recipeId,
    int? orderIndex,
    FoodItem? food,
    String? servingChoiceId,
    String? servingLabel,
    String? servingUnit,
    double? servingGramWeight,
    double? amount,
    bool? isApproximate,
    Map<NutrientKey, NutrientValue>? nutrients,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecipeIngredientModel(
      id: id ?? this.id,
      recipeId: recipeId ?? this.recipeId,
      orderIndex: orderIndex ?? this.orderIndex,
      food: food ?? this.food,
      servingChoiceId: servingChoiceId ?? this.servingChoiceId,
      servingLabel: servingLabel ?? this.servingLabel,
      servingUnit: servingUnit ?? this.servingUnit,
      servingGramWeight: servingGramWeight ?? this.servingGramWeight,
      amount: amount ?? this.amount,
      isApproximate: isApproximate ?? this.isApproximate,
      nutrients: nutrients ?? this.nutrients,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class RecipeModel {
  const RecipeModel({
    this.id,
    required this.name,
    this.notes,
    required this.category,
    required this.servings,
    required this.ingredients,
    this.isFavorite = false,
    required this.createdAt,
    required this.updatedAt,
  });

  final int? id;
  final String name;
  final String? notes;
  final RecipeCategory category;
  final double servings;
  final List<RecipeIngredientModel> ingredients;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;

  RecipeModel copyWith({
    int? id,
    String? name,
    String? notes,
    RecipeCategory? category,
    double? servings,
    List<RecipeIngredientModel>? ingredients,
    bool? isFavorite,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return RecipeModel(
      id: id ?? this.id,
      name: name ?? this.name,
      notes: notes ?? this.notes,
      category: category ?? this.category,
      servings: servings ?? this.servings,
      ingredients: ingredients ?? this.ingredients,
      isFavorite: isFavorite ?? this.isFavorite,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

@immutable
class RecipeComputedTotals {
  const RecipeComputedTotals({
    required this.totalNutrients,
    required this.perServingNutrients,
    required this.servings,
  });

  final Map<NutrientKey, double> totalNutrients;
  final Map<NutrientKey, double> perServingNutrients;
  final double servings;

  double totalOf(NutrientKey key) => totalNutrients[key] ?? 0;

  double perServingOf(NutrientKey key) => perServingNutrients[key] ?? 0;

  double get totalCalories => totalOf(NutrientKey.calories);

  double get totalProtein => totalOf(NutrientKey.protein);

  double get totalCarbs => totalOf(NutrientKey.carbs);

  double get totalFat => totalOf(NutrientKey.fatTotal);

  double get perServingCalories => perServingOf(NutrientKey.calories);

  double get perServingProtein => perServingOf(NutrientKey.protein);

  double get perServingCarbs => perServingOf(NutrientKey.carbs);

  double get perServingFat => perServingOf(NutrientKey.fatTotal);
}
