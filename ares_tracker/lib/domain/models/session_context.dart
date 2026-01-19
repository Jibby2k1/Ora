import 'session_exercise_info.dart';

class SessionContext {
  SessionContext({required this.sessionId, required this.exercises});

  final int sessionId;
  final List<SessionExerciseInfo> exercises;
}
