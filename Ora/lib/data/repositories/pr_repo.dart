import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class PrRepo {
  PrRepo(this._db);

  final AppDatabase _db;

  Future<List<Map<String, Object?>>> getSetsForExercise(int exerciseId) async {
    final db = await _db.database;
    return db.rawQuery('''
SELECT se.*
FROM set_entry se
JOIN session_exercise sx ON sx.id = se.session_exercise_id
WHERE sx.exercise_id = ?
ORDER BY se.created_at ASC
''', [exerciseId]);
  }
}
