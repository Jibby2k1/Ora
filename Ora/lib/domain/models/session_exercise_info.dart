import '../services/set_plan_service.dart';

class SessionExerciseInfo {
  SessionExerciseInfo({
    required this.sessionExerciseId,
    required this.exerciseId,
    required this.exerciseName,
    required this.weightModeDefault,
    required this.planBlocks,
    this.supersetGroupId,
  });

  final int sessionExerciseId;
  final int exerciseId;
  final String exerciseName;
  final String weightModeDefault;
  final List<SetPlanBlock> planBlocks;
  final int? supersetGroupId;

  SessionExerciseInfo copyWith({
    int? sessionExerciseId,
    int? exerciseId,
    String? exerciseName,
    String? weightModeDefault,
    List<SetPlanBlock>? planBlocks,
    int? supersetGroupId,
    bool clearSupersetGroupId = false,
  }) {
    return SessionExerciseInfo(
      sessionExerciseId: sessionExerciseId ?? this.sessionExerciseId,
      exerciseId: exerciseId ?? this.exerciseId,
      exerciseName: exerciseName ?? this.exerciseName,
      weightModeDefault: weightModeDefault ?? this.weightModeDefault,
      planBlocks: planBlocks ?? this.planBlocks,
      supersetGroupId: clearSupersetGroupId
          ? null
          : (supersetGroupId ?? this.supersetGroupId),
    );
  }
}
