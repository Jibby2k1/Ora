import 'package:flutter_test/flutter_test.dart';
import 'package:ora/domain/models/food_models.dart';
import 'package:ora/domain/services/food_nutrient_scaler.dart';

void main() {
  group('FoodNutrientScaler', () {
    const scaler = FoodNutrientScaler();

    test('scales per-100g nutrients using serving gram weight', () {
      final food = FoodItem(
        id: 'usda:1',
        source: FoodSource.usdaFdc,
        name: 'Oats',
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
            id: 'cup',
            label: '1 cup',
            amount: 1,
            unit: 'cup',
            gramWeight: 240,
          ),
        ],
        nutrients: const {
          NutrientKey.calories: NutrientValue(
            key: NutrientKey.calories,
            amount: 50,
            unit: 'kcal',
          ),
          NutrientKey.protein: NutrientValue(
            key: NutrientKey.protein,
            amount: 10,
            unit: 'g',
          ),
        },
        nutrientsPer100g: true,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final view = scaler.scale(
        food: food,
        serving: food.servingOptions[1],
        quantity: 1,
      );

      expect(view.totalGrams, 240);
      expect(view.isApproximateConversion, isFalse);
      expect(view.calories, closeTo(120, 0.001));
      expect(view.protein, closeTo(24, 0.001));
    });

    test('scales per-serving nutrients using gram ratio between servings', () {
      final food = FoodItem(
        id: 'off:1',
        source: FoodSource.openFoodFacts,
        name: 'Protein Bar',
        servingOptions: const [
          ServingOption(
            id: 'serving',
            label: '1 bar',
            amount: 1,
            unit: 'bar',
            gramWeight: 30,
            isDefault: true,
          ),
          ServingOption(
            id: '100g',
            label: '100 g',
            amount: 100,
            unit: 'g',
            gramWeight: 100,
          ),
        ],
        nutrients: const {
          NutrientKey.calories: NutrientValue(
            key: NutrientKey.calories,
            amount: 150,
            unit: 'kcal',
          ),
          NutrientKey.fatTotal: NutrientValue(
            key: NutrientKey.fatTotal,
            amount: 6,
            unit: 'g',
          ),
        },
        nutrientsPer100g: false,
        lastUpdated: DateTime(2026, 1, 1),
      );

      final view = scaler.scale(
        food: food,
        serving: food.servingOptions[1],
        quantity: 1,
      );

      expect(view.isApproximateConversion, isFalse);
      expect(view.calories, closeTo(500, 0.001));
      expect(view.fat, closeTo(20, 0.001));
    });
  });
}
