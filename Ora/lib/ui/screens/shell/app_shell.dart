import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';

import '../appearance/appearance_screen.dart';
import '../diet/diet_screen.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../programs/programs_screen.dart';
import '../settings/settings_screen.dart';
import 'app_shell_controller.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/services/session_service.dart';
import '../session/session_screen.dart';
import '../../widgets/orb/ora_orb.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _index = 0;
  bool _appearanceEnabled = true;
  late final SettingsRepo _settingsRepo;
  late final WorkoutRepo _workoutRepo;
  late final SessionService _sessionService;

  List<Widget> get _tabs => [
        const ProgramsScreen(),
        const DietScreen(),
        if (_appearanceEnabled) const AppearanceScreen(),
        const LeaderboardScreen(),
        const SettingsScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final maxIndex = tabs.length - 1;
    if (_index > maxIndex) {
      _index = maxIndex;
    }
    return Scaffold(
      body: Stack(
        children: [
          IndexedStack(
            index: _index,
            children: tabs,
          ),
          _ActiveSessionIndicator(
            activeListenable: AppShellController.instance.activeSession,
            onTap: _resumeActiveSession,
          ),
          const OraOrb(),
        ],
      ),
      bottomNavigationBar: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        child: Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface.withOpacity(0.82),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.35),
                blurRadius: 24,
                offset: const Offset(0, -8),
              ),
            ],
          ),
          child: BottomNavigationBar(
            currentIndex: _index,
            onTap: (value) => setState(() => _index = value),
            items: [
              const BottomNavigationBarItem(
                icon: Icon(Icons.fitness_center),
                label: 'Training',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.restaurant),
                label: 'Diet',
              ),
              if (_appearanceEnabled)
                const BottomNavigationBarItem(
                  icon: Icon(Icons.face_retouching_natural),
                  label: 'Appearance',
                ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.emoji_events),
                label: 'Leaderboard',
              ),
              const BottomNavigationBarItem(
                icon: Icon(Icons.settings),
                label: 'Settings',
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _workoutRepo = WorkoutRepo(AppDatabase.instance);
    _sessionService = SessionService(AppDatabase.instance);
    _loadAppearanceAccess();
    _loadActiveSession();
    AppShellController.instance.tabIndex.addListener(_handleTabChange);
    AppShellController.instance.appearanceEnabled.addListener(_handleAppearanceToggle);
  }

  @override
  void dispose() {
    AppShellController.instance.tabIndex.removeListener(_handleTabChange);
    AppShellController.instance.appearanceEnabled.removeListener(_handleAppearanceToggle);
    super.dispose();
  }

  void _handleTabChange() {
    if (!mounted) return;
    setState(() {
      _index = AppShellController.instance.tabIndex.value;
    });
  }

  void _handleAppearanceToggle() {
    if (!mounted) return;
    setState(() {
      final wasEnabled = _appearanceEnabled;
      final isEnabled = AppShellController.instance.appearanceEnabled.value;
      _appearanceEnabled = isEnabled;
      if (wasEnabled && !isEnabled && _index >= 2) {
        _index = _index - 1;
      } else if (!wasEnabled && isEnabled && _index >= 2) {
        _index = _index + 1;
      }
    });
  }

  Future<void> _loadAppearanceAccess() async {
    final access = await _settingsRepo.getAppearanceAccessEnabled();
    if (!mounted) return;
    final enabled = access ?? true;
    setState(() {
      _appearanceEnabled = enabled;
    });
    AppShellController.instance.setAppearanceEnabled(enabled);
  }

  Future<void> _loadActiveSession() async {
    final hasActive = await _workoutRepo.hasActiveSession();
    if (!mounted) return;
    AppShellController.instance.setActiveSession(hasActive);
  }

  Future<void> _resumeActiveSession() async {
    final contextData = await _sessionService.resumeActiveSession();
    if (contextData == null || !mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
  }
}

class _ActiveSessionIndicator extends StatelessWidget {
  const _ActiveSessionIndicator({required this.activeListenable, required this.onTap});

  final ValueListenable<bool> activeListenable;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: const Alignment(-0.8, 1),
        child: ValueListenableBuilder<bool>(
          valueListenable: activeListenable,
          builder: (context, active, child) {
            return AnimatedOpacity(
              opacity: active ? 1 : 0,
              duration: const Duration(milliseconds: 180),
              child: IgnorePointer(
                ignoring: !active,
                child: GestureDetector(
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 72),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.surface.withOpacity(0.82),
                        borderRadius: BorderRadius.circular(999),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.25),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              shape: BoxShape.circle,
                              color: Color(0xFF37D67A),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text('Session active'),
                          const SizedBox(width: 6),
                          const Icon(Icons.north_east, size: 16),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
