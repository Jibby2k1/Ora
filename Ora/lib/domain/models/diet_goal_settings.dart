enum DietGoalMode {
  manualMacros,
  macroPercentages,
  optimalRatio,
}

extension DietGoalModeX on DietGoalMode {
  String get storageValue {
    switch (this) {
      case DietGoalMode.manualMacros:
        return 'manual_macros';
      case DietGoalMode.macroPercentages:
        return 'macro_percentages';
      case DietGoalMode.optimalRatio:
        return 'optimal_ratio';
    }
  }

  static DietGoalMode fromStorage(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'macro_percentages':
        return DietGoalMode.macroPercentages;
      case 'optimal_ratio':
        return DietGoalMode.optimalRatio;
      case 'manual_macros':
      default:
        return DietGoalMode.manualMacros;
    }
  }
}

enum DietOptimalGoalType {
  cutting,
  bulking,
  recomping,
  maintaining,
}

extension DietOptimalGoalTypeX on DietOptimalGoalType {
  String get storageValue {
    switch (this) {
      case DietOptimalGoalType.cutting:
        return 'cutting';
      case DietOptimalGoalType.bulking:
        return 'bulking';
      case DietOptimalGoalType.recomping:
        return 'recomping';
      case DietOptimalGoalType.maintaining:
        return 'maintaining';
    }
  }

  String get label {
    switch (this) {
      case DietOptimalGoalType.cutting:
        return 'Cutting';
      case DietOptimalGoalType.bulking:
        return 'Bulking';
      case DietOptimalGoalType.recomping:
        return 'Recomping';
      case DietOptimalGoalType.maintaining:
        return 'Maintaining';
    }
  }

  static DietOptimalGoalType fromStorage(String? raw) {
    switch (raw?.trim().toLowerCase()) {
      case 'cutting':
        return DietOptimalGoalType.cutting;
      case 'bulking':
        return DietOptimalGoalType.bulking;
      case 'recomping':
        return DietOptimalGoalType.recomping;
      case 'maintaining':
      default:
        return DietOptimalGoalType.maintaining;
    }
  }
}

class DietGoalTargets {
  const DietGoalTargets({
    required this.calories,
    required this.proteinG,
    required this.carbsG,
    required this.fatG,
  });

  final double calories;
  final double proteinG;
  final double carbsG;
  final double fatG;
}

class DietMacroRatio {
  const DietMacroRatio({
    required this.proteinPercent,
    required this.carbPercent,
    required this.fatPercent,
  });

  final double proteinPercent;
  final double carbPercent;
  final double fatPercent;

  static DietMacroRatio presetFor(DietOptimalGoalType type) {
    switch (type) {
      case DietOptimalGoalType.cutting:
        return const DietMacroRatio(
          proteinPercent: 35,
          carbPercent: 35,
          fatPercent: 30,
        );
      case DietOptimalGoalType.bulking:
        return const DietMacroRatio(
          proteinPercent: 25,
          carbPercent: 50,
          fatPercent: 25,
        );
      case DietOptimalGoalType.recomping:
        return const DietMacroRatio(
          proteinPercent: 35,
          carbPercent: 40,
          fatPercent: 25,
        );
      case DietOptimalGoalType.maintaining:
        return const DietMacroRatio(
          proteinPercent: 30,
          carbPercent: 40,
          fatPercent: 30,
        );
    }
  }
}

class DietGoalSettings {
  const DietGoalSettings({
    required this.mode,
    required this.manualProteinG,
    required this.manualCarbsG,
    required this.manualFatG,
    required this.percentageCalories,
    required this.percentageProtein,
    required this.percentageCarbs,
    required this.percentageFat,
    required this.optimalCalories,
    required this.optimalGoalType,
  });

  final DietGoalMode mode;

  final double manualProteinG;
  final double manualCarbsG;
  final double manualFatG;

  final double percentageCalories;
  final double percentageProtein;
  final double percentageCarbs;
  final double percentageFat;

  final double optimalCalories;
  final DietOptimalGoalType optimalGoalType;

  double get manualCaloriesEstimate =>
      manualProteinG * 4 + manualCarbsG * 4 + manualFatG * 9;

  double get percentageTotal =>
      percentageProtein + percentageCarbs + percentageFat;

  DietMacroRatio get optimalRatio => DietMacroRatio.presetFor(optimalGoalType);

  DietGoalTargets effectiveTargetsForMode(DietGoalMode targetMode) {
    switch (targetMode) {
      case DietGoalMode.manualMacros:
        return DietGoalTargets(
          calories: manualCaloriesEstimate,
          proteinG: manualProteinG,
          carbsG: manualCarbsG,
          fatG: manualFatG,
        );
      case DietGoalMode.macroPercentages:
        return DietGoalTargets(
          calories: percentageCalories,
          proteinG: (percentageCalories * (percentageProtein / 100)) / 4,
          carbsG: (percentageCalories * (percentageCarbs / 100)) / 4,
          fatG: (percentageCalories * (percentageFat / 100)) / 9,
        );
      case DietGoalMode.optimalRatio:
        final ratio = optimalRatio;
        return DietGoalTargets(
          calories: optimalCalories,
          proteinG: (optimalCalories * (ratio.proteinPercent / 100)) / 4,
          carbsG: (optimalCalories * (ratio.carbPercent / 100)) / 4,
          fatG: (optimalCalories * (ratio.fatPercent / 100)) / 9,
        );
    }
  }
}
