import 'dart:math' as math;

import 'package:flutter/material.dart';

class StepsProgressRing extends StatelessWidget {
  const StepsProgressRing({
    super.key,
    required this.progress,
    required this.size,
    required this.strokeWidth,
    this.secondaryProgress = 0,
    this.child,
  });

  final double progress;
  final double size;
  final double strokeWidth;
  final double secondaryProgress;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          CustomPaint(
            size: Size.square(size),
            painter: _StepsProgressRingPainter(
              progress: progress.clamp(0.0, 1.0),
              secondaryProgress: secondaryProgress.clamp(0.0, 1.0),
              backgroundColor:
                  theme.colorScheme.onSurface.withValues(alpha: 0.14),
              progressColor: theme.colorScheme.primary,
              secondaryColor: Color.lerp(
                    theme.colorScheme.primary,
                    theme.colorScheme.surface,
                    0.32,
                  ) ??
                  theme.colorScheme.primary.withValues(alpha: 0.72),
              strokeWidth: strokeWidth,
            ),
          ),
          if (child != null) child!,
        ],
      ),
    );
  }
}

class _StepsProgressRingPainter extends CustomPainter {
  const _StepsProgressRingPainter({
    required this.progress,
    required this.secondaryProgress,
    required this.backgroundColor,
    required this.progressColor,
    required this.secondaryColor,
    required this.strokeWidth,
  });

  final double progress;
  final double secondaryProgress;
  final Color backgroundColor;
  final Color progressColor;
  final Color secondaryColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);
    final backgroundPaint = Paint()
      ..color = backgroundColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final progressPaint = Paint()
      ..color = progressColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    final secondaryPaint = Paint()
      ..color = secondaryColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, -math.pi / 2, math.pi * 2, false, backgroundPaint);
    if (progress > 0) {
      canvas.drawArc(
        rect,
        -math.pi / 2,
        math.pi * 2 * progress,
        false,
        progressPaint,
      );
    }
    if (secondaryProgress > 0) {
      canvas.drawArc(
        rect,
        (-math.pi / 2) + (math.pi * 2 * progress),
        math.pi * 2 * secondaryProgress,
        false,
        secondaryPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _StepsProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.secondaryProgress != secondaryProgress ||
        oldDelegate.backgroundColor != backgroundColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.secondaryColor != secondaryColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
