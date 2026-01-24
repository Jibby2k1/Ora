class AppearanceEntry {
  AppearanceEntry({
    required this.id,
    required this.createdAt,
    this.measurements,
    this.notes,
  });

  final int id;
  final DateTime createdAt;
  final String? measurements;
  final String? notes;
}
