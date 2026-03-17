import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/food_detail_computed.dart';

class MacroDonutChart extends StatelessWidget {
  const MacroDonutChart({
    super.key,
    required this.segments,
    required this.totalCalories,
    required this.proteinColor,
    required this.carbsColor,
    required this.fatColor,
  });

  final List<MacroPieSegment> segments;
  final double totalCalories;
  final Color proteinColor;
  final Color carbsColor;
  final Color fatColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final values = <double>[
      for (final segment in segments)
        segment.calories.isFinite && segment.calories > 0
            ? segment.calories
            : 0,
    ];
    final colors = <Color>[proteinColor, carbsColor, fatColor];
    final total = values.fold<double>(0, (sum, value) => sum + value);

    return SizedBox(
      height: 168,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final chartSize =
              math.min(constraints.maxWidth, constraints.maxHeight);
          return Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: chartSize,
                height: chartSize,
                child: CustomPaint(
                  painter: _MacroDonutPainter(
                    values: values,
                    colors: colors,
                    trackColor:
                        theme.colorScheme.onSurface.withValues(alpha: 0.16),
                    hasData: total > 0,
                  ),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalCalories.toStringAsFixed(0),
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                      height: 1,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    'kcal',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (total <= 0) ...[
                    const SizedBox(height: 4),
                    Text(
                      'No macro split',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _MacroDonutPainter extends CustomPainter {
  const _MacroDonutPainter({
    required this.values,
    required this.colors,
    required this.trackColor,
    required this.hasData,
  });

  final List<double> values;
  final List<Color> colors;
  final Color trackColor;
  final bool hasData;

  @override
  void paint(Canvas canvas, Size size) {
    final strokeWidth = 24.0;
    final radius = (math.min(size.width, size.height) - strokeWidth) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..color = trackColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.butt;

    canvas.drawArc(rect, 0, math.pi * 2, false, trackPaint);

    if (!hasData) return;

    final total = values.fold<double>(0, (sum, value) => sum + value);
    if (total <= 0) return;

    var startAngle = -math.pi / 2;
    for (var i = 0; i < values.length; i++) {
      final value = values[i];
      if (value <= 0) continue;
      final sweep = (value / total) * math.pi * 2;
      final paint = Paint()
        ..color = colors[i % colors.length]
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      startAngle += sweep;
    }
  }

  @override
  bool shouldRepaint(covariant _MacroDonutPainter oldDelegate) {
    return oldDelegate.values != values ||
        oldDelegate.colors != colors ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.hasData != hasData;
  }
}
