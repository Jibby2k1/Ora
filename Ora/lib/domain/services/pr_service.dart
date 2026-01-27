class PrService {
  bool isDominancePr({
    required double? weight,
    required int? reps,
    required List<Map<String, Object?>> priorSets,
  }) {
    if (weight == null || reps == null) return false;
    for (final set in priorSets) {
      final w = set['weight_value'] as double?;
      final r = set['reps'] as int?;
      if (w == null || r == null) continue;
      if (w >= weight && r >= reps) {
        return false;
      }
    }
    return true;
  }
}
