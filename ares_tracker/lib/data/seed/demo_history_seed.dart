import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class DemoHistorySeed {
  DemoHistorySeed(this._db);

  final AppDatabase _db;

  Future<void> ensureHistorySeed() async {
    final db = await _db.database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM set_entry;')) ?? 0;
    if (count > 0) return;

    final exercises = await db.query('exercise', limit: 6, orderBy: 'id ASC');
    if (exercises.isEmpty) return;

    final now = DateTime.now();
    final sessionId = await db.insert('workout_session', {
      'program_id': null,
      'program_day_id': null,
      'started_at': now.toIso8601String(),
      'ended_at': now.toIso8601String(),
      'notes': 'demo history',
    });

    for (var i = 0; i < exercises.length; i++) {
      final ex = exercises[i];
      final exerciseId = ex['id'] as int;
      final weightMode = ex['weight_mode_default'] as String? ?? 'TOTAL';
      final sessionExerciseId = await db.insert('session_exercise', {
        'workout_session_id': sessionId,
        'exercise_id': exerciseId,
        'order_index': i,
      });

      for (var j = 0; j < 16; j++) {
        final created = now.subtract(Duration(days: j * 7));
        final weight = 95 + (i * 5) + (j * 2.5);
        final reps = 5 + (j % 5);
        await db.insert('set_entry', {
          'session_exercise_id': sessionExerciseId,
          'set_index': j + 1,
          'set_role': 'TOP',
          'weight_value': weight,
          'weight_unit': 'lb',
          'weight_mode': weightMode,
          'reps': reps,
          'partial_reps': 0,
          'rpe': null,
          'rir': null,
          'flag_warmup': 0,
          'flag_partials': 0,
          'is_amrap': 0,
          'rest_sec_actual': null,
          'created_at': created.toIso8601String(),
        });
      }
    }
  }
}
