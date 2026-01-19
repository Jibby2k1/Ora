import '../schema.dart';

List<String> migration0001() {
  return [
    createTableExercise,
    createTableExerciseAlias,
    createTableProgram,
    createTableProgramDay,
    createTableProgramDayExercise,
    createTableWorkoutSession,
    createTableSessionExercise,
    createTableSetEntry,
    ...createIndexes,
  ];
}
