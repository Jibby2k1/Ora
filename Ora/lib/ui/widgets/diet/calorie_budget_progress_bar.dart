import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/models/diet_diary_models.dart';

class CalorieBudgetProgressBar extends StatelessWidget {
  const CalorieBudgetProgressBar({
    super.key,
    required this.summary,
    required this.baseColor,
    required this.baseTrackColor,
    required this.extensionColor,
    required this.extensionTrackColor,
    required this.overflowColor,
  });

  final DietSummaryComputedData summary;
  final Color baseColor;
  final Color baseTrackColor;
  final Color extensionColor;
  final Color extensionTrackColor;
  final Color overflowColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalWidth = constraints.maxWidth;
        final extensionVisualRatio = summary.burnedExtensionVisualRatio;
        final hasExtension = extensionVisualRatio > 0;
        final baseWidth = hasExtension
            ? totalWidth / (1 + extensionVisualRatio)
            : totalWidth;
        final extensionWidth = math.max(0.0, totalWidth - baseWidth);
        final baseFillWidth = baseWidth * summary.baseCalorieProgress;
        final extensionFillWidth =
            extensionWidth * summary.consumedBeyondBaseProgress;
        final overflowWidth = summary.isOverAdjustedGoal
            ? math.max(
                6.0,
                math.min(
                  totalWidth * 0.18,
                  totalWidth * summary.consumedBeyondAdjustedProgress,
                ),
              )
            : 0.0;

        return Container(
          height: 9,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(999),
            border: summary.isOverAdjustedGoal
                ? Border.all(color: overflowColor.withValues(alpha: 0.45))
                : null,
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(999),
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  top: 0,
                  bottom: 0,
                  width: baseWidth,
                  child: Container(color: baseTrackColor),
                ),
                if (extensionWidth > 0)
                  Positioned(
                    left: baseWidth,
                    top: 0,
                    bottom: 0,
                    width: extensionWidth,
                    child: Container(color: extensionTrackColor),
                  ),
                Align(
                  alignment: Alignment.centerLeft,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 360),
                    curve: Curves.easeOutCubic,
                    width: baseFillWidth,
                    color: baseColor,
                  ),
                ),
                if (extensionWidth > 0)
                  Positioned(
                    left: baseWidth,
                    top: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      width: extensionFillWidth,
                      color: extensionColor,
                    ),
                  ),
                if (overflowWidth > 0)
                  Positioned(
                    right: 0,
                    top: 0,
                    bottom: 0,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 360),
                      curve: Curves.easeOutCubic,
                      width: overflowWidth,
                      color: overflowColor.withValues(alpha: 0.66),
                    ),
                  ),
                if (hasExtension && extensionWidth > 0)
                  Positioned(
                    left: baseWidth - 0.5,
                    top: 0,
                    bottom: 0,
                    child: Container(
                      width: 1,
                      color: theme.colorScheme.onSurface.withValues(alpha: 0.18),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }
}
