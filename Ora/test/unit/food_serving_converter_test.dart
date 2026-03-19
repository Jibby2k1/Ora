import 'package:flutter_test/flutter_test.dart';
import 'package:ora/domain/models/food_models.dart';
import 'package:ora/domain/services/food_serving_converter.dart';
import 'package:ora/domain/services/recipe_nutrition_service.dart';

void main() {
  group('FoodServingConverter', () {
    const converter = FoodServingConverter();

    test('cups conversion uses gramWeight correctly when label contains cup',
        () {
      final food = FoodItem(
        id: 'test:rice',
        source: FoodSource.usdaFdc,
        name: 'Jasmine rice',
        servingOptions: const [
          ServingOption(
            id: '100g',
            label: '100 g',
            amount: 100,
            unit: 'g',
            gramWeight: 100,
            isDefault: true,
          ),
          ServingOption(
            id: 'serving',
            label: '1 cup (158 g)',
            amount: 158,
            unit: 'g',
            gramWeight: 158,
          ),
        ],
        nutrients: const {
          NutrientKey.calories: NutrientValue(
            key: NutrientKey.calories,
            amount: 130,
            unit: 'kcal',
          ),
        },
        nutrientsPer100g: true,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final catalog = converter.buildCatalog(food);
      final cupsChoice = catalog.choices.firstWhere(
        (choice) => choice.unitType == FoodServingUnitType.cups,
      );

      final scaled = converter.scale(
        food: food,
        choice: cupsChoice,
        amount: 2,
      );

      expect(cupsChoice.gramsPerUnit, closeTo(158, 0.001));
      expect(scaled.scaled.calories, closeTo(410.8, 0.2));
    });
  });

  group('RecipeNutritionService', () {
    const service = RecipeNutritionService();

    test('derives calories from macros when explicit calories are missing', () {
      final food = FoodItem(
        id: 'test:chicken',
        source: FoodSource.usdaFdc,
        name: 'Chicken breast',
        servingOptions: const [
          ServingOption(
            id: '100g',
            label: '100 g',
            amount: 100,
            unit: 'g',
            gramWeight: 100,
            isDefault: true,
          ),
        ],
        nutrients: const {
          NutrientKey.protein: NutrientValue(
            key: NutrientKey.protein,
            amount: 31,
            unit: 'g',
          ),
          NutrientKey.fatTotal: NutrientValue(
            key: NutrientKey.fatTotal,
            amount: 3.6,
            unit: 'g',
          ),
        },
        nutrientsPer100g: true,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final ingredient = service.buildIngredientFromFood(
        food: food,
        servingChoiceId: 'std_oz',
        amount: 12,
        orderIndex: 0,
      );

      final calories = ingredient.nutrients[NutrientKey.calories]?.amount ?? 0;
      expect(calories, greaterThan(0));
    });
  });
}
