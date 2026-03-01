import '../../data/repositories/workout_repo.dart';
import '../../domain/models/session_exercise_info.dart';
import '../../domain/services/set_plan_service.dart';
import 'command.dart';

class SessionCommandReducer {
  SessionCommandReducer({
    required this.workoutRepo,
    required this.sessionExerciseById,
  });

  final WorkoutRepo workoutRepo;
  final Map<int, SessionExerciseInfo> sessionExerciseById;

  Future<CommandResult> call(Command command) async {
    if (command is LogSetEntry) {
      final info = sessionExerciseById[command.sessionExerciseId];
      if (info == null) {
        return CommandResult(
            dbWrites: [],
            uiEvents: ['error:missing_session_exercise'],
            inverse: null);
      }
      final existing = await workoutRepo
          .getSetsForSessionExercise(command.sessionExerciseId);
      var maxIndex = 0;
      for (final row in existing) {
        final value = row['set_index'] as int?;
        if (value != null && value > maxIndex) {
          maxIndex = value;
        }
      }
      final setIndex = maxIndex + 1;
      final planResult = SetPlanService()
          .nextExpected(blocks: info.planBlocks, existingSets: existing);
      final role = planResult?.nextRole ?? 'TOP';
      final isAmrap = planResult?.isAmrap ?? false;

      final id = await workoutRepo.addSetEntry(
        sessionExerciseId: command.sessionExerciseId,
        setIndex: setIndex,
        setRole: role,
        weightValue: command.weight,
        weightUnit: command.weightUnit,
        weightMode: command.weightMode,
        reps: command.reps,
        partialReps: command.partials ?? 0,
        rpe: command.rpe,
        rir: command.rir,
        flagWarmup: role == 'WARMUP',
        flagPartials: (command.partials ?? 0) > 0,
        isAmrap: isAmrap,
        restSecActual: command.restSecActual,
      );

      final created = await workoutRepo.getSetEntryById(id);
      if (created == null) {
        return CommandResult(
            dbWrites: ['insert set_entry'], uiEvents: [], inverse: null);
      }
      return CommandResult(
        dbWrites: ['insert set_entry'],
        uiEvents: ['set_logged'],
        inverse: DeleteSetEntry(id),
      );
    }

    if (command is UpdateSetEntry) {
      final before = await workoutRepo.getSetEntryById(command.id);
      if (before == null) {
        return CommandResult(
            dbWrites: [], uiEvents: ['error:missing_set'], inverse: null);
      }
      final restActual =
          command.restSecActual ?? before['rest_sec_actual'] as int?;
      await workoutRepo.updateSetEntry(
        id: command.id,
        weightValue: command.weight ?? before['weight_value'] as double?,
        reps: command.reps ?? before['reps'] as int?,
        partialReps: command.partials ?? before['partial_reps'] as int?,
        rpe: command.rpe ?? before['rpe'] as double?,
        rir: command.rir ?? before['rir'] as double?,
        restSecActual: restActual,
      );
      final inverse = UpdateSetEntry(
        id: command.id,
        weight: before['weight_value'] as double?,
        reps: before['reps'] as int?,
        partials: before['partial_reps'] as int?,
        rpe: before['rpe'] as double?,
        rir: before['rir'] as double?,
        restSecActual: before['rest_sec_actual'] as int?,
      );
      return CommandResult(
        dbWrites: ['update set_entry'],
        uiEvents: ['set_updated'],
        inverse: inverse,
      );
    }

    if (command is DeleteSetEntry) {
      final before = await workoutRepo.getSetEntryById(command.id);
      if (before == null) {
        return CommandResult(
            dbWrites: [], uiEvents: ['error:missing_set'], inverse: null);
      }
      await workoutRepo.deleteSetEntry(command.id);
      final inverse = InsertSetEntry(
        id: before['id'] as int,
        sessionExerciseId: before['session_exercise_id'] as int,
        setIndex: before['set_index'] as int,
        setRole: before['set_role'] as String,
        weightUnit: before['weight_unit'] as String,
        weightMode: before['weight_mode'] as String,
        createdAt: before['created_at'] as String,
        weight: before['weight_value'] as double?,
        reps: before['reps'] as int?,
        partials: before['partial_reps'] as int?,
        rpe: before['rpe'] as double?,
        rir: before['rir'] as double?,
        flagWarmup: (before['flag_warmup'] as int? ?? 0) == 1,
        flagPartials: (before['flag_partials'] as int? ?? 0) == 1,
        isAmrap: (before['is_amrap'] as int? ?? 0) == 1,
        restSecActual: before['rest_sec_actual'] as int?,
      );
      return CommandResult(
        dbWrites: ['delete set_entry'],
        uiEvents: ['set_deleted'],
        inverse: inverse,
      );
    }

    if (command is InsertSetEntry) {
      await workoutRepo.insertSetEntryWithId({
        'id': command.id,
        'session_exercise_id': command.sessionExerciseId,
        'set_index': command.setIndex,
        'set_role': command.setRole,
        'weight_value': command.weight,
        'weight_unit': command.weightUnit,
        'weight_mode': command.weightMode,
        'reps': command.reps,
        'partial_reps': command.partials ?? 0,
        'rpe': command.rpe,
        'rir': command.rir,
        'flag_warmup': command.flagWarmup ? 1 : 0,
        'flag_partials': command.flagPartials ? 1 : 0,
        'is_amrap': command.isAmrap ? 1 : 0,
        'rest_sec_actual': command.restSecActual,
        'created_at': command.createdAt,
      });
      return CommandResult(
        dbWrites: ['insert set_entry'],
        uiEvents: ['set_restored'],
        inverse: DeleteSetEntry(command.id),
      );
    }

    return CommandResult(dbWrites: [], uiEvents: [], inverse: null);
  }
}
