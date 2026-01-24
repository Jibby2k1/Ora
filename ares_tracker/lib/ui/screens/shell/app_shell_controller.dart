import 'package:flutter/foundation.dart';

class AppShellController {
  AppShellController._();

  static final AppShellController instance = AppShellController._();

  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);
  final ValueNotifier<bool> appearanceEnabled = ValueNotifier<bool>(true);
  final ValueNotifier<bool> appearanceProfileEnabled = ValueNotifier<bool>(false);
  final ValueNotifier<String> appearanceProfileSex = ValueNotifier<String>('neutral');

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
}
