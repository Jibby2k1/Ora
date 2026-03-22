import 'dart:ui';

import 'package:flutter/material.dart';

class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.radius = 18,
    this.borderOpacity = 0.2,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;
  final double borderOpacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: scheme.outline.withValues(alpha: borderOpacity + 0.08),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.24),
                blurRadius: 28,
                offset: const Offset(0, 14),
              ),
              BoxShadow(
                color: scheme.primary.withValues(alpha: 0.05),
                blurRadius: 18,
                offset: const Offset(-4, -4),
              ),
            ],
            gradient: LinearGradient(
              colors: [
                scheme.surface.withValues(alpha: 0.82),
                scheme.surfaceContainerHighest.withValues(alpha: 0.70),
                scheme.surface.withValues(alpha: 0.58),
              ],
              stops: const [0.0, 0.55, 1.0],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: child,
        ),
      ),
    );
  }
}
