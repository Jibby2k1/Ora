import '../services/set_plan_service.dart';

class SessionExerciseInfo {
  SessionExerciseInfo({
    required this.sessionExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    required this.weightModeDefault,
    required this.planBlocks,
  });

  final int sessionExerciseId;
  final int exerciseId;
  final String exerciseName;
  final String weightModeDefault;
  final List<SetPlanBlock> planBlocks;
}
