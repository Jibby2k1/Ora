enum WorkoutSetTag {
  normal,
  warmup,
  failure,
  dropset;

  static WorkoutSetTag fromStorage(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'warmup':
        return WorkoutSetTag.warmup;
      case 'failure':
        return WorkoutSetTag.failure;
      case 'dropset':
        return WorkoutSetTag.dropset;
      default:
        return WorkoutSetTag.normal;
    }
  }

  String get storageValue {
    switch (this) {
      case WorkoutSetTag.normal:
        return 'normal';
      case WorkoutSetTag.warmup:
        return 'warmup';
      case WorkoutSetTag.failure:
        return 'failure';
      case WorkoutSetTag.dropset:
        return 'dropset';
    }
  }

  String get shortLabel {
    switch (this) {
      case WorkoutSetTag.normal:
        return '';
      case WorkoutSetTag.warmup:
        return 'W';
      case WorkoutSetTag.failure:
        return 'F';
      case WorkoutSetTag.dropset:
        return 'D';
    }
  }

  String get displayLabel {
    switch (this) {
      case WorkoutSetTag.normal:
        return 'Normal';
      case WorkoutSetTag.warmup:
        return 'Warm-up';
      case WorkoutSetTag.failure:
        return 'Failure';
      case WorkoutSetTag.dropset:
        return 'Dropset';
    }
  }
}
