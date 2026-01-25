import 'package:flutter/material.dart';

import '../screens/shell/app_shell_controller.dart';

class SessionActiveBanner extends StatefulWidget {
  const SessionActiveBanner({super.key, required this.onTap});

  final VoidCallback onTap;

  @override
  State<SessionActiveBanner> createState() => _SessionActiveBannerState();
}

class _SessionActiveBannerState extends State<SessionActiveBanner>
    with TickerProviderStateMixin {
  late final AnimationController _flashController;
  late final AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    );
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2600),
    )..repeat();
    AppShellController.instance.restAlertActive.addListener(_handleRestAlertChange);
    _handleRestAlertChange();
  }

  @override
  void dispose() {
    AppShellController.instance.restAlertActive.removeListener(_handleRestAlertChange);
    _flashController.dispose();
    _waveController.dispose();
    super.dispose();
  }

  void _handleRestAlertChange() {
    if (!mounted) return;
    final active = AppShellController.instance.restAlertActive.value;
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
      valueListenable: AppShellController.instance.activeSession,
      builder: (context, active, child) {
        if (!active) return const SizedBox.shrink();
        return GestureDetector(
          onTap: widget.onTap,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              return AnimatedBuilder(
                animation: Listenable.merge([_flashController, _waveController]),
                builder: (context, child) {
                  final flash = _flashController.value;
                  final restAlert = AppShellController.instance.restAlertActive.value;
                  final baseColor = Theme.of(context).colorScheme.primary.withOpacity(0.85);
                  final flashColor = Color.lerp(
                    baseColor,
                    Theme.of(context).colorScheme.primary.withOpacity(0.65),
                    restAlert ? (0.25 + flash * 0.35) : 0,
                  );
                  final waveOffset = (width * 2) * _waveController.value - width;
                  return Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      color: flashColor,
                      borderRadius: BorderRadius.zero,
                    ),
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Positioned.fill(
                          child: ClipRRect(
                            borderRadius: BorderRadius.zero,
                            child: Transform.translate(
                              offset: Offset(waveOffset, 0),
                              child: Container(
                                width: width * 2,
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    begin: Alignment.centerLeft,
                                    end: Alignment.centerRight,
                                    colors: [
                                      Colors.white.withOpacity(0.06),
                                      Colors.white.withOpacity(0.06),
                                      Colors.white.withOpacity(0.18),
                                      Colors.white.withOpacity(0.06),
                                      Colors.white.withOpacity(0.06),
                                    ],
                                    stops: const [0.0, 0.38, 0.5, 0.62, 1.0],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                          child: Row(
                            children: [
                              const Text('Current Session'),
                              const Spacer(),
                              ValueListenableBuilder<int>(
                                valueListenable: AppShellController.instance.restRemainingSeconds,
                                builder: (context, restSeconds, child) {
                                  if (restSeconds <= 0) {
                                    if (AppShellController.instance.restAlertActive.value) {
                                      return const Text('Rest done');
                                    }
                                    return const SizedBox.shrink();
                                  }
                                  return Text('Rest ${_formatRest(restSeconds)}');
                                },
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
        );
      },
    );
  }
}
