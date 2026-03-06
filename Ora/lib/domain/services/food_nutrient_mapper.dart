import '../models/food_models.dart';

class FoodNutrientMapper {
  const FoodNutrientMapper();

  static final Map<String, NutrientKey> _usdaNumberMap = {
    '1008': NutrientKey.calories,
    '2047': NutrientKey.calories,
    '1051': NutrientKey.water,
    '1003': NutrientKey.protein,
    '1005': NutrientKey.carbs,
    '1079': NutrientKey.fiber,
    '2000': NutrientKey.sugar,
    '1235': NutrientKey.addedSugar,
    '1004': NutrientKey.fatTotal,
    '1258': NutrientKey.satFat,
    '1292': NutrientKey.monoFat,
    '1293': NutrientKey.polyFat,
    '1257': NutrientKey.transFat,
    '1253': NutrientKey.cholesterol,
    '1093': NutrientKey.sodium,
    '1092': NutrientKey.potassium,
    '1087': NutrientKey.calcium,
    '1089': NutrientKey.iron,
    '1090': NutrientKey.magnesium,
    '1091': NutrientKey.phosphorus,
    '1095': NutrientKey.zinc,
    '1098': NutrientKey.copper,
    '1101': NutrientKey.manganese,
    '1103': NutrientKey.selenium,
    '1106': NutrientKey.vitaminA,
    '1162': NutrientKey.vitaminC,
    '1114': NutrientKey.vitaminD,
    '1109': NutrientKey.vitaminE,
    '1185': NutrientKey.vitaminK,
    '1165': NutrientKey.thiamin,
    '1166': NutrientKey.riboflavin,
    '1167': NutrientKey.niacin,
    '1170': NutrientKey.pantothenicAcid,
    '1175': NutrientKey.vitaminB6,
    '1177': NutrientKey.folate,
    '1178': NutrientKey.vitaminB12,
    '1180': NutrientKey.choline,
  };

  static final Map<String, NutrientKey> _usdaNameMap = {
    'energy': NutrientKey.calories,
    'water': NutrientKey.water,
    'protein': NutrientKey.protein,
    'carbohydrate, by difference': NutrientKey.carbs,
    'fiber, total dietary': NutrientKey.fiber,
    'sugars, total including nlea': NutrientKey.sugar,
    'sugars, added': NutrientKey.addedSugar,
    'total lipid (fat)': NutrientKey.fatTotal,
    'fatty acids, total saturated': NutrientKey.satFat,
    'fatty acids, total monounsaturated': NutrientKey.monoFat,
    'fatty acids, total polyunsaturated': NutrientKey.polyFat,
    'fatty acids, total trans': NutrientKey.transFat,
    'cholesterol': NutrientKey.cholesterol,
    'sodium, na': NutrientKey.sodium,
    'potassium, k': NutrientKey.potassium,
    'calcium, ca': NutrientKey.calcium,
    'iron, fe': NutrientKey.iron,
    'magnesium, mg': NutrientKey.magnesium,
    'phosphorus, p': NutrientKey.phosphorus,
    'zinc, zn': NutrientKey.zinc,
    'copper, cu': NutrientKey.copper,
    'manganese, mn': NutrientKey.manganese,
    'selenium, se': NutrientKey.selenium,
    'vitamin a, rae': NutrientKey.vitaminA,
    'vitamin c, total ascorbic acid': NutrientKey.vitaminC,
    'vitamin d (d2 + d3)': NutrientKey.vitaminD,
    'vitamin e (alpha-tocopherol)': NutrientKey.vitaminE,
    'vitamin k (phylloquinone)': NutrientKey.vitaminK,
    'thiamin': NutrientKey.thiamin,
    'riboflavin': NutrientKey.riboflavin,
    'niacin': NutrientKey.niacin,
    'pantothenic acid': NutrientKey.pantothenicAcid,
    'vitamin b-6': NutrientKey.vitaminB6,
    'folate, total': NutrientKey.folate,
    'vitamin b-12': NutrientKey.vitaminB12,
    'choline, total': NutrientKey.choline,
  };

  static final Map<String, NutrientKey> _openFoodFactsKeyMap = {
    'energy-kcal': NutrientKey.calories,
    'water': NutrientKey.water,
    'proteins': NutrientKey.protein,
    'carbohydrates': NutrientKey.carbs,
    'fiber': NutrientKey.fiber,
    'sugars': NutrientKey.sugar,
    'added-sugars': NutrientKey.addedSugar,
    'fat': NutrientKey.fatTotal,
    'saturated-fat': NutrientKey.satFat,
    'monounsaturated-fat': NutrientKey.monoFat,
    'polyunsaturated-fat': NutrientKey.polyFat,
    'trans-fat': NutrientKey.transFat,
    'cholesterol': NutrientKey.cholesterol,
    'sodium': NutrientKey.sodium,
    'potassium': NutrientKey.potassium,
    'calcium': NutrientKey.calcium,
    'iron': NutrientKey.iron,
    'magnesium': NutrientKey.magnesium,
    'phosphorus': NutrientKey.phosphorus,
    'zinc': NutrientKey.zinc,
    'copper': NutrientKey.copper,
    'manganese': NutrientKey.manganese,
    'selenium': NutrientKey.selenium,
    'vitamin-a': NutrientKey.vitaminA,
    'vitamin-c': NutrientKey.vitaminC,
    'vitamin-d': NutrientKey.vitaminD,
    'vitamin-e': NutrientKey.vitaminE,
    'vitamin-k': NutrientKey.vitaminK,
    'vitamin-b1': NutrientKey.thiamin,
    'vitamin-b2': NutrientKey.riboflavin,
    'vitamin-pp': NutrientKey.niacin,
    'pantothenic-acid': NutrientKey.pantothenicAcid,
    'vitamin-b6': NutrientKey.vitaminB6,
    'folates': NutrientKey.folate,
    'vitamin-b12': NutrientKey.vitaminB12,
  };

  Map<NutrientKey, NutrientValue> fromUsdaFoodNutrients(List<dynamic> nutrients) {
    final result = <NutrientKey, NutrientValue>{};
    for (final raw in nutrients) {
      if (raw is! Map) continue;
      final map = Map<String, dynamic>.from(raw);
      final nutrientBlock = map['nutrient'];
      final nutrient =
          nutrientBlock is Map ? Map<String, dynamic>.from(nutrientBlock) : map;

      final key = _resolveUsdaNutrientKey(nutrient);
      if (key == null) continue;

      final amount = _parseDouble(map['amount']) ??
          _parseDouble(nutrient['amount']) ??
          _parseDouble(map['value']);
      if (amount == null) continue;
      final unitRaw = (nutrient['unitName'] ?? nutrient['unit_name'] ?? '').toString();
      final normalized = normalizeToDefaultUnit(
        key: key,
        amount: amount,
        unit: unitRaw,
      );
      result[key] = NutrientValue(
        key: key,
        amount: normalized.amount,
        unit: normalized.unit,
        displayName: nutrient['name']?.toString(),
      );
    }
    return result;
  }

  Map<NutrientKey, NutrientValue> fromOpenFoodFactsNutriments(
    Map<String, dynamic> nutriments, {
    bool perServing = false,
  }) {
    final suffix = perServing ? '_serving' : '_100g';
    final result = <NutrientKey, NutrientValue>{};
    for (final entry in _openFoodFactsKeyMap.entries) {
      final baseKey = entry.key;
      final nutrientKey = entry.value;
      final value = _parseDouble(nutriments['$baseKey$suffix']);
      if (value == null) continue;
      final unit = nutriments['${baseKey}_unit']?.toString() ?? nutrientKey.defaultUnit;
      final normalized = normalizeToDefaultUnit(
        key: nutrientKey,
        amount: value,
        unit: unit,
      );
      result[nutrientKey] = NutrientValue(
        key: nutrientKey,
        amount: normalized.amount,
        unit: normalized.unit,
      );
    }

    if (!result.containsKey(NutrientKey.calories)) {
      final energyKj = _parseDouble(nutriments['energy-kj$suffix']);
      if (energyKj != null) {
        final normalized = normalizeToDefaultUnit(
          key: NutrientKey.calories,
          amount: energyKj,
          unit: 'kJ',
        );
        result[NutrientKey.calories] = NutrientValue(
          key: NutrientKey.calories,
          amount: normalized.amount,
          unit: normalized.unit,
        );
      }
    }

    return result;
  }

  NutrientKey? _resolveUsdaNutrientKey(Map<String, dynamic> nutrient) {
    final number = nutrient['number']?.toString() ?? nutrient['nutrientNumber']?.toString();
    if (number != null && _usdaNumberMap.containsKey(number)) {
      return _usdaNumberMap[number];
    }

    final name = nutrient['name']?.toString().trim().toLowerCase();
    if (name != null && _usdaNameMap.containsKey(name)) {
      return _usdaNameMap[name];
    }

    return null;
  }

  ({double amount, String unit}) normalizeToDefaultUnit({
    required NutrientKey key,
    required double amount,
    required String unit,
  }) {
    final normalizedUnit = unit.trim().toLowerCase();
    if (key == NutrientKey.calories) {
      if (normalizedUnit == 'kj') {
        return (amount: amount / 4.184, unit: 'kcal');
      }
      return (amount: amount, unit: 'kcal');
    }

    final target = key.defaultUnit.toLowerCase();
    if (normalizedUnit.isEmpty || normalizedUnit == target) {
      return (amount: amount, unit: key.defaultUnit);
    }

    final converted = _convertMass(
      amount: amount,
      from: normalizedUnit,
      to: target,
    );
    if (converted != null) {
      return (amount: converted, unit: key.defaultUnit);
    }
    return (amount: amount, unit: unit.trim().isEmpty ? key.defaultUnit : unit);
  }

  double? _convertMass({
    required double amount,
    required String from,
    required String to,
  }) {
    const grams = {'g', 'gram', 'grams'};
    const milligrams = {'mg', 'milligram', 'milligrams'};
    const micrograms = {'ug', 'mcg', 'µg', 'microgram', 'micrograms'};

    double? inMilligrams;
    if (grams.contains(from)) {
      inMilligrams = amount * 1000;
    } else if (milligrams.contains(from)) {
      inMilligrams = amount;
    } else if (micrograms.contains(from)) {
      inMilligrams = amount / 1000;
    }

    if (inMilligrams == null) return null;

    if (grams.contains(to)) {
      return inMilligrams / 1000;
    }
    if (milligrams.contains(to)) {
      return inMilligrams;
    }
    if (micrograms.contains(to)) {
      return inMilligrams * 1000;
    }
    return null;
  }
}

double? _parseDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
