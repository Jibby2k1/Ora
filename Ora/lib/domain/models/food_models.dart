import 'package:flutter/foundation.dart';

enum FoodSource {
  usdaFdc,
  openFoodFacts,
  nutritionix,
  custom,
}

extension FoodSourceX on FoodSource {
  String get cacheKey => switch (this) {
        FoodSource.usdaFdc => 'usda_fdc',
        FoodSource.openFoodFacts => 'open_food_facts',
        FoodSource.nutritionix => 'nutritionix',
        FoodSource.custom => 'custom',
      };

  String get label => switch (this) {
        FoodSource.usdaFdc => 'USDA',
        FoodSource.openFoodFacts => 'OFF',
        FoodSource.nutritionix => 'NUTRITIONIX',
        FoodSource.custom => 'CUSTOM',
      };
}

enum FoodSearchCategory {
  all,
  commonFoods,
  branded,
  custom,
}

extension FoodSearchCategoryX on FoodSearchCategory {
  String get label => switch (this) {
        FoodSearchCategory.all => 'All',
        FoodSearchCategory.commonFoods => 'Generic',
        FoodSearchCategory.branded => 'Branded',
        FoodSearchCategory.custom => 'Custom',
      };
}

@immutable
class FoodSearchFilters {
  const FoodSearchFilters({
    this.category = FoodSearchCategory.all,
  });

  final FoodSearchCategory category;
}

@immutable
class FoodSearchResult {
  const FoodSearchResult({
    required this.id,
    required this.source,
    required this.name,
    this.brand,
    this.barcode,
    this.subtitle,
    this.dataType,
    this.isBranded = false,
    this.hasRichNutrientPanel = false,
  });

  final String id;
  final FoodSource source;
  final String name;
  final String? brand;
  final String? barcode;
  final String? subtitle;
  final String? dataType;
  final bool isBranded;
  final bool hasRichNutrientPanel;

  FoodResultType get resultType {
    if (source == FoodSource.custom) {
      return FoodResultType.custom;
    }
    final normalizedDataType = (dataType ?? '').toLowerCase().trim();
    if (isBranded || normalizedDataType.contains('branded')) {
      return FoodResultType.branded;
    }
    return FoodResultType.generic;
  }

  String get resultTypeLabel => resultType.label;
}

enum FoodResultType {
  generic,
  branded,
  custom,
}

extension FoodResultTypeX on FoodResultType {
  String get label => switch (this) {
        FoodResultType.generic => 'Generic',
        FoodResultType.branded => 'Branded',
        FoodResultType.custom => 'Custom',
      };
}

enum NutrientGroup {
  general,
  carbs,
  lipids,
  protein,
  minerals,
  vitamins,
}

enum NutrientKey {
  calories,
  water,
  protein,
  carbs,
  fiber,
  sugar,
  addedSugar,
  fatTotal,
  satFat,
  monoFat,
  polyFat,
  transFat,
  cholesterol,
  sodium,
  potassium,
  calcium,
  iron,
  magnesium,
  phosphorus,
  zinc,
  copper,
  manganese,
  selenium,
  vitaminA,
  vitaminC,
  vitaminD,
  vitaminE,
  vitaminK,
  thiamin,
  riboflavin,
  niacin,
  pantothenicAcid,
  vitaminB6,
  folate,
  vitaminB12,
  choline,
}

extension NutrientKeyX on NutrientKey {
  String get id => name;

  NutrientGroup get group => switch (this) {
        NutrientKey.calories || NutrientKey.water => NutrientGroup.general,
        NutrientKey.carbs ||
        NutrientKey.fiber ||
        NutrientKey.sugar ||
        NutrientKey.addedSugar =>
          NutrientGroup.carbs,
        NutrientKey.fatTotal ||
        NutrientKey.satFat ||
        NutrientKey.monoFat ||
        NutrientKey.polyFat ||
        NutrientKey.transFat ||
        NutrientKey.cholesterol =>
          NutrientGroup.lipids,
        NutrientKey.protein => NutrientGroup.protein,
        NutrientKey.sodium ||
        NutrientKey.potassium ||
        NutrientKey.calcium ||
        NutrientKey.iron ||
        NutrientKey.magnesium ||
        NutrientKey.phosphorus ||
        NutrientKey.zinc ||
        NutrientKey.copper ||
        NutrientKey.manganese ||
        NutrientKey.selenium =>
          NutrientGroup.minerals,
        NutrientKey.vitaminA ||
        NutrientKey.vitaminC ||
        NutrientKey.vitaminD ||
        NutrientKey.vitaminE ||
        NutrientKey.vitaminK ||
        NutrientKey.thiamin ||
        NutrientKey.riboflavin ||
        NutrientKey.niacin ||
        NutrientKey.pantothenicAcid ||
        NutrientKey.vitaminB6 ||
        NutrientKey.folate ||
        NutrientKey.vitaminB12 ||
        NutrientKey.choline =>
          NutrientGroup.vitamins,
      };

  String get label => switch (this) {
        NutrientKey.calories => 'Calories',
        NutrientKey.water => 'Water',
        NutrientKey.protein => 'Protein',
        NutrientKey.carbs => 'Total Carbs',
        NutrientKey.fiber => 'Fiber',
        NutrientKey.sugar => 'Sugar',
        NutrientKey.addedSugar => 'Added Sugar',
        NutrientKey.fatTotal => 'Total Fat',
        NutrientKey.satFat => 'Saturated Fat',
        NutrientKey.monoFat => 'Monounsaturated Fat',
        NutrientKey.polyFat => 'Polyunsaturated Fat',
        NutrientKey.transFat => 'Trans Fat',
        NutrientKey.cholesterol => 'Cholesterol',
        NutrientKey.sodium => 'Sodium',
        NutrientKey.potassium => 'Potassium',
        NutrientKey.calcium => 'Calcium',
        NutrientKey.iron => 'Iron',
        NutrientKey.magnesium => 'Magnesium',
        NutrientKey.phosphorus => 'Phosphorus',
        NutrientKey.zinc => 'Zinc',
        NutrientKey.copper => 'Copper',
        NutrientKey.manganese => 'Manganese',
        NutrientKey.selenium => 'Selenium',
        NutrientKey.vitaminA => 'Vitamin A',
        NutrientKey.vitaminC => 'Vitamin C',
        NutrientKey.vitaminD => 'Vitamin D',
        NutrientKey.vitaminE => 'Vitamin E',
        NutrientKey.vitaminK => 'Vitamin K',
        NutrientKey.thiamin => 'Thiamin (B1)',
        NutrientKey.riboflavin => 'Riboflavin (B2)',
        NutrientKey.niacin => 'Niacin (B3)',
        NutrientKey.pantothenicAcid => 'Pantothenic Acid (B5)',
        NutrientKey.vitaminB6 => 'Vitamin B6',
        NutrientKey.folate => 'Folate',
        NutrientKey.vitaminB12 => 'Vitamin B12',
        NutrientKey.choline => 'Choline',
      };

  String get defaultUnit => switch (this) {
        NutrientKey.calories => 'kcal',
        NutrientKey.water => 'g',
        NutrientKey.protein ||
        NutrientKey.carbs ||
        NutrientKey.fiber ||
        NutrientKey.sugar ||
        NutrientKey.addedSugar ||
        NutrientKey.fatTotal ||
        NutrientKey.satFat ||
        NutrientKey.monoFat ||
        NutrientKey.polyFat ||
        NutrientKey.transFat =>
          'g',
        NutrientKey.cholesterol ||
        NutrientKey.sodium ||
        NutrientKey.potassium ||
        NutrientKey.calcium ||
        NutrientKey.iron ||
        NutrientKey.magnesium ||
        NutrientKey.phosphorus ||
        NutrientKey.zinc ||
        NutrientKey.copper ||
        NutrientKey.manganese ||
        NutrientKey.selenium ||
        NutrientKey.vitaminC ||
        NutrientKey.vitaminE ||
        NutrientKey.thiamin ||
        NutrientKey.riboflavin ||
        NutrientKey.niacin ||
        NutrientKey.pantothenicAcid ||
        NutrientKey.vitaminB6 ||
        NutrientKey.folate ||
        NutrientKey.vitaminB12 ||
        NutrientKey.choline =>
          'mg',
        NutrientKey.vitaminA ||
        NutrientKey.vitaminD ||
        NutrientKey.vitaminK =>
          'mcg',
      };
}

@immutable
class ServingOption {
  const ServingOption({
    required this.id,
    required this.label,
    this.amount = 1,
    this.unit,
    this.gramWeight,
    this.isDefault = false,
  });

  final String id;
  final String label;
  final double amount;
  final String? unit;
  final double? gramWeight;
  final bool isDefault;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'label': label,
      'amount': amount,
      'unit': unit,
      'gramWeight': gramWeight,
      'isDefault': isDefault,
    };
  }

  factory ServingOption.fromJson(Map<String, dynamic> json) {
    return ServingOption(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      amount: _parseDouble(json['amount']) ?? 1,
      unit: json['unit']?.toString(),
      gramWeight: _parseDouble(json['gramWeight']),
      isDefault: json['isDefault'] == true,
    );
  }
}

@immutable
class NutrientValue {
  const NutrientValue({
    required this.key,
    required this.amount,
    required this.unit,
    this.displayName,
  });

  final NutrientKey key;
  final double amount;
  final String unit;
  final String? displayName;

  String get label => displayName ?? key.label;

  NutrientValue copyWith({
    double? amount,
    String? unit,
    String? displayName,
  }) {
    return NutrientValue(
      key: key,
      amount: amount ?? this.amount,
      unit: unit ?? this.unit,
      displayName: displayName ?? this.displayName,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'key': key.id,
      'amount': amount,
      'unit': unit,
      'displayName': displayName,
    };
  }

  factory NutrientValue.fromJson(Map<String, dynamic> json) {
    final keyName = json['key']?.toString() ?? '';
    final key = NutrientKey.values.firstWhere(
      (value) => value.id == keyName,
      orElse: () => NutrientKey.calories,
    );
    return NutrientValue(
      key: key,
      amount: _parseDouble(json['amount']) ?? 0,
      unit: json['unit']?.toString() ?? key.defaultUnit,
      displayName: json['displayName']?.toString(),
    );
  }
}

@immutable
class FoodItem {
  const FoodItem({
    required this.id,
    required this.source,
    required this.name,
    required this.servingOptions,
    required this.nutrients,
    required this.lastUpdated,
    this.brand,
    this.barcode,
    this.ingredientsText,
    this.nutrientsPer100g = true,
    this.sourceDescription,
  });

  final String id;
  final FoodSource source;
  final String name;
  final String? brand;
  final String? barcode;
  final String? ingredientsText;
  final List<ServingOption> servingOptions;
  final Map<NutrientKey, NutrientValue> nutrients;
  final bool nutrientsPer100g;
  final DateTime lastUpdated;
  final String? sourceDescription;

  ServingOption get defaultServing {
    if (servingOptions.isEmpty) {
      return const ServingOption(
        id: 'default',
        label: '100 g',
        amount: 100,
        unit: 'g',
        gramWeight: 100,
        isDefault: true,
      );
    }
    return servingOptions.firstWhere(
      (option) => option.isDefault,
      orElse: () => servingOptions.first,
    );
  }

  double? get calories => nutrients[NutrientKey.calories]?.amount;
  double? get protein => nutrients[NutrientKey.protein]?.amount;
  double? get carbs => nutrients[NutrientKey.carbs]?.amount;
  double? get fat => nutrients[NutrientKey.fatTotal]?.amount;
  double? get fiber => nutrients[NutrientKey.fiber]?.amount;
  double? get sugar => nutrients[NutrientKey.sugar]?.amount;
  double? get sodium => nutrients[NutrientKey.sodium]?.amount;
  double? get cholesterol => nutrients[NutrientKey.cholesterol]?.amount;
  double? get saturatedFat => nutrients[NutrientKey.satFat]?.amount;

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'source': source.cacheKey,
      'name': name,
      'brand': brand,
      'barcode': barcode,
      'ingredientsText': ingredientsText,
      'servingOptions':
          servingOptions.map((option) => option.toJson()).toList(),
      'nutrients': nutrients.map(
        (key, value) => MapEntry(key.id, value.toJson()),
      ),
      'nutrientsPer100g': nutrientsPer100g,
      'lastUpdated': lastUpdated.toIso8601String(),
      'sourceDescription': sourceDescription,
    };
  }

  factory FoodItem.fromJson(Map<String, dynamic> json) {
    final sourceRaw = json['source']?.toString() ?? FoodSource.custom.cacheKey;
    final source = FoodSource.values.firstWhere(
      (value) => value.cacheKey == sourceRaw,
      orElse: () => FoodSource.custom,
    );

    final servingRaw = json['servingOptions'];
    final servingOptions = <ServingOption>[];
    if (servingRaw is List) {
      for (final item in servingRaw) {
        if (item is Map<String, dynamic>) {
          servingOptions.add(ServingOption.fromJson(item));
        } else if (item is Map) {
          servingOptions
              .add(ServingOption.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    }

    final nutrientMap = <NutrientKey, NutrientValue>{};
    final nutrientRaw = json['nutrients'];
    if (nutrientRaw is Map) {
      for (final entry in nutrientRaw.entries) {
        final keyName = entry.key.toString();
        final key = NutrientKey.values.firstWhere(
          (value) => value.id == keyName,
          orElse: () => NutrientKey.calories,
        );
        final valueJson = entry.value;
        if (valueJson is Map<String, dynamic>) {
          nutrientMap[key] = NutrientValue.fromJson(valueJson);
        } else if (valueJson is Map) {
          nutrientMap[key] =
              NutrientValue.fromJson(Map<String, dynamic>.from(valueJson));
        }
      }
    }

    return FoodItem(
      id: json['id']?.toString() ?? '',
      source: source,
      name: json['name']?.toString() ?? '',
      brand: json['brand']?.toString(),
      barcode: json['barcode']?.toString(),
      ingredientsText: json['ingredientsText']?.toString(),
      servingOptions: servingOptions,
      nutrients: nutrientMap,
      nutrientsPer100g: json['nutrientsPer100g'] != false,
      lastUpdated: DateTime.tryParse(json['lastUpdated']?.toString() ?? '') ??
          DateTime.now(),
      sourceDescription: json['sourceDescription']?.toString(),
    );
  }
}

double? _parseDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
