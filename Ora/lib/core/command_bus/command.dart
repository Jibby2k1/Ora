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

class LogSetEntry extends Command {
  const LogSetEntry({
    required this.sessionExerciseId,
    required this.weightUnit,
    required this.weightMode,
    this.weight,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
    this.restSecActual,
  });

  final int sessionExerciseId;
  final String weightUnit;
  final String weightMode;
  final double? weight;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
  final int? restSecActual;

  @override
  String get type => 'LogSetEntry';
}

class UpdateSetEntry extends Command {
  const UpdateSetEntry({
    required this.id,
    this.weight,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
    this.restSecActual,
  });

  final int id;
  final double? weight;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
  final int? restSecActual;

  @override
  String get type => 'UpdateSetEntry';
}

class DeleteSetEntry extends Command {
  const DeleteSetEntry(this.id);

  final int id;

  @override
  String get type => 'DeleteSetEntry';
}

class InsertSetEntry extends Command {
  const InsertSetEntry({
    required this.id,
    required this.sessionExerciseId,
    required this.setIndex,
    required this.setRole,
    required this.weightUnit,
    required this.weightMode,
    required this.createdAt,
    this.weight,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
    this.flagWarmup = false,
    this.flagPartials = false,
    this.isAmrap = false,
    this.restSecActual,
  });

  final int id;
  final int sessionExerciseId;
  final int setIndex;
  final String setRole;
  final String weightUnit;
  final String weightMode;
  final String createdAt;
  final double? weight;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
  final bool flagWarmup;
  final bool flagPartials;
  final bool isAmrap;
  final int? restSecActual;

  @override
  String get type => 'InsertSetEntry';
}
