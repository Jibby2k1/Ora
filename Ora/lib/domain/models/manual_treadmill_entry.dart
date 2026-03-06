import 'dart:convert';

class ManualTreadmillEntry {
  const ManualTreadmillEntry({
    required this.steps,
    required this.inclineDegrees,
    required this.speedMph,
    this.durationMinutes,
    required this.createdAt,
    required this.estimatedCalories,
  });

  final int steps;
  final double inclineDegrees;
  final double speedMph;
  final int? durationMinutes;
  final DateTime createdAt;
  final double estimatedCalories;

  ManualTreadmillEntry copyWith({
    int? steps,
    double? inclineDegrees,
    double? speedMph,
    int? durationMinutes,
    DateTime? createdAt,
    double? estimatedCalories,
  }) {
    return ManualTreadmillEntry(
      steps: steps ?? this.steps,
      inclineDegrees: inclineDegrees ?? this.inclineDegrees,
      speedMph: speedMph ?? this.speedMph,
      durationMinutes: durationMinutes ?? this.durationMinutes,
      createdAt: createdAt ?? this.createdAt,
      estimatedCalories: estimatedCalories ?? this.estimatedCalories,
    );
  }

  Map<String, Object?> toJson() {
    return {
      'steps': steps,
      'inclineDegrees': inclineDegrees,
      'speedMph': speedMph,
      'durationMinutes': durationMinutes,
      'createdAt': createdAt.toIso8601String(),
      'estimatedCalories': estimatedCalories,
    };
  }

  String toJsonString() => jsonEncode(toJson());

  static String encodeList(List<ManualTreadmillEntry> entries) {
    return jsonEncode(entries.map((entry) => entry.toJson()).toList());
  }

  factory ManualTreadmillEntry.fromJson(Map<String, dynamic> json) {
    return ManualTreadmillEntry(
      steps: (json['steps'] as num?)?.toInt() ?? 0,
      inclineDegrees: (json['inclineDegrees'] as num?)?.toDouble() ?? 0,
      speedMph: (json['speedMph'] as num?)?.toDouble() ?? 0,
      durationMinutes: (json['durationMinutes'] as num?)?.toInt(),
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
      estimatedCalories: (json['estimatedCalories'] as num?)?.toDouble() ?? 0,
    );
  }

  factory ManualTreadmillEntry.fromJsonString(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('Invalid treadmill entry payload.');
    }
    return ManualTreadmillEntry.fromJson(decoded);
  }

  static List<ManualTreadmillEntry> decodeList(String raw) {
    final decoded = jsonDecode(raw);
    if (decoded is! List) {
      throw const FormatException('Invalid treadmill entry list payload.');
    }
    return decoded
        .whereType<Map>()
        .map(
          (item) => ManualTreadmillEntry.fromJson(
            Map<String, dynamic>.from(item),
          ),
        )
        .toList();
  }
}
