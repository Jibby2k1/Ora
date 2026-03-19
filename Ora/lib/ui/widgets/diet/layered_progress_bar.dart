import 'package:flutter/material.dart';

class LayeredProgressBar extends StatelessWidget {
  const LayeredProgressBar({
    super.key,
    required this.baseProgress,
    required this.projectedProgress,
    required this.baseColor,
    required this.addedColor,
    this.backgroundColor,
    this.height = 8,
  });

  final double baseProgress;
  final double projectedProgress;
  final Color baseColor;
  final Color addedColor;
  final Color? backgroundColor;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trackColor =
        backgroundColor ?? theme.colorScheme.onSurface.withValues(alpha: 0.14);

    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _LayeredProgressBarPainter(
          baseProgress: baseProgress,
          projectedProgress: projectedProgress,
          baseColor: baseColor,
          addedColor: addedColor,
          trackColor: trackColor,
        ),
      ),
    );
  }
}

class _LayeredProgressBarPainter extends CustomPainter {
  const _LayeredProgressBarPainter({
    required this.baseProgress,
    required this.projectedProgress,
    required this.baseColor,
    required this.addedColor,
    required this.trackColor,
  });

  final double baseProgress;
  final double projectedProgress;
  final Color baseColor;
  final Color addedColor;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final base = baseProgress.clamp(0.0, 1.0).toDouble();
    final projected = projectedProgress.clamp(0.0, 1.0).toDouble();
    final start = base <= projected ? base : projected;
    final end = base <= projected ? projected : base;

    final radius = Radius.circular(size.height / 2);
    final trackRect = Offset.zero & size;
    final trackRRect = RRect.fromRectAndRadius(trackRect, radius);
    canvas.drawRRect(trackRRect, Paint()..color = trackColor);

    if (base > 0) {
      final baseRect = Rect.fromLTWH(0, 0, size.width * base, size.height);
      canvas.drawRRect(
        _segmentRRect(baseRect, radius,
            touchesLeft: true, touchesRight: base >= 1),
        Paint()..color = baseColor,
      );
    }

    if (end > start) {
      final overlayRect = Rect.fromLTWH(
          size.width * start, 0, size.width * (end - start), size.height);
      canvas.drawRRect(
        _segmentRRect(
          overlayRect,
          radius,
          touchesLeft: start <= 0,
          touchesRight: end >= 1,
        ),
        Paint()..color = addedColor,
      );
    }

    if (base > 0 && base < 1 && end > start) {
      final markerX = size.width * base;
      final markerPaint = Paint()
        ..color = Colors.white.withValues(alpha: 0.45)
        ..strokeWidth = 1.2;
      canvas.drawLine(
        Offset(markerX, 0),
        Offset(markerX, size.height),
        markerPaint,
      );
    }
  }

  RRect _segmentRRect(
    Rect rect,
    Radius radius, {
    required bool touchesLeft,
    required bool touchesRight,
  }) {
    return RRect.fromRectAndCorners(
      rect,
      topLeft: touchesLeft ? radius : Radius.zero,
      bottomLeft: touchesLeft ? radius : Radius.zero,
      topRight: touchesRight ? radius : Radius.zero,
      bottomRight: touchesRight ? radius : Radius.zero,
    );
  }

  @override
  bool shouldRepaint(covariant _LayeredProgressBarPainter oldDelegate) {
    return oldDelegate.baseProgress != baseProgress ||
        oldDelegate.projectedProgress != projectedProgress ||
        oldDelegate.baseColor != baseColor ||
        oldDelegate.addedColor != addedColor ||
        oldDelegate.trackColor != trackColor;
  }
}
