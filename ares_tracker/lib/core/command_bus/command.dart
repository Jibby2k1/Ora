abstract class Command {
  const Command();
  String get type;
}

class SwitchExercise extends Command {
  const SwitchExercise(this.exerciseId);
  final int exerciseId;
  @override
  String get type => 'SwitchExercise';
}

class LogSet extends Command {
  const LogSet({
    required this.exerciseId,
    required this.reps,
    this.weight,
    this.partials,
    this.rpe,
    this.rir,
  });

  final int? exerciseId;
  final int reps;
  final double? weight;
  final int? partials;
  final double? rpe;
  final double? rir;

  @override
  String get type => 'LogSet';
}

class StartRestTimer extends Command {
  const StartRestTimer(this.seconds);
  final int? seconds;
  @override
  String get type => 'StartRestTimer';
}

class ShowStats extends Command {
  const ShowStats(this.exerciseId);
  final int? exerciseId;
  @override
  String get type => 'ShowStats';
}

class Undo extends Command {
  const Undo();
  @override
  String get type => 'Undo';
}

class Redo extends Command {
  const Redo();
  @override
  String get type => 'Redo';
}

class FinishWorkout extends Command {
  const FinishWorkout();
  @override
  String get type => 'FinishWorkout';
}

class CommandResult {
  CommandResult({
    required this.dbWrites,
    required this.uiEvents,
    required this.inverse,
  });

  final List<String> dbWrites;
  final List<String> uiEvents;
  final Command? inverse;
}
