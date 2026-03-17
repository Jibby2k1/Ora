import '../models/food_detail_computed.dart';
import '../models/food_models.dart';

class FoodDetailComputer {
  const FoodDetailComputer();

  static const Map<NutrientKey, double> defaultMicronutrientTargets = {
    NutrientKey.water: 3700,
    NutrientKey.fiber: 30,
    NutrientKey.sugar: 50,
    NutrientKey.addedSugar: 50,
    NutrientKey.satFat: 20,
    NutrientKey.cholesterol: 300,
    NutrientKey.sodium: 2300,
    NutrientKey.potassium: 3400,
    NutrientKey.calcium: 1000,
    NutrientKey.iron: 18,
    NutrientKey.magnesium: 420,
    NutrientKey.phosphorus: 700,
    NutrientKey.zinc: 11,
    NutrientKey.copper: 0.9,
    NutrientKey.manganese: 2.3,
    NutrientKey.selenium: 55,
    NutrientKey.vitaminA: 900,
    NutrientKey.vitaminC: 90,
    NutrientKey.vitaminD: 20,
    NutrientKey.vitaminE: 15,
    NutrientKey.vitaminK: 120,
    NutrientKey.thiamin: 1.2,
    NutrientKey.riboflavin: 1.3,
    NutrientKey.niacin: 16,
    NutrientKey.pantothenicAcid: 5,
    NutrientKey.vitaminB6: 1.7,
    NutrientKey.folate: 400,
    NutrientKey.vitaminB12: 2.4,
    NutrientKey.choline: 550,
  };

  FoodDetailComputedData compute({
    required Map<NutrientKey, NutrientValue> scaledNutrients,
    required FoodDiarySnapshot diary,
    required bool showAllNutrients,
  }) {
    final macros = _buildMacroRows(
      scaledNutrients: scaledNutrients,
      diary: diary,
    );
    final sections = _buildMicronutrientSections(
      scaledNutrients: scaledNutrients,
      diary: diary,
      showAllNutrients: showAllNutrients,
    );

    final proteinKcal = _scaledAmount(scaledNutrients, NutrientKey.protein) * 4;
    final carbsKcal = _scaledAmount(scaledNutrients, NutrientKey.carbs) * 4;
    final fatKcal = _scaledAmount(scaledNutrients, NutrientKey.fatTotal) * 9;
    final totalMacroKcal = proteinKcal + carbsKcal + fatKcal;
    final caloriesFromSource =
        _scaledAmount(scaledNutrients, NutrientKey.calories);
    final effectiveCalories =
        caloriesFromSource > 0 ? caloriesFromSource : totalMacroKcal;

    List<MacroPieSegment> macroPieSegments;
    if (totalMacroKcal <= 0) {
      macroPieSegments = const [
        MacroPieSegment(label: 'Protein', grams: 0, calories: 0, percent: 0),
        MacroPieSegment(label: 'Carbs', grams: 0, calories: 0, percent: 0),
        MacroPieSegment(label: 'Fat', grams: 0, calories: 0, percent: 0),
      ];
    } else {
      macroPieSegments = [
        MacroPieSegment(
          label: 'Protein',
          grams: _scaledAmount(scaledNutrients, NutrientKey.protein),
          calories: proteinKcal,
          percent: proteinKcal / totalMacroKcal,
        ),
        MacroPieSegment(
          label: 'Carbs',
          grams: _scaledAmount(scaledNutrients, NutrientKey.carbs),
          calories: carbsKcal,
          percent: carbsKcal / totalMacroKcal,
        ),
        MacroPieSegment(
          label: 'Fat',
          grams: _scaledAmount(scaledNutrients, NutrientKey.fatTotal),
          calories: fatKcal,
          percent: fatKcal / totalMacroKcal,
        ),
      ];
    }

    return FoodDetailComputedData(
      scaledNutrients: scaledNutrients,
      macroPieSegments: macroPieSegments,
      macroRows: macros,
      micronutrientSections: sections,
      totalCalories: effectiveCalories,
      showCoverageHint: diary.shouldShowCoverageHint,
    );
  }

  List<NutrientProgressRowData> _buildMacroRows({
    required Map<NutrientKey, NutrientValue> scaledNutrients,
    required FoodDiarySnapshot diary,
  }) {
    final caloriesAdd = _effectiveCalories(scaledNutrients);
    return [
      _buildProgressRow(
        id: 'calories',
        label: 'Calories',
        unit: 'kcal',
        current: (diary.consumed[NutrientKey.calories] ?? 0).toDouble(),
        add: caloriesAdd,
        target: _resolveTarget(diary, NutrientKey.calories),
      ),
      _buildKeyRow(
        id: 'protein',
        label: 'Protein',
        key: NutrientKey.protein,
        unit: 'g',
        scaledNutrients: scaledNutrients,
        diary: diary,
      ),
      _buildKeyRow(
        id: 'carbs',
        label: 'Carbs',
        key: NutrientKey.carbs,
        unit: 'g',
        scaledNutrients: scaledNutrients,
        diary: diary,
      ),
      _buildKeyRow(
        id: 'fat',
        label: 'Fat',
        key: NutrientKey.fatTotal,
        unit: 'g',
        scaledNutrients: scaledNutrients,
        diary: diary,
      ),
    ];
  }

  List<NutrientSectionRows> _buildMicronutrientSections({
    required Map<NutrientKey, NutrientValue> scaledNutrients,
    required FoodDiarySnapshot diary,
    required bool showAllNutrients,
  }) {
    final sections = <NutrientSectionRows>[];

    List<NutrientProgressRowData> buildRows(
      NutrientSectionType type,
      List<_RowDef> definitions,
    ) {
      final rows = <NutrientProgressRowData>[];
      for (final row in definitions) {
        final data = _buildRow(
          definition: row,
          scaledNutrients: scaledNutrients,
          diary: diary,
        );
        if (showAllNutrients || data.hasAnyValue || data.hasTarget) {
          rows.add(data);
        }
      }
      return rows;
    }

    final generalRows = buildRows(NutrientSectionType.general, const [
      _RowDef.key(
        id: 'energy',
        label: 'Energy',
        key: NutrientKey.calories,
        unit: 'kcal',
      ),
      _RowDef.key(
        id: 'water',
        label: 'Water',
        key: NutrientKey.water,
        unit: 'g',
      ),
      _RowDef.placeholder(id: 'alcohol', label: 'Alcohol', unit: 'g'),
      _RowDef.placeholder(id: 'caffeine', label: 'Caffeine', unit: 'mg'),
    ]);
    if (generalRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.general,
          title: 'General',
          rows: generalRows,
        ),
      );
    }

    final vitaminRows = buildRows(NutrientSectionType.vitamins, const [
      _RowDef.key(
        id: 'b1',
        label: 'B1 (Thiamine)',
        key: NutrientKey.thiamin,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'b2',
        label: 'B2 (Riboflavin)',
        key: NutrientKey.riboflavin,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'b3',
        label: 'B3 (Niacin)',
        key: NutrientKey.niacin,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'b5',
        label: 'B5 (Pantothenic Acid)',
        key: NutrientKey.pantothenicAcid,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'b6',
        label: 'B6 (Pyridoxine)',
        key: NutrientKey.vitaminB6,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'b12',
        label: 'B12 (Cobalamin)',
        key: NutrientKey.vitaminB12,
        unit: 'mcg',
      ),
      _RowDef.key(
        id: 'folate',
        label: 'Folate',
        key: NutrientKey.folate,
        unit: 'mcg',
      ),
      _RowDef.key(
        id: 'vitamin_a',
        label: 'Vitamin A',
        key: NutrientKey.vitaminA,
        unit: 'mcg',
      ),
      _RowDef.key(
        id: 'vitamin_c',
        label: 'Vitamin C',
        key: NutrientKey.vitaminC,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'vitamin_d',
        label: 'Vitamin D',
        key: NutrientKey.vitaminD,
        unit: 'mcg',
      ),
      _RowDef.key(
        id: 'vitamin_e',
        label: 'Vitamin E',
        key: NutrientKey.vitaminE,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'vitamin_k',
        label: 'Vitamin K',
        key: NutrientKey.vitaminK,
        unit: 'mcg',
      ),
    ]);
    if (vitaminRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.vitamins,
          title: 'Vitamins',
          rows: vitaminRows,
        ),
      );
    }

    final mineralRows = buildRows(NutrientSectionType.minerals, const [
      _RowDef.key(
        id: 'calcium',
        label: 'Calcium',
        key: NutrientKey.calcium,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'copper',
        label: 'Copper',
        key: NutrientKey.copper,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'iron',
        label: 'Iron',
        key: NutrientKey.iron,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'magnesium',
        label: 'Magnesium',
        key: NutrientKey.magnesium,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'manganese',
        label: 'Manganese',
        key: NutrientKey.manganese,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'phosphorus',
        label: 'Phosphorus',
        key: NutrientKey.phosphorus,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'potassium',
        label: 'Potassium',
        key: NutrientKey.potassium,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'selenium',
        label: 'Selenium',
        key: NutrientKey.selenium,
        unit: 'mcg',
      ),
      _RowDef.key(
        id: 'sodium',
        label: 'Sodium',
        key: NutrientKey.sodium,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'zinc',
        label: 'Zinc',
        key: NutrientKey.zinc,
        unit: 'mg',
      ),
    ]);
    if (mineralRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.minerals,
          title: 'Minerals',
          rows: mineralRows,
        ),
      );
    }

    final carbRows = buildRows(NutrientSectionType.carbohydrates, const [
      _RowDef.key(
        id: 'carbs_total',
        label: 'Carbs (Total)',
        key: NutrientKey.carbs,
        unit: 'g',
      ),
      _RowDef.key(
        id: 'fiber',
        label: 'Fiber',
        key: NutrientKey.fiber,
        unit: 'g',
      ),
      _RowDef.derived(
        id: 'net_carbs',
        label: 'Net Carbs',
        unit: 'g',
        computeCurrent: _deriveNetCarbsCurrent,
        computeAdd: _deriveNetCarbsAdd,
      ),
      _RowDef.placeholder(id: 'starch', label: 'Starch', unit: 'g'),
      _RowDef.key(
        id: 'sugars',
        label: 'Sugars',
        key: NutrientKey.sugar,
        unit: 'g',
      ),
      _RowDef.key(
        id: 'added_sugars',
        label: 'Added Sugars',
        key: NutrientKey.addedSugar,
        unit: 'g',
      ),
    ]);
    if (carbRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.carbohydrates,
          title: 'Carbohydrates',
          rows: carbRows,
        ),
      );
    }

    final lipidRows = buildRows(NutrientSectionType.lipids, const [
      _RowDef.key(
        id: 'cholesterol',
        label: 'Cholesterol',
        key: NutrientKey.cholesterol,
        unit: 'mg',
      ),
      _RowDef.key(
        id: 'fat',
        label: 'Fat',
        key: NutrientKey.fatTotal,
        unit: 'g',
      ),
      _RowDef.key(
        id: 'mono_fat',
        label: 'Fat (Monounsaturated)',
        key: NutrientKey.monoFat,
        unit: 'g',
      ),
      _RowDef.key(
        id: 'poly_fat',
        label: 'Fat (Polyunsaturated)',
        key: NutrientKey.polyFat,
        unit: 'g',
      ),
      _RowDef.placeholder(id: 'omega_3', label: 'Omega 3', unit: 'g'),
      _RowDef.placeholder(id: 'omega_6', label: 'Omega 6', unit: 'g'),
      _RowDef.key(
        id: 'sat_fat',
        label: 'Fat (Saturated)',
        key: NutrientKey.satFat,
        unit: 'g',
      ),
      _RowDef.key(
        id: 'trans_fat',
        label: 'Fat (Trans)',
        key: NutrientKey.transFat,
        unit: 'g',
      ),
    ]);
    if (lipidRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.lipids,
          title: 'Lipids',
          rows: lipidRows,
        ),
      );
    }

    final proteinRows = buildRows(NutrientSectionType.protein, const [
      _RowDef.key(
        id: 'protein',
        label: 'Protein',
        key: NutrientKey.protein,
        unit: 'g',
      ),
      _RowDef.placeholder(id: 'cystine', label: 'Cystine', unit: 'g'),
      _RowDef.placeholder(id: 'histidine', label: 'Histidine', unit: 'g'),
      _RowDef.placeholder(id: 'isoleucine', label: 'Isoleucine', unit: 'g'),
      _RowDef.placeholder(id: 'leucine', label: 'Leucine', unit: 'g'),
      _RowDef.placeholder(id: 'lysine', label: 'Lysine', unit: 'g'),
      _RowDef.placeholder(id: 'methionine', label: 'Methionine', unit: 'g'),
      _RowDef.placeholder(
        id: 'phenylalanine',
        label: 'Phenylalanine',
        unit: 'g',
      ),
      _RowDef.placeholder(id: 'threonine', label: 'Threonine', unit: 'g'),
      _RowDef.placeholder(id: 'tryptophan', label: 'Tryptophan', unit: 'g'),
      _RowDef.placeholder(id: 'tyrosine', label: 'Tyrosine', unit: 'g'),
      _RowDef.placeholder(id: 'valine', label: 'Valine', unit: 'g'),
    ]);
    if (proteinRows.isNotEmpty) {
      sections.add(
        NutrientSectionRows(
          type: NutrientSectionType.protein,
          title: 'Protein / Amino Acids',
          rows: proteinRows,
        ),
      );
    }

    return sections;
  }

  NutrientProgressRowData _buildKeyRow({
    required String id,
    required String label,
    required NutrientKey key,
    required String unit,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
    required FoodDiarySnapshot diary,
  }) {
    final current = (diary.consumed[key] ?? 0).toDouble();
    final add = _scaledAmount(scaledNutrients, key);
    final target = _resolveTarget(diary, key);
    return _buildProgressRow(
      id: id,
      label: label,
      unit: unit,
      current: current,
      add: add,
      target: target,
    );
  }

  NutrientProgressRowData _buildRow({
    required _RowDef definition,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
    required FoodDiarySnapshot diary,
  }) {
    final target =
        definition.key != null ? _resolveTarget(diary, definition.key!) : null;
    final current = definition.currentValue(
      consumed: diary.consumed,
      scaledNutrients: scaledNutrients,
    );
    final add = definition.addValue(
      consumed: diary.consumed,
      scaledNutrients: scaledNutrients,
    );

    return _buildProgressRow(
      id: definition.id,
      label: definition.label,
      unit: definition.unit,
      current: current,
      add: add,
      target: target,
    );
  }

  NutrientProgressRowData _buildProgressRow({
    required String id,
    required String label,
    required String unit,
    required double current,
    required double add,
    required double? target,
  }) {
    final projected = current + add;
    final hasTarget = target != null && target > 0;
    final safeTarget = hasTarget ? target : 1.0;
    final currentProgress =
        hasTarget ? (current / safeTarget).clamp(0.0, 1.0).toDouble() : 0.0;
    final projectedProgress =
        hasTarget ? (projected / safeTarget).clamp(0.0, 1.0).toDouble() : 0.0;

    return NutrientProgressRowData(
      id: id,
      label: label,
      unit: unit,
      current: current,
      add: add,
      projected: projected,
      target: hasTarget ? target : null,
      currentProgress: currentProgress,
      projectedProgress: projectedProgress,
      hasTarget: hasTarget,
      hasAnyValue: current > 0 || add > 0,
    );
  }

  double _scaledAmount(
    Map<NutrientKey, NutrientValue> scaledNutrients,
    NutrientKey key,
  ) {
    return (scaledNutrients[key]?.amount ?? 0).toDouble();
  }

  double _effectiveCalories(Map<NutrientKey, NutrientValue> scaledNutrients) {
    final calories = _scaledAmount(scaledNutrients, NutrientKey.calories);
    if (calories > 0) return calories;
    final protein = _scaledAmount(scaledNutrients, NutrientKey.protein);
    final carbs = _scaledAmount(scaledNutrients, NutrientKey.carbs);
    final fat = _scaledAmount(scaledNutrients, NutrientKey.fatTotal);
    return (protein * 4) + (carbs * 4) + (fat * 9);
  }

  double? _resolveTarget(FoodDiarySnapshot diary, NutrientKey key) {
    final explicit = diary.targets[key];
    if (explicit != null && explicit > 0) return explicit;
    return defaultMicronutrientTargets[key];
  }

  static double _deriveNetCarbsCurrent({
    required Map<NutrientKey, double> consumed,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
  }) {
    final carbs = consumed[NutrientKey.carbs] ?? 0;
    final fiber = consumed[NutrientKey.fiber] ?? 0;
    return (carbs - fiber).clamp(0.0, double.infinity).toDouble();
  }

  static double _deriveNetCarbsAdd({
    required Map<NutrientKey, double> consumed,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
  }) {
    final carbs = scaledNutrients[NutrientKey.carbs]?.amount ?? 0;
    final fiber = scaledNutrients[NutrientKey.fiber]?.amount ?? 0;
    return (carbs - fiber).clamp(0.0, double.infinity).toDouble();
  }
}

typedef _NutrientCompute = double Function({
  required Map<NutrientKey, double> consumed,
  required Map<NutrientKey, NutrientValue> scaledNutrients,
});

class _RowDef {
  const _RowDef.key({
    required this.id,
    required this.label,
    required this.key,
    required this.unit,
  })  : _current = null,
        _add = null;

  const _RowDef.derived({
    required this.id,
    required this.label,
    required this.unit,
    required _NutrientCompute computeCurrent,
    required _NutrientCompute computeAdd,
  })  : key = null,
        _current = computeCurrent,
        _add = computeAdd;

  const _RowDef.placeholder({
    required this.id,
    required this.label,
    required this.unit,
  })  : key = null,
        _current = null,
        _add = null;

  final String id;
  final String label;
  final NutrientKey? key;
  final String unit;
  final _NutrientCompute? _current;
  final _NutrientCompute? _add;

  double currentValue({
    required Map<NutrientKey, double> consumed,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
  }) {
    if (key != null) {
      final rowKey = key;
      if (rowKey != null) {
        return consumed[rowKey] ?? 0;
      }
    }
    final currentComputer = _current;
    if (currentComputer != null) {
      return currentComputer(
        consumed: consumed,
        scaledNutrients: scaledNutrients,
      );
    }
    return 0;
  }

  double addValue({
    required Map<NutrientKey, double> consumed,
    required Map<NutrientKey, NutrientValue> scaledNutrients,
  }) {
    if (key != null) {
      final rowKey = key;
      if (rowKey != null) {
        return scaledNutrients[rowKey]?.amount ?? 0;
      }
    }
    final addComputer = _add;
    if (addComputer != null) {
      return addComputer(
        consumed: consumed,
        scaledNutrients: scaledNutrients,
      );
    }
    return 0;
  }
}
