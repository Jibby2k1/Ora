import 'package:flutter/foundation.dart';

class AppShellController {
  AppShellController._();

  static final AppShellController instance = AppShellController._();

  final ValueNotifier<int> tabIndex = ValueNotifier<int>(0);

  void selectTab(int index) {
    if (tabIndex.value == index) return;
    tabIndex.value = index;
  }
}
