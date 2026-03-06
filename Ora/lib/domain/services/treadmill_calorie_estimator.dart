import 'dart:math' as math;

class TreadmillCalorieEstimator {
  static const double defaultWeightKg = 80;
  static const double _defaultStrideMeters = 0.762;

  double estimateCalories({
    required int steps,
    required double inclineDegrees,
    required double speedMph,
    int? durationMinutes,
    double? weightKg,
  }) {
    if (steps <= 0) return 0;
    final safeSpeedMph = speedMph <= 0 ? 3.0 : speedMph;
    final safeDurationMinutes = durationMinutes != null && durationMinutes > 0
        ? durationMinutes.toDouble()
        : estimateDurationMinutes(steps: steps, speedMph: safeSpeedMph);
    final speedMetersPerMinute = safeSpeedMph * 26.8224;
    final grade = math.tan((inclineDegrees.clamp(0, 30)) * math.pi / 180.0);
    final vo2 = safeSpeedMph <= 5
        ? (0.1 * speedMetersPerMinute) +
            (1.8 * speedMetersPerMinute * grade) +
            3.5
        : (0.2 * speedMetersPerMinute) +
            (0.9 * speedMetersPerMinute * grade) +
            3.5;
    final met = (vo2 / 3.5).clamp(2.0, 18.0);
    final hours = safeDurationMinutes / 60.0;
    final calories = met * (weightKg ?? defaultWeightKg) * hours;
    return double.parse(calories.toStringAsFixed(1));
  }

  double estimateDistanceKm(int steps) {
    if (steps <= 0) return 0;
    final distanceMeters = steps * _defaultStrideMeters;
    return distanceMeters / 1000.0;
  }

  int estimateEquivalentFlatSteps({
    required int steps,
    required double inclineDegrees,
    required double speedMph,
  }) {
    if (steps <= 0) return 0;
    final inclineBoost = inclineDegrees.clamp(0, 30) / 6.4;
    final speedBoost = ((speedMph - 3.0) * 0.1).clamp(-0.15, 0.35);
    final multiplier = (1.0 + inclineBoost + speedBoost).clamp(1.0, 3.0);
    return math.max((steps * multiplier).round(), steps);
  }

  double estimateDurationMinutes({
    required int steps,
    required double speedMph,
  }) {
    if (steps <= 0) return 0;
    final safeSpeedMph = speedMph <= 0 ? 3.0 : speedMph;
    final distanceMiles = (steps * _defaultStrideMeters) / 1609.344;
    final hours = distanceMiles / safeSpeedMph;
    return math.max(hours * 60.0, 1.0);
  }

  int estimateSteps({
    required int durationMinutes,
    required double speedMph,
  }) {
    if (durationMinutes <= 0) return 0;
    final safeSpeedMph = speedMph <= 0 ? 3.0 : speedMph;
    final distanceMiles = safeSpeedMph * (durationMinutes / 60.0);
    final distanceMeters = distanceMiles * 1609.344;
    return math.max((distanceMeters / _defaultStrideMeters).round(), 1);
  }
}
