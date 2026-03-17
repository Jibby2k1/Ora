import 'food_models.dart';

enum NutrientSectionType {
  general,
  vitamins,
  minerals,
  carbohydrates,
  lipids,
  protein,
  other,
}

class FoodDiarySnapshot {
  const FoodDiarySnapshot({
    required this.day,
    required this.consumed,
    required this.targets,
    required this.totalEntries,
    required this.entriesWithMicros,
  });

  final DateTime day;
  final Map<NutrientKey, double> consumed;
  final Map<NutrientKey, double> targets;
  final int totalEntries;
  final int entriesWithMicros;

  double get micronutrientCoverage {
    if (totalEntries <= 0) return 1;
    return (entriesWithMicros / totalEntries).clamp(0.0, 1.0);
  }

  bool get shouldShowCoverageHint {
    return totalEntries >= 3 && micronutrientCoverage < 0.5;
  }
}

class MacroPieSegment {
  const MacroPieSegment({
    required this.label,
    required this.grams,
    required this.calories,
    required this.percent,
  });

  final String label;
  final double grams;
  final double calories;
  final double percent;
}

class NutrientProgressRowData {
  const NutrientProgressRowData({
    required this.id,
    required this.label,
    required this.unit,
    required this.current,
    required this.add,
    required this.projected,
    required this.target,
    required this.currentProgress,
    required this.projectedProgress,
    required this.hasTarget,
    required this.hasAnyValue,
  });

  final String id;
  final String label;
  final String unit;
  final double current;
  final double add;
  final double projected;
  final double? target;
  final double currentProgress;
  final double projectedProgress;
  final bool hasTarget;
  final bool hasAnyValue;
}

class NutrientSectionRows {
  const NutrientSectionRows({
    required this.type,
    required this.title,
    required this.rows,
  });

  final NutrientSectionType type;
  final String title;
  final List<NutrientProgressRowData> rows;
}

class FoodDetailComputedData {
  const FoodDetailComputedData({
    required this.scaledNutrients,
    required this.macroPieSegments,
    required this.macroRows,
    required this.micronutrientSections,
    required this.totalCalories,
    required this.showCoverageHint,
  });

  final Map<NutrientKey, NutrientValue> scaledNutrients;
  final List<MacroPieSegment> macroPieSegments;
  final List<NutrientProgressRowData> macroRows;
  final List<NutrientSectionRows> micronutrientSections;
  final double totalCalories;
  final bool showCoverageHint;
}
