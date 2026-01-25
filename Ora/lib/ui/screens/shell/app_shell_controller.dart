import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/input/input_router.dart';

class AppShellController {
  AppShellController._();

  static final AppShellController instance = AppShellController._();

  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> appearanceEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> appearanceProfileEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> appearanceProfileSex = ValueNotifier<String>('neutral');
  final ValueNotifier<bool> orbHidden = ValueNotifier<bool>(false);
  final ValueNotifier<bool> activeSession = ValueNotifier<bool>(false);
  final ValueNotifier<bool> activeSessionIndicatorHidden = ValueNotifier<bool>(false);
  final ValueNotifier<int> restRemainingSeconds = ValueNotifier<int>(0);
  final ValueNotifier<bool> restAlertActive = ValueNotifier<bool>(false);
  final ValueNotifier<InputDispatch?> pendingInput = ValueNotifier<InputDispatch?>(null);
  Timer? _restTicker;
  DateTime? _restStartedAt;
  DateTime? _restEndsAt;
  int _restDurationSeconds = 0;
  int? _restSetId;
  int? _restExerciseId;

  int? get restActiveSetId => _restSetId;
  int? get restActiveExerciseId => _restExerciseId;
  DateTime? get restStartedAt => _restStartedAt;
  int get restDurationSeconds => _restDurationSeconds;

  void selectTab(int index) {
    if (tabIndex.value == index) return;
    tabIndex.value = index;
  }

  void setAppearanceEnabled(bool value) {
    if (appearanceEnabled.value == value) return;
    appearanceEnabled.value = value;
  }

  void setAppearanceProfileEnabled(bool value) {
    if (appearanceProfileEnabled.value == value) return;
    appearanceProfileEnabled.value = value;
  }

  void setAppearanceProfileSex(String value) {
    if (appearanceProfileSex.value == value) return;
    appearanceProfileSex.value = value;
  }

  void setOrbHidden(bool value) {
    if (orbHidden.value == value) return;
    orbHidden.value = value;
  }

  void setActiveSession(bool value) {
    if (activeSession.value == value) return;
    activeSession.value = value;
    if (!value) {
      activeSessionIndicatorHidden.value = false;
      _clearRestState();
    }
  }

  void setActiveSessionIndicatorHidden(bool value) {
    if (activeSessionIndicatorHidden.value == value) return;
    activeSessionIndicatorHidden.value = value;
  }

  void setRestRemainingSeconds(int value) {
    if (restRemainingSeconds.value == value) return;
    restRemainingSeconds.value = value;
  }

  void setRestAlertActive(bool value) {
    if (restAlertActive.value == value) return;
    restAlertActive.value = value;
  }

  void startRestTimer({
    required int seconds,
    int? setId,
    int? exerciseId,
  }) {
    if (seconds <= 0) return;
    _restSetId = setId;
    _restExerciseId = exerciseId;
    _restDurationSeconds = seconds;
    _restStartedAt = DateTime.now();
    _restEndsAt = _restStartedAt!.add(Duration(seconds: seconds));
    restAlertActive.value = false;
    _tickRest();
    _restTicker ??= Timer.periodic(const Duration(seconds: 1), (_) => _tickRest());
  }

  void completeRestTimer({bool showAlert = false}) {
    _restSetId = null;
    _restExerciseId = null;
    _restStartedAt = null;
    _restEndsAt = null;
    _restDurationSeconds = 0;
    restRemainingSeconds.value = 0;
    restAlertActive.value = showAlert;
    _stopRestTicker();
  }

  void _tickRest() {
    if (_restEndsAt == null) {
      restRemainingSeconds.value = 0;
      _stopRestTicker();
      return;
    }
    final remaining = _restEndsAt!.difference(DateTime.now()).inSeconds;
    if (remaining <= 0) {
      _restSetId = null;
      _restExerciseId = null;
      _restStartedAt = null;
      _restEndsAt = null;
      _restDurationSeconds = 0;
      restRemainingSeconds.value = 0;
      restAlertActive.value = true;
      _stopRestTicker();
      return;
    }
    restRemainingSeconds.value = remaining;
  }

  void _clearRestState() {
    _restSetId = null;
    _restExerciseId = null;
    _restStartedAt = null;
    _restEndsAt = null;
    _restDurationSeconds = 0;
    restRemainingSeconds.value = 0;
    restAlertActive.value = false;
    _stopRestTicker();
  }

  void _stopRestTicker() {
    _restTicker?.cancel();
    _restTicker = null;
  }

  void setPendingInput(InputDispatch? input) {
    pendingInput.value = input;
  }

  void clearPendingInput() {
    pendingInput.value = null;
  }
}
