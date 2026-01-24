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
      restRemainingSeconds.value = 0;
      restAlertActive.value = false;
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

  void setPendingInput(InputDispatch? input) {
    pendingInput.value = input;
  }

  void clearPendingInput() {
    pendingInput.value = null;
  }
}
