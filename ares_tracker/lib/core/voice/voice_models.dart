class NluCommand {
  NluCommand({
    required this.type,
    this.exerciseRef,
    this.weight,
    this.weightUnit,
    this.reps,
    this.partials,
    this.rpe,
    this.rir,
    this.restSeconds,
  });

  final String type;
  final String? exerciseRef;
  final double? weight;
  final String? weightUnit;
  final int? reps;
  final int? partials;
  final double? rpe;
  final double? rir;
  final int? restSeconds;
}
