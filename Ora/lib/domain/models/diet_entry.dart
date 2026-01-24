class DietEntry {
  DietEntry({
    required this.id,
    required this.mealName,
    required this.loggedAt,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sodiumMg,
    this.micros,
    this.notes,
  });

  final int id;
  final String mealName;
  final DateTime loggedAt;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sodiumMg;
  final Map<String, double>? micros;
  final String? notes;
}
