import 'package:flutter/material.dart';

import '../../../domain/models/diet_diary_models.dart';

class MacroBreakdownCard extends StatelessWidget {
  const MacroBreakdownCard({
    super.key,
    required this.totals,
    required this.targets,
  });

  final DietMacroTotals totals;
  final DietMacroTargets targets;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _ProgressBarRow(
          label: 'Calories',
          icon: Icons.local_fire_department,
          consumed: totals.calories,
          goal: targets.calories,
          unit: 'kcal',
          color: Colors.white,
          consumedDecimals: 0,
          goalDecimals: 0,
        ),
        const SizedBox(height: 12),
        _ProgressBarRow(
          label: 'Protein',
          icon: Icons.fitness_center,
          consumed: totals.proteinG,
          goal: targets.proteinG,
          unit: 'g',
          color: Colors.green,
          consumedDecimals: 1,
          goalDecimals: 0,
        ),
        const SizedBox(height: 12),
        _ProgressBarRow(
          label: 'Carbs',
          icon: Icons.grain,
          consumed: totals.carbsG,
          goal: targets.carbsG,
          unit: 'g',
          color: Colors.blue,
          consumedDecimals: 1,
          goalDecimals: 0,
        ),
        const SizedBox(height: 12),
        _ProgressBarRow(
          label: 'Fat',
          icon: Icons.water_drop,
          consumed: totals.fatG,
          goal: targets.fatG,
          unit: 'g',
          color: Colors.red,
          consumedDecimals: 1,
          goalDecimals: 0,
        ),
      ],
    );
  }
}

class _ProgressBarRow extends StatelessWidget {
  const _ProgressBarRow({
    required this.label,
    required this.icon,
    required this.consumed,
    required this.goal,
    required this.unit,
    required this.color,
    required this.consumedDecimals,
    required this.goalDecimals,
  });

  final String label;
  final IconData icon;
  final double consumed;
  final double goal;
  final String unit;
  final Color color;
  final int consumedDecimals;
  final int goalDecimals;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final safeGoal = goal <= 0 ? 1.0 : goal;
    final progress = (consumed / safeGoal).clamp(0.0, 1.0).toDouble();
    final percent = (progress * 100).round();
    final consumedText = consumed.toStringAsFixed(consumedDecimals);
    final goalText = goal.toStringAsFixed(goalDecimals);
    final details = '$consumedText / $goalText $unit ($percent%)';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(
              icon,
              size: 16,
              color: color.withValues(alpha: 0.9),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              details,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        TweenAnimationBuilder<double>(
          tween: Tween<double>(end: progress),
          duration: const Duration(milliseconds: 360),
          curve: Curves.easeOutCubic,
          builder: (context, animatedProgress, _) {
            return ClipRRect(
              borderRadius: BorderRadius.circular(999),
              child: LinearProgressIndicator(
                value: animatedProgress,
                minHeight: 8,
                backgroundColor:
                    theme.colorScheme.onSurface.withValues(alpha: 0.16),
                color: color,
              ),
            );
          },
        ),
      ],
    );
  }
}
