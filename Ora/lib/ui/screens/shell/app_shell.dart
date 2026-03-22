import 'package:flutter/material.dart';

import '../appearance/appearance_screen.dart';
import '../diet/diet_screen.dart';
import '../programs/programs_screen.dart';
import '../profile/profile_hub_screen.dart';
import 'app_shell_controller.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/services/session_service.dart';
import '../session/session_screen.dart';
import '../../widgets/orb/ora_orb.dart';
import '../../widgets/session_active_banner.dart';

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
        const ProfileHubScreen(),
      ];

  @override
  Widget build(BuildContext context) {
    final tabs = _tabs;
    final maxIndex = tabs.length - 1;
    if (_index > maxIndex) {
      _index = maxIndex;
    }
    final navHeight =
        _BottomNavBar.navHeight + MediaQuery.of(context).padding.bottom;
    return Scaffold(
      body: Stack(
        children: [
          Padding(
            padding: EdgeInsets.only(bottom: navHeight),
            child: IndexedStack(
              index: _index,
              children: tabs,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ValueListenableBuilder<bool>(
              valueListenable: AppShellController.instance.orbHidden,
              builder: (context, orbHidden, _) {
                return _BottomNavBar(
                  currentIndex: _index,
                  appearanceEnabled: _appearanceEnabled,
                  orbHidden: orbHidden,
                  onTap: (value) => setState(() => _index = value),
                );
              },
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: navHeight,
            child: SessionActiveBanner(onTap: _resumeActiveSession),
          ),
          const OraOrb(),
        ],
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
    AppShellController.instance.appearanceEnabled
        .addListener(_handleAppearanceToggle);
  }

  @override
  void dispose() {
    AppShellController.instance.tabIndex.removeListener(_handleTabChange);
    AppShellController.instance.appearanceEnabled
        .removeListener(_handleAppearanceToggle);
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
      MaterialPageRoute(
          builder: (_) => SessionScreen(contextData: contextData)),
    );
  }
}

class _BottomNavBar extends StatelessWidget {
  const _BottomNavBar({
    required this.currentIndex,
    required this.appearanceEnabled,
    required this.orbHidden,
    required this.onTap,
  });

  final int currentIndex;
  final bool appearanceEnabled;
  final bool orbHidden;
  final ValueChanged<int> onTap;

  static const double navHeight = 68;
  static const double _orbSlotWidth = 128;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final items = _buildItems();

    Widget buildBar(List<_NavItemData> leading,
        [List<_NavItemData>? trailing]) {
      return Container(
        height: navHeight + bottomPadding,
        padding: EdgeInsets.fromLTRB(
          10,
          8,
          10,
          bottomPadding > 0 ? bottomPadding + 6 : 14,
        ),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              scheme.surface.withValues(alpha: 0.86),
              scheme.surfaceContainerHighest.withValues(alpha: 0.74),
              scheme.surface.withValues(alpha: 0.82),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          border: Border(
            top: BorderSide(color: scheme.outline.withValues(alpha: 0.22)),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.30),
              blurRadius: 28,
              offset: const Offset(0, -10),
            ),
          ],
        ),
        child: Row(
          children: [
            for (final item in leading)
              _NavItem(
                icon: item.icon,
                label: item.label,
                selected: currentIndex == item.index,
                onTap: () => onTap(item.index),
              ),
            if (trailing != null) const SizedBox(width: _orbSlotWidth),
            if (trailing != null)
              for (final item in trailing)
                _NavItem(
                  icon: item.icon,
                  label: item.label,
                  selected: currentIndex == item.index,
                  onTap: () => onTap(item.index),
                ),
          ],
        ),
      );
    }

    if (orbHidden) {
      return buildBar(items);
    }

    final left = items.take(2).toList();
    final right = items.skip(2).toList();
    return ClipPath(
      clipper: const _BottomNavClipper(),
      child: buildBar(left, right),
    );
  }

  List<_NavItemData> _buildItems() {
    final items = <_NavItemData>[
      _NavItemData(index: 0, icon: Icons.fitness_center, label: 'Training'),
      _NavItemData(index: 1, icon: Icons.restaurant, label: 'Diet'),
    ];
    if (appearanceEnabled) {
      items.add(_NavItemData(
          index: 2, icon: Icons.face_retouching_natural, label: 'Appearance'));
      items.add(_NavItemData(index: 3, icon: Icons.person, label: 'Profile'));
    } else {
      items.add(_NavItemData(index: 2, icon: Icons.person, label: 'Profile'));
    }
    return items;
  }
}

class _NavItemData {
  const _NavItemData({
    required this.index,
    required this.icon,
    required this.label,
  });

  final int index;
  final IconData icon;
  final String label;
}

class _NavItem extends StatelessWidget {
  const _NavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final foreground =
        selected ? scheme.onPrimary : scheme.onSurface.withValues(alpha: 0.74);
    final background = selected
        ? scheme.primary.withValues(alpha: 0.96)
        : scheme.surface.withValues(alpha: 0.10);
    final borderColor = selected
        ? scheme.primary.withValues(alpha: 0.42)
        : scheme.outline.withValues(alpha: 0.10);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: borderColor),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: foreground, size: 18),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.fade,
                  softWrap: false,
                  style: TextStyle(
                    fontSize: 10,
                    height: 1,
                    color: foreground,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomNavClipper extends CustomClipper<Path> {
  const _BottomNavClipper();

  @override
  Path getClip(Size size) {
    const notchRadius = 48.0;
    const notchDepth = 22.0;
    final mid = size.width / 2;
    final path = Path();
    path.moveTo(0, 0);
    path.lineTo(mid - notchRadius, 0);
    path.quadraticBezierTo(
        mid - notchRadius * 0.6, 0, mid - notchRadius * 0.6, notchDepth * 0.5);
    path.arcToPoint(
      Offset(mid + notchRadius * 0.6, notchDepth * 0.5),
      radius: const Radius.circular(notchRadius),
      clockwise: false,
    );
    path.quadraticBezierTo(mid + notchRadius * 0.6, 0, mid + notchRadius, 0);
    path.lineTo(size.width, 0);
    path.lineTo(size.width, size.height);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(covariant CustomClipper<Path> oldClipper) => false;
}
