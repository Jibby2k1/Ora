import '../../data/db/db.dart';
import '../../data/repositories/diet_repo.dart';
import '../../data/repositories/profile_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../domain/models/user_profile.dart';

class WorkoutCalorieEstimate {
  const WorkoutCalorieEstimate({
    required this.workoutCalories,
    required this.bmrCalories,
    required this.durationMinutes,
    required this.setCount,
    required this.repCount,
    required this.bodyWeightKg,
    required this.usedDefaultWeight,
    required this.bmrAvailable,
  });

  final double workoutCalories;
  final double bmrCalories;
  final double durationMinutes;
  final int setCount;
  final double repCount;
  final double bodyWeightKg;
  final bool usedDefaultWeight;
  final bool bmrAvailable;

  double get totalCalories => workoutCalories + bmrCalories;
}

class CalorieAggregate {
  const CalorieAggregate({
    required this.caloriesAdded,
    required this.workoutCalories,
    required this.bmrCalories,
    required this.bmrAvailable,
  });

  final double caloriesAdded;
  final double workoutCalories;
  final double bmrCalories;
  final bool bmrAvailable;

  double get caloriesConsumed => workoutCalories + bmrCalories;
  double get netCalories => caloriesAdded - caloriesConsumed;
}

class CalorieService {
  CalorieService(this._db)
      : _dietRepo = DietRepo(_db),
        _profileRepo = ProfileRepo(_db),
        _settingsRepo = SettingsRepo(_db);

  final AppDatabase _db;
  final DietRepo _dietRepo;
  final ProfileRepo _profileRepo;
  final SettingsRepo _settingsRepo;

  static const double _secondsPerRep = 2.2;
  static const double _setSetupSeconds = 12.0;
  static const double _defaultRestSeconds = 75.0;
  static const double _liftingMet = 5.5;
  static const double _defaultBodyWeightKg = 75.0;

  Future<WorkoutCalorieEstimate> estimateWorkoutCaloriesForRange(DateTime start, DateTime end) async {
    final profile = await _profileRepo.getProfile();
    final sex = await _settingsRepo.getAppearanceProfileSex();
    final bodyWeight = profile?.weightKg ?? _defaultBodyWeightKg;
    final usedDefaultWeight = profile?.weightKg == null;
    final core = await _estimateWorkoutCore(start, end, bodyWeight);
    final bmr = _estimateBmr(profile, sex);
    final bmrCalories = bmr == null ? 0.0 : (bmr * (core.durationSeconds / 86400.0));
    return WorkoutCalorieEstimate(
      workoutCalories: core.workoutCalories,
      bmrCalories: bmrCalories,
      durationMinutes: core.durationSeconds / 60.0,
      setCount: core.setCount,
      repCount: core.repCount,
      bodyWeightKg: bodyWeight,
      usedDefaultWeight: usedDefaultWeight,
      bmrAvailable: bmr != null,
    );
  }

  Future<CalorieAggregate> aggregateCaloriesForRange(DateTime start, DateTime end) async {
    final profile = await _profileRepo.getProfile();
    final sex = await _settingsRepo.getAppearanceProfileSex();
    final bodyWeight = profile?.weightKg ?? _defaultBodyWeightKg;
    final core = await _estimateWorkoutCore(start, end, bodyWeight);
    final dietSummary = await _dietRepo.getSummaryForRange(start, end);
    final bmr = _estimateBmr(profile, sex);
    final rangeSeconds = end.difference(start).inSeconds;
    final bmrCalories = bmr == null ? 0.0 : (bmr * (rangeSeconds / 86400.0));
    return CalorieAggregate(
      caloriesAdded: dietSummary.calories ?? 0.0,
      workoutCalories: core.workoutCalories,
      bmrCalories: bmrCalories,
      bmrAvailable: bmr != null,
    );
  }

  Future<_WorkoutCore> _estimateWorkoutCore(DateTime start, DateTime end, double bodyWeightKg) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''
SELECT reps, partial_reps, rest_sec_actual
FROM set_entry
WHERE created_at >= ? AND created_at < ?
''', [start.toIso8601String(), end.toIso8601String()]);

    var durationSeconds = 0.0;
    var setCount = 0;
    var repCount = 0.0;

    for (final row in rows) {
      final reps = _asDouble(row['reps']) ?? 0.0;
      final partials = _asDouble(row['partial_reps']) ?? 0.0;
      final effectiveReps = reps + (partials * 0.5);
      final hasWork = effectiveReps > 0;
      if (hasWork) {
        setCount += 1;
        repCount += effectiveReps;
      }
      final restSeconds = _asDouble(row['rest_sec_actual']) ?? (hasWork ? _defaultRestSeconds : 0.0);
      final activeSeconds = hasWork ? (effectiveReps * _secondsPerRep) + _setSetupSeconds : 0.0;
      durationSeconds += activeSeconds + restSeconds;
    }

    final minutes = durationSeconds / 60.0;
    final workoutCalories = minutes <= 0
        ? 0.0
        : (_liftingMet * 3.5 * bodyWeightKg / 200.0 * minutes);

    return _WorkoutCore(
      workoutCalories: workoutCalories,
      durationSeconds: durationSeconds,
      setCount: setCount,
      repCount: repCount,
    );
  }

  double? _estimateBmr(UserProfile? profile, String sex) {
    if (profile == null) return null;
    final weight = profile.weightKg;
    final height = profile.heightCm;
    final age = profile.age;
    if (weight == null || height == null || age == null) return null;
    final base = (10 * weight) + (6.25 * height) - (5 * age);
    if (sex == 'male') return base + 5;
    if (sex == 'female') return base - 161;
    return base - 78; // Neutral = average of male/female constants.
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class _WorkoutCore {
  const _WorkoutCore({
    required this.workoutCalories,
    required this.durationSeconds,
    required this.setCount,
    required this.repCount,
  });

  final double workoutCalories;
  final double durationSeconds;
  final int setCount;
  final double repCount;
}
