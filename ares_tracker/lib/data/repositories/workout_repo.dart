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
}
