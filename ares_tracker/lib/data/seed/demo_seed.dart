import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../repositories/exercise_repo.dart';
import '../repositories/program_repo.dart';

class DemoSeedResult {
  DemoSeedResult({required this.programId, required this.programDayId});

  final int programId;
  final int programDayId;
}

class DemoSeed {
  DemoSeed(this._db);

  final AppDatabase _db;

  Future<DemoSeedResult> ensureDemoProgram() async {
    final db = await _db.database;
    final programCount = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM program;')) ?? 0;
    if (programCount > 0) {
      final row = (await db.query('program', columns: ['id'], limit: 1)).first;
      final day = (await db.query('program_day', columns: ['id', 'program_id'], limit: 1)).first;
      return DemoSeedResult(programId: day['program_id'] as int, programDayId: day['id'] as int);
    }

    final programRepo = ProgramRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);
    final programId = await programRepo.createProgram(name: 'Demo Program');
    final dayId = await programRepo.addProgramDay(programId: programId, dayIndex: 0, dayName: 'Day 1');

    final exercises = await exerciseRepo.getAll();
    final picks = exercises.take(3).toList();

    for (var i = 0; i < picks.length; i++) {
      final exerciseId = picks[i]['id'] as int;
      final dayExerciseId = await programRepo.addProgramDayExercise(
        programDayId: dayId,
        exerciseId: exerciseId,
        orderIndex: i,
      );

      await programRepo.addSetPlanBlock(
        programDayExerciseId: dayExerciseId,
        orderIndex: 0,
        role: 'WARMUP',
        setCount: 2,
        repsMin: 8,
        repsMax: 10,
        restSecMin: 60,
        restSecMax: 90,
        loadRuleType: 'NONE',
        amrapLastSet: false,
      );
      await programRepo.addSetPlanBlock(
        programDayExerciseId: dayExerciseId,
        orderIndex: 1,
        role: 'TOP',
        setCount: 1,
        repsMin: 6,
        repsMax: 8,
        restSecMin: 120,
        restSecMax: 180,
        loadRuleType: 'NONE',
        amrapLastSet: true,
      );
      await programRepo.addSetPlanBlock(
        programDayExerciseId: dayExerciseId,
        orderIndex: 2,
        role: 'BACKOFF',
        setCount: 2,
        repsMin: 8,
        repsMax: 12,
        restSecMin: 90,
        restSecMax: 120,
        loadRuleType: 'DROP_PERCENT_FROM_TOP',
        loadRuleMin: 10,
        loadRuleMax: 15,
        amrapLastSet: false,
      );
    }

    return DemoSeedResult(programId: programId, programDayId: dayId);
  }
}
