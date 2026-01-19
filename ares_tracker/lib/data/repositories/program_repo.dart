import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class ProgramRepo {
  ProgramRepo(this._db);

  final AppDatabase _db;

  Future<int> createProgram({required String name, String? notes}) async {
    final db = await _db.database;
    return db.insert('program', {
      'name': name,
      'notes': notes,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> addProgramDay({
    required int programId,
    required int dayIndex,
    required String dayName,
  }) async {
    final db = await _db.database;
    return db.insert('program_day', {
      'program_id': programId,
      'day_index': dayIndex,
      'day_name': dayName,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> addProgramDayExercise({
    required int programDayId,
    required int exerciseId,
    required int orderIndex,
    String? notes,
  }) async {
    final db = await _db.database;
    return db.insert('program_day_exercise', {
      'program_day_id': programDayId,
      'exercise_id': exerciseId,
      'order_index': orderIndex,
      'notes': notes,
    });
  }

  Future<int> addSetPlanBlock({
    required int programDayExerciseId,
    required int orderIndex,
    required String role,
    required int setCount,
    int? repsMin,
    int? repsMax,
    int? restSecMin,
    int? restSecMax,
    double? targetRpeMin,
    double? targetRpeMax,
    double? targetRirMin,
    double? targetRirMax,
    required String loadRuleType,
    double? loadRuleMin,
    double? loadRuleMax,
    required bool amrapLastSet,
    int? partialsTargetMin,
    int? partialsTargetMax,
    String? notes,
  }) async {
    final db = await _db.database;
    return db.insert('set_plan_block', {
      'program_day_exercise_id': programDayExerciseId,
      'order_index': orderIndex,
      'role': role,
      'set_count': setCount,
      'reps_min': repsMin,
      'reps_max': repsMax,
      'rest_sec_min': restSecMin,
      'rest_sec_max': restSecMax,
      'target_rpe_min': targetRpeMin,
      'target_rpe_max': targetRpeMax,
      'target_rir_min': targetRirMin,
      'target_rir_max': targetRirMax,
      'load_rule_type': loadRuleType,
      'load_rule_min': loadRuleMin,
      'load_rule_max': loadRuleMax,
      'amrap_last_set': amrapLastSet ? 1 : 0,
      'partials_target_min': partialsTargetMin,
      'partials_target_max': partialsTargetMax,
      'notes': notes,
    });
  }

  Future<List<Map<String, Object?>>> getSetPlanBlocks(int programDayExerciseId) async {
    final db = await _db.database;
    return db.query(
      'set_plan_block',
      where: 'program_day_exercise_id = ?',
      whereArgs: [programDayExerciseId],
      orderBy: 'order_index ASC',
    );
  }
}
