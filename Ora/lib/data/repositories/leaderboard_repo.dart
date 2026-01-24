import '../db/db.dart';

class LeaderboardStats {
  LeaderboardStats({
    required this.trainingScore,
    required this.dietScore,
    required this.appearanceScore,
  });

  final double trainingScore;
  final double dietScore;
  final double appearanceScore;
}

class LeaderboardRepo {
  LeaderboardRepo(this._db);

  final AppDatabase _db;

  Future<LeaderboardStats> computeStats({int days = 30}) async {
    final db = await _db.database;
    final end = DateTime.now();
    final start = end.subtract(Duration(days: days));

    final rows = await db.rawQuery('''
SELECT
  COUNT(se.id) as set_count,
  SUM(CASE WHEN se.weight_value IS NOT NULL AND se.reps IS NOT NULL
           THEN se.weight_value * se.reps
           ELSE 0 END) as volume
FROM set_entry se
JOIN session_exercise sx ON sx.id = se.session_exercise_id
JOIN workout_session ws ON ws.id = sx.workout_session_id
WHERE ws.started_at >= ?
''', [start.toIso8601String()]);

    final row = rows.isEmpty ? null : rows.first;
    final setCount = _asDouble(row?['set_count']) ?? 0;
    final volume = _asDouble(row?['volume']) ?? 0;

    final mealRows = await db.rawQuery('''
SELECT COUNT(id) as meal_count
FROM diet_entry
WHERE logged_at >= ?
''', [start.toIso8601String()]);
    final mealCount = _asDouble(mealRows.isEmpty ? null : mealRows.first['meal_count']) ?? 0;

    final trainingScore = _scoreTraining(volume, setCount);
    final dietScore = mealCount;
    final appearanceScore = 0.0;

    return LeaderboardStats(
      trainingScore: trainingScore,
      dietScore: dietScore,
      appearanceScore: appearanceScore,
    );
  }

  double _scoreTraining(double volume, double setCount) {
    if (volume <= 0 && setCount <= 0) return 0;
    return (volume / 1000.0) + (setCount * 0.5);
  }

  double? _asDouble(Object? value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }
}
