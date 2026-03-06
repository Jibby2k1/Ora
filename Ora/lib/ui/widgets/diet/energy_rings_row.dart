import 'package:flutter/material.dart';

class EnergyRingsRow extends StatelessWidget {
  const EnergyRingsRow({
    super.key,
    required this.consumed,
    required this.burned,
    required this.remaining,
    required this.goal,
  });

  final double consumed;
  final double burned;
  final double remaining;
  final double goal;

  @override
  Widget build(BuildContext context) {
    final safeGoal = goal <= 0 ? 1.0 : goal;
    final accent = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _EnergyRing(
            label: 'Consumed',
            value: consumed,
            progress: (consumed / safeGoal).clamp(0.0, 1.0),
            color: accent,
            icon: Icons.local_fire_department,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _EnergyRing(
            label: 'Burned',
            value: burned,
            progress: (burned / safeGoal).clamp(0.0, 1.0),
            color: secondary.withValues(alpha: 0.9),
            icon: Icons.directions_walk,
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: _EnergyRing(
            label: 'Remaining',
            value: remaining,
            progress:
                ((remaining <= 0 ? 0 : remaining) / safeGoal).clamp(0.0, 1.0),
            color: remaining < 0
                ? Theme.of(context).colorScheme.error
                : accent.withValues(alpha: 0.75),
            icon: Icons.track_changes,
          ),
        ),
      ],
    );
  }
}

class _EnergyRing extends StatelessWidget {
  const _EnergyRing({
    required this.label,
    required this.value,
    required this.progress,
    required this.color,
    required this.icon,
  });

  final String label;
  final double value;
  final double progress;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const ringSize = 74.0;
    return Column(
      children: [
        SizedBox(
          width: ringSize,
          height: ringSize,
          child: Stack(
            alignment: Alignment.center,
            children: [
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: CircularProgressIndicator(
                  value: 1,
                  strokeWidth: 6,
                  valueColor: AlwaysStoppedAnimation(
                    theme.colorScheme.onSurface.withValues(alpha: 0.18),
                  ),
                ),
              ),
              SizedBox(
                width: ringSize,
                height: ringSize,
                child: CircularProgressIndicator(
                  value: progress,
                  strokeWidth: 6,
                  valueColor: AlwaysStoppedAnimation(color),
                ),
              ),
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 12, color: color),
                  const SizedBox(height: 1),
                  Text(
                    value.round().toString(),
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'kcal',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.66),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 5),
        Text(
          label,
          style: theme.textTheme.labelMedium?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.8),
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
