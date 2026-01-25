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
          child: Stack(
            children: [
              BottomNavigationBar(
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
              Positioned(
                left: 12,
                bottom: 6,
                child: _ActiveSessionIndicator(
                  activeListenable: AppShellController.instance.activeSession,
                  hiddenListenable: AppShellController.instance.activeSessionIndicatorHidden,
                  restListenable: AppShellController.instance.restRemainingSeconds,
                  restAlertListenable: AppShellController.instance.restAlertActive,
                  onTap: _resumeActiveSession,
                  onHide: () => AppShellController.instance.setActiveSessionIndicatorHidden(true),
                  onShow: () => AppShellController.instance.setActiveSessionIndicatorHidden(false),
                  dockToNavBar: true,
                ),
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

class _ActiveSessionIndicator extends StatefulWidget {
  const _ActiveSessionIndicator({
    required this.activeListenable,
    required this.hiddenListenable,
    required this.restListenable,
    required this.restAlertListenable,
    required this.onTap,
    required this.onHide,
    required this.onShow,
    this.dockToNavBar = false,
  });

  final ValueListenable<bool> activeListenable;
  final ValueListenable<bool> hiddenListenable;
  final ValueListenable<int> restListenable;
  final ValueListenable<bool> restAlertListenable;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback onShow;
  final bool dockToNavBar;

  @override
  State<_ActiveSessionIndicator> createState() => _ActiveSessionIndicatorState();
}

class _ActiveSessionIndicatorState extends State<_ActiveSessionIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;
  static const double _tabHeight = 34;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    widget.restAlertListenable.addListener(_handleRestAlertChange);
    _handleRestAlertChange();
  }

  @override
  void dispose() {
    widget.restAlertListenable.removeListener(_handleRestAlertChange);
    _flashController.dispose();
    super.dispose();
  }

  void _handleRestAlertChange() {
    if (!mounted) return;
    final active = widget.restAlertListenable.value;
    if (active) {
      _flashController.repeat(reverse: true);
    } else {
      _flashController.stop();
      _flashController.value = 0;
    }
  }

  String _formatRest(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: widget.activeListenable,
      builder: (context, active, child) {
        if (!active) {
          return const SizedBox.shrink();
        }
        return ValueListenableBuilder<bool>(
          valueListenable: widget.hiddenListenable,
          builder: (context, hidden, child) {
            final scheme = Theme.of(context).colorScheme;
            if (hidden) {
              return Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: widget.onShow,
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(14),
                    topRight: Radius.circular(14),
                    bottomRight: Radius.circular(8),
                    bottomLeft: Radius.circular(4),
                  ),
                  child: Container(
                    height: _tabHeight,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    decoration: BoxDecoration(
                      color: scheme.primary.withOpacity(0.92),
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(14),
                        topRight: Radius.circular(14),
                        bottomRight: Radius.circular(8),
                        bottomLeft: Radius.circular(4),
                      ),
                      border: Border(
                        top: BorderSide(color: scheme.primary.withOpacity(0.95), width: 1.2),
                        left: BorderSide(color: scheme.primary.withOpacity(0.95), width: 1.2),
                        right: BorderSide(color: scheme.primary.withOpacity(0.95), width: 1.2),
                        bottom: BorderSide(color: scheme.primary.withOpacity(0.2), width: 0.6),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.25),
                          blurRadius: 12,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_arrow, size: 16, color: Colors.white),
                        SizedBox(width: 6),
                        Text(
                          'Session',
                          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                        ),
                        SizedBox(width: 4),
                        Icon(Icons.keyboard_arrow_right, size: 18, color: Colors.white70),
                      ],
                    ),
                  ),
                ),
              );
            }

            return Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: widget.onTap,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(16),
                  topRight: Radius.circular(16),
                  bottomRight: Radius.circular(16),
                  bottomLeft: Radius.circular(6),
                ),
                child: AnimatedBuilder(
                  animation: _flashController,
                  builder: (context, child) {
                    final flash = _flashController.value;
                    final restAlert = widget.restAlertListenable.value;
                    final baseColor = scheme.surface.withOpacity(0.94);
                    final flashColor = Color.lerp(
                      baseColor,
                      scheme.primary,
                      restAlert ? (0.25 + flash * 0.6) : 0,
                    );
                    return Container(
                      constraints: BoxConstraints(
                        minHeight: _tabHeight,
                        maxWidth: MediaQuery.of(context).size.width * 0.7,
                      ),
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: flashColor,
                        borderRadius: const BorderRadius.only(
                          topLeft: Radius.circular(16),
                          topRight: Radius.circular(16),
                          bottomRight: Radius.circular(16),
                          bottomLeft: Radius.circular(6),
                        ),
                        border: Border.all(color: scheme.outline.withOpacity(0.5)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.22),
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
                          const SizedBox(width: 10),
                          ValueListenableBuilder<int>(
                            valueListenable: widget.restListenable,
                            builder: (context, restSeconds, child) {
                              if (restSeconds <= 0) {
                                if (widget.restAlertListenable.value) {
                                  return const Text('Rest done');
                                }
                                return const SizedBox.shrink();
                              }
                              return Text('Rest ${_formatRest(restSeconds)}');
                            },
                          ),
                          const SizedBox(width: 8),
                          IconButton(
                            onPressed: widget.onHide,
                            icon: const Icon(Icons.expand_more, size: 18),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                            splashRadius: 16,
                            tooltip: 'Hide',
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
