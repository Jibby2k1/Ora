class ExerciseScienceInfo {
  const ExerciseScienceInfo({
    required this.exerciseId,
    required this.instructions,
    required this.avoid,
    required this.citations,
    required this.visualAssetPaths,
  });

  final int exerciseId;
  final List<String> instructions;
  final List<String> avoid;
  final List<String> citations;
  final List<String> visualAssetPaths;
}
