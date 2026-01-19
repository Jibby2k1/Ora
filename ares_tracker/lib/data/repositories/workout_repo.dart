import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class WorkoutRepo {
  WorkoutRepo(this._db);

  final AppDatabase _db;

  Future<int> startSession({int? programId, int? programDayId}) async {
    final db = await _db.database;
    return db.insert('workout_session', {
      'program_id': programId,
      'program_day_id': programDayId,
      'started_at': DateTime.now().toIso8601String(),
      'ended_at': null,
      'notes': null,
    });
  }

  Future<void> endSession(int sessionId) async {
    final db = await _db.database;
    await db.update('workout_session', {
      'ended_at': DateTime.now().toIso8601String(),
    }, where: 'id = ?', whereArgs: [sessionId]);
  }

  Future<int> addSessionExercise({
    required int workoutSessionId,
    required int exerciseId,
    required int orderIndex,
  }) async {
    final db = await _db.database;
    return db.insert('session_exercise', {
      'workout_session_id': workoutSessionId,
      'exercise_id': exerciseId,
      'order_index': orderIndex,
    });
  }

  Future<int> addSetEntry({
    required int sessionExerciseId,
    required int setIndex,
    required String setRole,
    required String weightUnit,
    required String weightMode,
    double? weightValue,
    int? reps,
    int partialReps = 0,
    double? rpe,
    double? rir,
    bool flagWarmup = false,
    bool flagPartials = false,
    bool isAmrap = false,
    int? restSecActual,
  }) async {
    final db = await _db.database;
    return db.insert('set_entry', {
      'session_exercise_id': sessionExerciseId,
      'set_index': setIndex,
      'set_role': setRole,
      'weight_value': weightValue,
      'weight_unit': weightUnit,
      'weight_mode': weightMode,
      'reps': reps,
      'partial_reps': partialReps,
      'rpe': rpe,
      'rir': rir,
      'flag_warmup': flagWarmup ? 1 : 0,
      'flag_partials': flagPartials ? 1 : 0,
      'is_amrap': isAmrap ? 1 : 0,
      'rest_sec_actual': restSecActual,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, Object?>>> getSetsForSessionExercise(int sessionExerciseId) async {
    final db = await _db.database;
    return db.query(
      'set_entry',
      where: 'session_exercise_id = ?',
      whereArgs: [sessionExerciseId],
      orderBy: 'set_index ASC',
    );
  }

  Future<void> updateSetEntry({required int id, double? weightValue, int? reps, int? partialReps, double? rpe, double? rir}) async {
    final db = await _db.database;
    await db.update(
      'set_entry',
      {
        'weight_value': weightValue,
        'reps': reps,
        'partial_reps': partialReps ?? 0,
        'rpe': rpe,
        'rir': rir,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<Map<String, Object?>?> getSetEntryById(int id) async {
    final db = await _db.database;
    final rows = await db.query('set_entry', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> deleteSetEntry(int id) async {
    final db = await _db.database;
    await db.delete('set_entry', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> insertSetEntryWithId(Map<String, Object?> row) async {
    final db = await _db.database;
    await db.insert('set_entry', row, conflictAlgorithm: ConflictAlgorithm.replace);
  }

  Future<Map<String, Object?>?> getLatestSetForSessionExercise(int sessionExerciseId) async {
    final db = await _db.database;
    final rows = await db.query(
      'set_entry',
      where: 'session_exercise_id = ?',
      whereArgs: [sessionExerciseId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    return rows.isEmpty ? null : rows.first;
  }

  Future<double?> getLatestWeightForSessionExercise(int sessionExerciseId) async {
    final db = await _db.database;
    final rows = await db.query(
      'set_entry',
      columns: ['weight_value'],
      where: 'session_exercise_id = ? AND weight_value IS NOT NULL',
      whereArgs: [sessionExerciseId],
      orderBy: 'created_at DESC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['weight_value'] as double?;
  }

  Future<List<Map<String, Object?>>> getSessionExercises(int sessionId) async {
    final db = await _db.database;
    return db.rawQuery('''\nSELECT sx.id as session_exercise_id,\n       sx.exercise_id,\n       sx.order_index,\n       e.canonical_name,\n       e.weight_mode_default\nFROM session_exercise sx\nJOIN exercise e ON e.id = sx.exercise_id\nWHERE sx.workout_session_id = ?\nORDER BY sx.order_index ASC\n''', [sessionId]);
  }

  Future<int?> getLastCompletedDayIndex(int programId) async {
    final db = await _db.database;
    final rows = await db.rawQuery('''\nSELECT pd.day_index\nFROM workout_session ws\nJOIN program_day pd ON pd.id = ws.program_day_id\nWHERE ws.program_id = ? AND ws.ended_at IS NOT NULL\nORDER BY ws.started_at DESC\nLIMIT 1\n''', [programId]);
    if (rows.isEmpty) return null;
    return rows.first['day_index'] as int?;
  }
}
