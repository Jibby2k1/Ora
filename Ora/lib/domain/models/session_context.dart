import 'session_exercise_info.dart';

class SessionContext {
  SessionContext({
    required this.sessionId,
    required this.exercises,
    required this.programId,
    required this.programDayId,
  });

  final int sessionId;
  final List<SessionExerciseInfo> exercises;
  final int? programId;
  final int? programDayId;
}
