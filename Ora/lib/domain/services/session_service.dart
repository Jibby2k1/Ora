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

  Future<SessionContext> startFreeSession({int? programId}) async {
    final workoutRepo = WorkoutRepo(_db);
    final sessionId = await workoutRepo.startSession(programId: programId, programDayId: null);
    return SessionContext(
      sessionId: sessionId,
      exercises: const [],
      programId: programId,
      programDayId: null,
    );
  }

  Future<SessionContext?> resumeActiveSession() async {
    final workoutRepo = WorkoutRepo(_db);
    final programRepo = ProgramRepo(_db);
    final active = await workoutRepo.getActiveSession();
    if (active == null) return null;
    final sessionId = active['id'] as int;
    final programId = active['program_id'] as int?;
    final programDayId = active['program_day_id'] as int?;
    final sessionRows = await workoutRepo.getSessionExercises(sessionId);

    final exerciseInfos = <SessionExerciseInfo>[];
    for (final row in sessionRows) {
      final sessionExerciseId = row['session_exercise_id'] as int;
      final exerciseId = row['exercise_id'] as int;
      final exerciseName = row['canonical_name'] as String? ?? 'Exercise';
      final weightModeDefault = row['weight_mode_default'] as String? ?? 'TOTAL';
      final orderIndex = row['order_index'] as int;
      final planBlocks = <SetPlanBlock>[];
      if (programDayId != null) {
        final programDayExerciseId = await programRepo.getProgramDayExerciseIdByOrder(
          programDayId: programDayId,
          orderIndex: orderIndex,
        );
        if (programDayExerciseId != null) {
          final blocks = await programRepo.getSetPlanBlocks(programDayExerciseId);
          planBlocks.addAll(blocks.map((b) => SetPlanBlock.fromRow(b)));
        }
      }
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

  Future<SessionContext> loadSession(int sessionId) async {
    final workoutRepo = WorkoutRepo(_db);
    final programRepo = ProgramRepo(_db);
    final header = await workoutRepo.getSessionHeader(sessionId);
    final programId = header?['program_id'] as int?;
    final programDayId = header?['program_day_id'] as int?;
    final sessionRows = await workoutRepo.getSessionExercises(sessionId);

    final exerciseInfos = <SessionExerciseInfo>[];
    for (final row in sessionRows) {
      final sessionExerciseId = row['session_exercise_id'] as int;
      final exerciseId = row['exercise_id'] as int;
      final exerciseName = row['canonical_name'] as String? ?? 'Exercise';
      final weightModeDefault = row['weight_mode_default'] as String? ?? 'TOTAL';
      final orderIndex = row['order_index'] as int;
      final planBlocks = <SetPlanBlock>[];
      if (programDayId != null) {
        final programDayExerciseId = await programRepo.getProgramDayExerciseIdByOrder(
          programDayId: programDayId,
          orderIndex: orderIndex,
        );
        if (programDayExerciseId != null) {
          final blocks = await programRepo.getSetPlanBlocks(programDayExerciseId);
          planBlocks.addAll(blocks.map((b) => SetPlanBlock.fromRow(b)));
        }
      }
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
