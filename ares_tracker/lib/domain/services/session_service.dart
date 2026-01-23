import '../../data/db/db.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/program_repo.dart';
import '../../data/repositories/workout_repo.dart';
import '../models/session_context.dart';
import '../models/session_exercise_info.dart';
import 'set_plan_service.dart';

class SessionService {
  SessionService(this._db);

  final AppDatabase _db;

  Future<SessionContext> startSessionForProgramDay({
    required int programId,
    required int programDayId,
  }) async {
    final programRepo = ProgramRepo(_db);
    final workoutRepo = WorkoutRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);

    final dayExercises = await programRepo.getProgramDayExerciseDetails(programDayId);
    final sessionId = await workoutRepo.startSession(programId: programId, programDayId: programDayId);

    final exerciseInfos = <SessionExerciseInfo>[];
    for (final dayExercise in dayExercises) {
      final programDayExerciseId = dayExercise['program_day_exercise_id'] as int;
      final exerciseId = dayExercise['exercise_id'] as int;
      final orderIndex = dayExercise['order_index'] as int;

      final sessionExerciseId = await workoutRepo.addSessionExercise(
        workoutSessionId: sessionId,
        exerciseId: exerciseId,
        orderIndex: orderIndex,
      );

      final exerciseRow = await exerciseRepo.getById(exerciseId);
      final exerciseName = exerciseRow?['canonical_name'] as String? ?? 'Exercise';
      final weightModeDefault = exerciseRow?['weight_mode_default'] as String? ?? 'TOTAL';

      final blocks = await programRepo.getSetPlanBlocks(programDayExerciseId);
      final planBlocks = blocks.map((row) => SetPlanBlock.fromRow(row)).toList();

      exerciseInfos.add(SessionExerciseInfo(
        sessionExerciseId: sessionExerciseId,
        exerciseId: exerciseId,
        exerciseName: exerciseName,
        weightModeDefault: weightModeDefault,
        planBlocks: planBlocks,
      ));
    }

    return SessionContext(
      sessionId: sessionId,
      exercises: exerciseInfos,
      programId: programId,
      programDayId: programDayId,
    );
  }
}
