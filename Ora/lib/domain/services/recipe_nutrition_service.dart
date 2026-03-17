import '../models/food_models.dart';
import '../models/recipe_models.dart';
import 'food_nutrient_scaler.dart';
import 'food_serving_converter.dart';

class RecipeNutritionService {
  const RecipeNutritionService({
    FoodNutrientScaler scaler = const FoodNutrientScaler(),
    FoodServingConverter converter = const FoodServingConverter(),
  })  : _scaler = scaler,
        _converter = converter;

  static const List<NutrientKey> highlightedMicronutrients = [
    NutrientKey.fiber,
    NutrientKey.sodium,
    NutrientKey.potassium,
    NutrientKey.calcium,
    NutrientKey.iron,
    NutrientKey.vitaminC,
    NutrientKey.vitaminD,
    NutrientKey.magnesium,
  ];

  final FoodNutrientScaler _scaler;
  final FoodServingConverter _converter;

  RecipeIngredientModel normalizeIngredient(
    RecipeIngredientModel ingredient, {
    DateTime? now,
  }) {
    final normalizedAmount = ingredient.amount <= 0 ? 1.0 : ingredient.amount;
    final catalog = _converter.buildCatalog(ingredient.food);
    final matchedChoice = catalog.byId(ingredient.servingChoiceId);

    late final FoodScaledView scaled;
    late final bool isApproximate;
    late final String servingChoiceId;
    late final String servingLabel;
    late final String? servingUnit;
    late final double? servingGramWeight;

    if (matchedChoice != null) {
      final converted = _converter.scale(
        food: ingredient.food,
        choice: matchedChoice,
        amount: normalizedAmount,
      );
      scaled = converted.scaled;
      isApproximate = converted.isApproximate;
      servingChoiceId = matchedChoice.id;
      servingLabel = matchedChoice.label;
      servingUnit = matchedChoice.unitLabel;
      servingGramWeight = matchedChoice.gramsPerUnit;
    } else {
      scaled = _scaler.scale(
        food: ingredient.food,
        serving: ingredient.servingOption,
        quantity: normalizedAmount,
      );
      isApproximate = scaled.isApproximateConversion;
      servingChoiceId = ingredient.servingChoiceId;
      servingLabel = ingredient.servingLabel;
      servingUnit = ingredient.servingUnit;
      servingGramWeight = ingredient.servingGramWeight;
    }

    final normalizedNutrients = Map<NutrientKey, NutrientValue>.from(
      scaled.nutrients,
    );
    final caloriesAmount =
        normalizedNutrients[NutrientKey.calories]?.amount ?? 0;
    if (caloriesAmount <= 0) {
      final protein = normalizedNutrients[NutrientKey.protein]?.amount ?? 0;
      final carbs = normalizedNutrients[NutrientKey.carbs]?.amount ?? 0;
      final fat = normalizedNutrients[NutrientKey.fatTotal]?.amount ?? 0;
      final derivedCalories = (protein * 4) + (carbs * 4) + (fat * 9);
      if (derivedCalories > 0) {
        normalizedNutrients[NutrientKey.calories] = NutrientValue(
          key: NutrientKey.calories,
          amount: derivedCalories,
          unit: NutrientKey.calories.defaultUnit,
        );
      }
    }

    return ingredient.copyWith(
      servingChoiceId: servingChoiceId,
      servingLabel: servingLabel,
      servingUnit: servingUnit,
      servingGramWeight: servingGramWeight,
      amount: normalizedAmount,
      isApproximate: isApproximate || ingredient.isApproximate,
      nutrients: normalizedNutrients,
      updatedAt: now ?? DateTime.now(),
    );
  }

  RecipeIngredientModel buildIngredientFromFood({
    required FoodItem food,
    required String servingChoiceId,
    required double amount,
    required int orderIndex,
  }) {
    final catalog = _converter.buildCatalog(food);
    final choice = catalog.byId(servingChoiceId) ?? catalog.defaultChoice;
    final base = RecipeIngredientModel(
      orderIndex: orderIndex,
      food: food,
      servingChoiceId: choice.id,
      servingLabel: choice.label,
      servingUnit: choice.unitLabel,
      servingGramWeight: choice.gramsPerUnit,
      amount: amount,
      isApproximate: choice.isApproximate,
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    );
    return normalizeIngredient(base);
  }

  RecipeModel normalizeRecipe(RecipeModel recipe, {DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    final normalizedIngredients = <RecipeIngredientModel>[];
    for (var i = 0; i < recipe.ingredients.length; i++) {
      final normalized = normalizeIngredient(
        recipe.ingredients[i].copyWith(orderIndex: i),
        now: timestamp,
      );
      normalizedIngredients.add(normalized);
    }
    final servings = recipe.servings <= 0 ? 1.0 : recipe.servings;
    return recipe.copyWith(
      servings: servings,
      ingredients: normalizedIngredients,
      updatedAt: timestamp,
    );
  }

  RecipeComputedTotals computeTotals(RecipeModel recipe) {
    final totals = <NutrientKey, double>{};
    for (final ingredient in recipe.ingredients) {
      final nutrients = normalizeIngredient(ingredient).nutrients;
      for (final entry in nutrients.entries) {
        totals[entry.key] = (totals[entry.key] ?? 0) + entry.value.amount;
      }
    }
    final normalizedServings = recipe.servings <= 0 ? 1.0 : recipe.servings;
    final perServing = <NutrientKey, double>{
      for (final entry in totals.entries)
        entry.key: entry.value / normalizedServings,
    };
    return RecipeComputedTotals(
      totalNutrients: totals,
      perServingNutrients: perServing,
      servings: normalizedServings,
    );
  }

  Map<String, double> toMicrosMap(Map<NutrientKey, double> nutrients) {
    final micros = <String, double>{};
    for (final entry in nutrients.entries) {
      final key = entry.key;
      if (key == NutrientKey.calories ||
          key == NutrientKey.protein ||
          key == NutrientKey.carbs ||
          key == NutrientKey.fatTotal ||
          key == NutrientKey.fiber ||
          key == NutrientKey.sodium) {
        continue;
      }
      if (entry.value <= 0) continue;
      micros[key.id] = entry.value;
    }
    return micros;
  }
}
