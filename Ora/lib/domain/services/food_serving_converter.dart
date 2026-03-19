import '../models/food_models.dart';
import 'food_nutrient_scaler.dart';

enum FoodServingUnitType {
  sourceNative,
  grams,
  ounces,
  pounds,
  cups,
  fluidOunces,
  liters,
  gallons,
}

class FoodServingChoice {
  const FoodServingChoice({
    required this.id,
    required this.label,
    required this.unitLabel,
    required this.unitType,
    required this.isLiquid,
    required this.isSourceNative,
    required this.gramsPerUnit,
    required this.millilitersPerUnit,
    required this.isApproximate,
    this.sourceServing,
  });

  final String id;
  final String label;
  final String unitLabel;
  final FoodServingUnitType unitType;
  final bool isLiquid;
  final bool isSourceNative;
  final double? gramsPerUnit;
  final double? millilitersPerUnit;
  final bool isApproximate;
  final ServingOption? sourceServing;

  ServingOption toServingOption() {
    if (sourceServing != null) {
      return sourceServing!;
    }
    return ServingOption(
      id: id,
      label: label,
      amount: 1,
      unit: unitLabel,
      gramWeight: gramsPerUnit,
    );
  }
}

class FoodServingCatalog {
  const FoodServingCatalog({
    required this.food,
    required this.choices,
    required this.defaultChoiceId,
    required this.isLiquid,
  });

  final FoodItem food;
  final List<FoodServingChoice> choices;
  final String defaultChoiceId;
  final bool isLiquid;

  FoodServingChoice get defaultChoice {
    for (final choice in choices) {
      if (choice.id == defaultChoiceId) {
        return choice;
      }
    }
    return choices.first;
  }

  FoodServingChoice? byId(String id) {
    for (final choice in choices) {
      if (choice.id == id) return choice;
    }
    return null;
  }
}

class FoodServingScaleResult {
  const FoodServingScaleResult({
    required this.scaled,
    required this.choice,
    required this.isApproximate,
  });

  final FoodScaledView scaled;
  final FoodServingChoice choice;
  final bool isApproximate;
}

class FoodServingConverter {
  const FoodServingConverter({
    FoodNutrientScaler scaler = const FoodNutrientScaler(),
  }) : _scaler = scaler;

  static const double _gramsPerOunce = 28.349523125;
  static const double _gramsPerPound = 453.59237;
  static const double _millilitersPerFluidOunce = 29.5735295625;
  static const double _millilitersPerCup = 240;
  static const double _millilitersPerLiter = 1000;
  static const double _millilitersPerGallon = 3785.411784;

  final FoodNutrientScaler _scaler;

  FoodServingCatalog buildCatalog(FoodItem food) {
    final sourceChoices = <FoodServingChoice>[];
    final liquid = _looksLikeLiquid(food);
    final densityGramPerMl = _estimateDensity(food);

    String? defaultChoiceId;
    for (var i = 0; i < food.servingOptions.length; i++) {
      final serving = food.servingOptions[i];
      final grams = _resolveServingGrams(
        serving: serving,
        densityGramPerMl: densityGramPerMl,
      );
      final ml = _resolveServingMilliliters(serving: serving);
      final choice = FoodServingChoice(
        id: 'native_$i',
        label: serving.label,
        unitLabel: serving.unit?.trim().isNotEmpty == true
            ? serving.unit!.trim()
            : 'serving',
        unitType: FoodServingUnitType.sourceNative,
        isLiquid: liquid,
        isSourceNative: true,
        gramsPerUnit: grams,
        millilitersPerUnit: ml,
        isApproximate: grams == null,
        sourceServing: serving,
      );
      sourceChoices.add(choice);
      if (serving.isDefault) {
        defaultChoiceId = choice.id;
      }
    }

    final gramAnchor = _resolveGramAnchor(food, sourceChoices);
    final canOfferMass = food.nutrientsPer100g || gramAnchor != null;
    final canOfferVolume = liquid && canOfferMass;

    final generatedChoices = <FoodServingChoice>[];
    if (canOfferMass) {
      generatedChoices.add(
        const FoodServingChoice(
          id: 'std_grams',
          label: 'Grams (g)',
          unitLabel: 'g',
          unitType: FoodServingUnitType.grams,
          isLiquid: false,
          isSourceNative: false,
          gramsPerUnit: 1,
          millilitersPerUnit: null,
          isApproximate: false,
        ),
      );
      generatedChoices.add(
        const FoodServingChoice(
          id: 'std_oz',
          label: 'Ounces (oz)',
          unitLabel: 'oz',
          unitType: FoodServingUnitType.ounces,
          isLiquid: false,
          isSourceNative: false,
          gramsPerUnit: _gramsPerOunce,
          millilitersPerUnit: null,
          isApproximate: false,
        ),
      );
      generatedChoices.add(
        const FoodServingChoice(
          id: 'std_lb',
          label: 'Pounds (lb)',
          unitLabel: 'lb',
          unitType: FoodServingUnitType.pounds,
          isLiquid: false,
          isSourceNative: false,
          gramsPerUnit: _gramsPerPound,
          millilitersPerUnit: null,
          isApproximate: false,
        ),
      );
    }

    final gramsPerCup = _resolveGramsPerCup(sourceChoices, densityGramPerMl);
    if (gramsPerCup != null && gramsPerCup > 0) {
      generatedChoices.add(
        FoodServingChoice(
          id: 'std_cup',
          label: 'Cups',
          unitLabel: 'cup',
          unitType: FoodServingUnitType.cups,
          isLiquid: liquid,
          isSourceNative: false,
          gramsPerUnit: gramsPerCup,
          millilitersPerUnit: liquid ? _millilitersPerCup : null,
          isApproximate: liquid && densityGramPerMl == null,
        ),
      );
    }

    if (canOfferVolume) {
      final density = densityGramPerMl ?? 1.0;
      generatedChoices.addAll([
        FoodServingChoice(
          id: 'std_fl_oz',
          label: 'Fluid Ounces (fl oz)',
          unitLabel: 'fl oz',
          unitType: FoodServingUnitType.fluidOunces,
          isLiquid: true,
          isSourceNative: false,
          gramsPerUnit: _millilitersPerFluidOunce * density,
          millilitersPerUnit: _millilitersPerFluidOunce,
          isApproximate: densityGramPerMl == null,
        ),
        FoodServingChoice(
          id: 'std_liters',
          label: 'Liters (L)',
          unitLabel: 'L',
          unitType: FoodServingUnitType.liters,
          isLiquid: true,
          isSourceNative: false,
          gramsPerUnit: _millilitersPerLiter * density,
          millilitersPerUnit: _millilitersPerLiter,
          isApproximate: densityGramPerMl == null,
        ),
        FoodServingChoice(
          id: 'std_gallon',
          label: 'Gallon',
          unitLabel: 'gallon',
          unitType: FoodServingUnitType.gallons,
          isLiquid: true,
          isSourceNative: false,
          gramsPerUnit: _millilitersPerGallon * density,
          millilitersPerUnit: _millilitersPerGallon,
          isApproximate: densityGramPerMl == null,
        ),
      ]);
    }

    final merged = _mergeChoices(
      sourceChoices: sourceChoices,
      generatedChoices: generatedChoices,
    );

    if (defaultChoiceId == null && merged.isNotEmpty) {
      if (sourceChoices.isNotEmpty) {
        defaultChoiceId = sourceChoices.first.id;
      } else {
        defaultChoiceId = merged.first.id;
      }
    }

    return FoodServingCatalog(
      food: food,
      choices: merged,
      defaultChoiceId: defaultChoiceId ?? merged.first.id,
      isLiquid: liquid,
    );
  }

  FoodServingScaleResult scale({
    required FoodItem food,
    required FoodServingChoice choice,
    required double amount,
  }) {
    final safeAmount = amount <= 0 ? 1.0 : amount.toDouble();
    final scaled = _scaler.scale(
      food: food,
      serving: choice.toServingOption(),
      quantity: safeAmount,
    );
    return FoodServingScaleResult(
      scaled: scaled,
      choice: choice,
      isApproximate: scaled.isApproximateConversion || choice.isApproximate,
    );
  }

  List<FoodServingChoice> _mergeChoices({
    required List<FoodServingChoice> sourceChoices,
    required List<FoodServingChoice> generatedChoices,
  }) {
    final out = <FoodServingChoice>[];
    final seen = <String>{};

    void addChoice(FoodServingChoice choice) {
      final grams = choice.gramsPerUnit?.toStringAsFixed(4) ?? 'null';
      final key = '${choice.label.toLowerCase()}|$grams';
      if (!seen.add(key)) return;
      out.add(choice);
    }

    final defaultNative = sourceChoices
        .where((choice) => choice.sourceServing?.isDefault == true)
        .toList(growable: false);
    for (final choice in defaultNative) {
      addChoice(choice);
    }
    for (final choice in sourceChoices) {
      addChoice(choice);
    }
    for (final choice in generatedChoices) {
      addChoice(choice);
    }

    if (out.isEmpty) {
      out.add(
        const FoodServingChoice(
          id: 'fallback_grams',
          label: 'Grams (g)',
          unitLabel: 'g',
          unitType: FoodServingUnitType.grams,
          isLiquid: false,
          isSourceNative: false,
          gramsPerUnit: 1,
          millilitersPerUnit: null,
          isApproximate: false,
        ),
      );
    }

    return out;
  }

  bool _looksLikeLiquid(FoodItem food) {
    final liquidUnits = <String>{
      'ml',
      'milliliter',
      'milliliters',
      'l',
      'liter',
      'liters',
      'fl oz',
      'fluid ounce',
      'fluid ounces',
      'cup',
      'cups',
      'gallon',
      'gal',
      'qt',
      'pint',
      'pt',
    };
    for (final serving in food.servingOptions) {
      final unit = serving.unit?.trim().toLowerCase();
      if (unit != null && liquidUnits.contains(unit)) {
        return true;
      }
      final label = serving.label.toLowerCase();
      if (label.contains('ml') ||
          label.contains('fl oz') ||
          label.contains('fluid ounce') ||
          label.contains('liter') ||
          label.contains('gallon')) {
        return true;
      }
    }

    final lowerName = food.name.toLowerCase();
    const liquidKeywords = [
      'water',
      'juice',
      'milk',
      'drink',
      'beverage',
      'tea',
      'coffee',
      'smoothie',
      'shake',
      'soda',
      'broth',
      'soup',
      'wine',
      'beer',
    ];
    return liquidKeywords.any(lowerName.contains);
  }

  double? _estimateDensity(FoodItem food) {
    final estimates = <double>[];
    for (final serving in food.servingOptions) {
      final grams = serving.gramWeight;
      final ml = _resolveServingMilliliters(serving: serving);
      if (grams == null || grams <= 0 || ml == null || ml <= 0) continue;
      estimates.add(grams / ml);
    }

    if (estimates.isNotEmpty) {
      final total = estimates.fold<double>(0, (sum, value) => sum + value);
      return total / estimates.length;
    }

    if (_looksLikeLiquid(food)) {
      return 1.0;
    }
    return null;
  }

  double? _resolveServingMilliliters({required ServingOption serving}) {
    final double amount = serving.amount <= 0 ? 1.0 : serving.amount;
    final unit = serving.unit?.trim().toLowerCase();
    if (unit == null || unit.isEmpty) {
      return _parseMlFromLabel(serving.label);
    }
    if (unit == 'ml' || unit == 'milliliter' || unit == 'milliliters') {
      return amount;
    }
    if (unit == 'l' || unit == 'liter' || unit == 'liters') {
      return amount * _millilitersPerLiter;
    }
    if (unit == 'fl oz' || unit == 'fluid ounce' || unit == 'fluid ounces') {
      return amount * _millilitersPerFluidOunce;
    }
    if (unit == 'gallon' || unit == 'gal') {
      return amount * _millilitersPerGallon;
    }
    if (unit == 'cup' || unit == 'cups') {
      return amount * _millilitersPerCup;
    }
    return _parseMlFromLabel(serving.label);
  }

  double? _resolveServingGrams({
    required ServingOption serving,
    required double? densityGramPerMl,
  }) {
    if (serving.gramWeight != null && serving.gramWeight! > 0) {
      return serving.gramWeight!;
    }

    final unit = serving.unit?.trim().toLowerCase();
    final double amount = serving.amount <= 0 ? 1.0 : serving.amount;
    if (unit == 'g' || unit == 'gram' || unit == 'grams') {
      return amount;
    }
    if (unit == 'oz' || unit == 'ounce' || unit == 'ounces') {
      return amount * _gramsPerOunce;
    }
    if (unit == 'lb' || unit == 'lbs' || unit == 'pound' || unit == 'pounds') {
      return amount * _gramsPerPound;
    }

    final ml = _resolveServingMilliliters(serving: serving);
    if (ml != null && ml > 0 && densityGramPerMl != null) {
      return ml * densityGramPerMl;
    }
    return null;
  }

  double? _parseMlFromLabel(String label) {
    final lower = label.toLowerCase();
    final mlMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*ml\b').firstMatch(lower);
    if (mlMatch != null) {
      final parsed = double.tryParse(mlMatch.group(1) ?? '');
      if (parsed != null) return parsed;
    }
    final flOzMatch =
        RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*fl\s*oz\b').firstMatch(lower);
    if (flOzMatch != null) {
      final parsed = double.tryParse(flOzMatch.group(1) ?? '');
      if (parsed != null) return parsed * _millilitersPerFluidOunce;
    }
    final literMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*l\b').firstMatch(lower);
    if (literMatch != null) {
      final parsed = double.tryParse(literMatch.group(1) ?? '');
      if (parsed != null) return parsed * _millilitersPerLiter;
    }
    return null;
  }

  double? _resolveGramAnchor(
    FoodItem food,
    List<FoodServingChoice> sourceChoices,
  ) {
    if (food.nutrientsPer100g) return 100;
    final defaultGrams = food.defaultServing.gramWeight;
    if (defaultGrams != null && defaultGrams > 0) return defaultGrams;
    for (final choice in sourceChoices) {
      final grams = choice.gramsPerUnit;
      if (grams != null && grams > 0) {
        return grams;
      }
    }
    return null;
  }

  double? _resolveGramsPerCup(
    List<FoodServingChoice> sourceChoices,
    double? densityGramPerMl,
  ) {
    for (final choice in sourceChoices) {
      final serving = choice.sourceServing;
      if (serving == null) continue;
      final label = serving.label.toLowerCase();
      final unit = serving.unit?.toLowerCase();
      if (unit == 'cup' || unit == 'cups' || label.contains('cup')) {
        final grams = choice.gramsPerUnit;
        if (grams != null && grams > 0) {
          final cupCountFromLabel = _parseCupCountFromLabel(label);
          if (cupCountFromLabel != null && cupCountFromLabel > 0) {
            return grams / cupCountFromLabel;
          }

          if (unit == 'cup' || unit == 'cups') {
            final amount = serving.amount <= 0 ? 1 : serving.amount;
            if (amount > 0 && amount <= 8) {
              return grams / amount;
            }
          }

          // Many providers put gram amount into `amount` even for cup labels.
          // In that case `gramWeight` already represents one full cup serving.
          return grams;
        }
      }
    }
    if (densityGramPerMl != null && densityGramPerMl > 0) {
      return densityGramPerMl * _millilitersPerCup;
    }
    return null;
  }

  double? _parseCupCountFromLabel(String label) {
    final normalized = label.toLowerCase();
    if (!normalized.contains('cup')) return null;

    final mixed = RegExp(r'(\d+)\s+(\d+)\s*/\s*(\d+)\s*cup').firstMatch(
      normalized,
    );
    if (mixed != null) {
      final whole = double.tryParse(mixed.group(1) ?? '');
      final num = double.tryParse(mixed.group(2) ?? '');
      final den = double.tryParse(mixed.group(3) ?? '');
      if (whole != null && num != null && den != null && den != 0) {
        return whole + (num / den);
      }
    }

    final fraction = RegExp(r'(\d+)\s*/\s*(\d+)\s*cup').firstMatch(normalized);
    if (fraction != null) {
      final num = double.tryParse(fraction.group(1) ?? '');
      final den = double.tryParse(fraction.group(2) ?? '');
      if (num != null && den != null && den != 0) {
        return num / den;
      }
    }

    final decimal = RegExp(r'(\d+(?:\.\d+)?)\s*cup').firstMatch(normalized);
    if (decimal != null) {
      final value = double.tryParse(decimal.group(1) ?? '');
      if (value != null && value > 0) {
        return value;
      }
    }

    return 1;
  }
}
