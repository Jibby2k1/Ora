import 'package:flutter_test/flutter_test.dart';
import 'package:ora/domain/models/food_models.dart';
import 'package:ora/domain/services/food_nutrient_mapper.dart';

void main() {
  group('FoodNutrientMapper', () {
    const mapper = FoodNutrientMapper();

    test('maps USDA nutrients into normalized macro keys', () {
      final nutrients = mapper.fromUsdaFoodNutrients([
        {
          'amount': 120,
          'nutrient': {
            'number': '1008',
            'name': 'Energy',
            'unitName': 'KCAL',
          },
        },
        {
          'amount': 8.5,
          'nutrient': {
            'number': '1003',
            'name': 'Protein',
            'unitName': 'G',
          },
        },
        {
          'amount': 15,
          'nutrient': {
            'number': '1005',
            'name': 'Carbohydrate, by difference',
            'unitName': 'G',
          },
        },
        {
          'amount': 3.2,
          'nutrient': {
            'number': '1004',
            'name': 'Total lipid (fat)',
            'unitName': 'G',
          },
        },
      ]);

      expect(nutrients[NutrientKey.calories]?.amount, 120);
      expect(nutrients[NutrientKey.protein]?.amount, 8.5);
      expect(nutrients[NutrientKey.carbs]?.amount, 15);
      expect(nutrients[NutrientKey.fatTotal]?.amount, 3.2);
    });

    test('maps Open Food Facts nutriments and normalizes units', () {
      final nutrients = mapper.fromOpenFoodFactsNutriments(
        {
          'energy-kcal_100g': 250,
          'proteins_100g': 7.5,
          'carbohydrates_100g': 30,
          'fat_100g': 11,
          'sodium_100g': 0.45,
          'sodium_unit': 'g',
        },
        perServing: false,
      );

      expect(nutrients[NutrientKey.calories]?.amount, 250);
      expect(nutrients[NutrientKey.protein]?.amount, 7.5);
      expect(nutrients[NutrientKey.carbs]?.amount, 30);
      expect(nutrients[NutrientKey.fatTotal]?.amount, 11);
      expect(nutrients[NutrientKey.sodium]?.amount, closeTo(450, 0.001));
      expect(nutrients[NutrientKey.sodium]?.unit, 'mg');
    });
  });
}
