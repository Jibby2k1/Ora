import 'package:flutter/material.dart';

import 'steps_progress_ring.dart';

class StepsMiniStatChip extends StatelessWidget {
  const StepsMiniStatChip({
    super.key,
    required this.icon,
    required this.value,
    required this.unit,
    required this.label,
    required this.progress,
  });

  final IconData icon;
  final String value;
  final String unit;
  final String label;
  final double progress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: scheme.outline.withValues(alpha: 0.1),
        ),
      ),
      child: Row(
        children: [
          StepsProgressRing(
            progress: progress.clamp(0.0, 1.0),
            size: 28,
            strokeWidth: 3.2,
            child: Icon(
              icon,
              size: 15,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '$value $unit',
                    maxLines: 1,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                const SizedBox(height: 1),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: scheme.onSurface.withValues(alpha: 0.62),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
