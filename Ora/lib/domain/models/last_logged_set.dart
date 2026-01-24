class LastLoggedSet {
  LastLoggedSet({
    required this.exerciseName,
    required this.reps,
    required this.weight,
    required this.role,
    required this.isAmrap,
    required this.sessionSetCount,
  });

  final String exerciseName;
  final int reps;
  final double? weight;
  final String role;
  final bool isAmrap;
  final int sessionSetCount;
}
