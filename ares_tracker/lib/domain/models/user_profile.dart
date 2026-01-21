class UserProfile {
  UserProfile({
    required this.id,
    this.displayName,
    this.age,
    this.heightCm,
    this.weightKg,
    this.notes,
    required this.createdAt,
    required this.updatedAt,
  });

  final int id;
  final String? displayName;
  final int? age;
  final double? heightCm;
  final double? weightKg;
  final String? notes;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserProfile copyWith({
    String? displayName,
    int? age,
    double? heightCm,
    double? weightKg,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserProfile(
      id: id,
      displayName: displayName ?? this.displayName,
      age: age ?? this.age,
      heightCm: heightCm ?? this.heightCm,
      weightKg: weightKg ?? this.weightKg,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
