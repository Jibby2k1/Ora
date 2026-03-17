import 'diet_entry.dart';

class DietMacroTargets {
  const DietMacroTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sodiumMg,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;
}

class DietMacroTotals {
  const DietMacroTotals({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
    required this.fiberG,
    required this.sodiumMg,
  });

  const DietMacroTotals.zero()
      : calories = 0,
        proteinG = 0,
        carbsG = 0,
        fatG = 0,
        fiberG = 0,
        sodiumMg = 0;

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
  final double fiberG;
  final double sodiumMg;

  DietMacroTotals add({
    double calories = 0,
    double proteinG = 0,
    double carbsG = 0,
    double fatG = 0,
    double fiberG = 0,
    double sodiumMg = 0,
  }) {
    return DietMacroTotals(
      calories: this.calories + calories,
      proteinG: this.proteinG + proteinG,
      carbsG: this.carbsG + carbsG,
      fatG: this.fatG + fatG,
      fiberG: this.fiberG + fiberG,
      sodiumMg: this.sodiumMg + sodiumMg,
    );
  }
}

class DietHighlightedNutrient {
  const DietHighlightedNutrient({
    required this.key,
    required this.label,
    required this.amount,
    required this.target,
    required this.unit,
  });

  final String key;
  final String label;
  final double? amount;
  final double target;
  final String unit;

  bool get hasData => amount != null;

  double get progress {
    if (!hasData || target <= 0) return 0;
    return ((amount ?? 0) / target).clamp(0.0, 1.0);
  }
}

class DietDiaryEntryItem {
  const DietDiaryEntryItem({
    required this.entry,
    required this.mealSlot,
    required this.servingDescription,
  });

  final DietEntry entry;
  final String mealSlot;
  final String servingDescription;

  double get calories {
    final explicit = entry.calories;
    if (explicit != null && explicit > 0) return explicit;
    final protein = entry.proteinG ?? 0;
    final carbs = entry.carbsG ?? 0;
    final fat = entry.fatG ?? 0;
    final derived = (protein * 4) + (carbs * 4) + (fat * 9);
    return derived > 0 ? derived : 0;
  }
}

class DietDiaryMealGroup {
  const DietDiaryMealGroup({
    required this.mealSlot,
    required this.entries,
    required this.totals,
  });

  final String mealSlot;
  final List<DietDiaryEntryItem> entries;
  final DietMacroTotals totals;
}

class DietDiaryViewModel {
  const DietDiaryViewModel({
    required this.day,
    required this.targets,
    required this.dailyTotals,
    required this.burnedCalories,
    required this.remainingCalories,
    required this.mealGroups,
    required this.highlightedNutrients,
    required this.totalEntries,
    required this.entriesWithMicros,
  });

  final DateTime day;
  final DietMacroTargets targets;
  final DietMacroTotals dailyTotals;
  final double burnedCalories;
  final double remainingCalories;
  final List<DietDiaryMealGroup> mealGroups;
  final List<DietHighlightedNutrient> highlightedNutrients;
  final int totalEntries;
  final int entriesWithMicros;

  double get micronutrientCoverage {
    if (totalEntries <= 0) return 1;
    return (entriesWithMicros / totalEntries).clamp(0.0, 1.0);
  }

  bool get shouldShowMicronutrientCoverageHint {
    return totalEntries >= 3 && micronutrientCoverage < 0.5;
  }
}
