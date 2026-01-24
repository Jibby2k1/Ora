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
            hiddenListenable: AppShellController.instance.activeSessionIndicatorHidden,
            restListenable: AppShellController.instance.restRemainingSeconds,
            restAlertListenable: AppShellController.instance.restAlertActive,
            onTap: _resumeActiveSession,
            onHide: () => AppShellController.instance.setActiveSessionIndicatorHidden(true),
            onShow: () => AppShellController.instance.setActiveSessionIndicatorHidden(false),
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

class _ActiveSessionIndicator extends StatefulWidget {
  const _ActiveSessionIndicator({
    required this.activeListenable,
    required this.hiddenListenable,
    required this.restListenable,
    required this.restAlertListenable,
    required this.onTap,
    required this.onHide,
    required this.onShow,
  });

  final ValueListenable<bool> activeListenable;
  final ValueListenable<bool> hiddenListenable;
  final ValueListenable<int> restListenable;
  final ValueListenable<bool> restAlertListenable;
  final VoidCallback onTap;
  final VoidCallback onHide;
  final VoidCallback onShow;

  @override
  State<_ActiveSessionIndicator> createState() => _ActiveSessionIndicatorState();
}

class _ActiveSessionIndicatorState extends State<_ActiveSessionIndicator>
    with SingleTickerProviderStateMixin {
  static const double _dockThreshold = 42;
  Offset _dragOffset = Offset.zero;
  late final AnimationController _flashController;

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

  void _handleDragUpdate(DragUpdateDetails details) {
    final delta = details.delta;
    final next = Offset(
      (_dragOffset.dx + delta.dx).clamp(-120, 0),
      (_dragOffset.dy + delta.dy).clamp(0, 120),
    );
    setState(() => _dragOffset = next);
  }

  void _handleDragEnd(DragEndDetails details) {
    if (-_dragOffset.dx + _dragOffset.dy >= _dockThreshold) {
      setState(() => _dragOffset = Offset.zero);
      widget.onHide();
    } else {
      setState(() => _dragOffset = Offset.zero);
    }
  }

  String _formatRest(int seconds) {
    final minutes = seconds ~/ 60;
    final secs = seconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${secs.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Align(
        alignment: Alignment.bottomLeft,
        child: ValueListenableBuilder<bool>(
          valueListenable: widget.activeListenable,
          builder: (context, active, child) {
            if (!active) {
              return const SizedBox.shrink();
            }
            return ValueListenableBuilder<bool>(
              valueListenable: widget.hiddenListenable,
              builder: (context, hidden, child) {
                final padding = hidden
                    ? const EdgeInsets.only(left: 10, bottom: 52)
                    : const EdgeInsets.only(left: 12, bottom: 56);
                return Padding(
                  padding: padding,
                  child: hidden
                      ? GestureDetector(
                          onTap: widget.onShow,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: const Color(0xFF2F78FF).withOpacity(0.92),
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.25),
                                  blurRadius: 12,
                                  offset: const Offset(0, 6),
                                ),
                              ],
                            ),
                            child: const Text(
                              'S',
                              style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                            ),
                          ),
                        )
                      : GestureDetector(
                          onPanUpdate: _handleDragUpdate,
                          onPanEnd: _handleDragEnd,
                          child: Transform.translate(
                            offset: _dragOffset,
                            child: AnimatedBuilder(
                              animation: _flashController,
                              builder: (context, child) {
                                final flash = _flashController.value;
                                final restAlert = widget.restAlertListenable.value;
                                final baseColor = Theme.of(context).colorScheme.surface.withOpacity(0.82);
                                final flashColor = Color.lerp(
                                  baseColor,
                                  const Color(0xFF2F78FF),
                                  restAlert ? (0.25 + flash * 0.6) : 0,
                                );
                                return Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: flashColor,
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
                                      GestureDetector(
                                        onTap: widget.onTap,
                                        child: const Icon(Icons.north_east, size: 16),
                                      ),
                                      const SizedBox(width: 6),
                                      GestureDetector(
                                        onTap: widget.onHide,
                                        child: const Icon(Icons.expand_more, size: 18),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}
