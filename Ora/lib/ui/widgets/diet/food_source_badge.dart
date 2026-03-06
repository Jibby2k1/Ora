import 'package:flutter/material.dart';

import '../../../domain/models/food_models.dart';

class FoodSourceBadge extends StatelessWidget {
  const FoodSourceBadge({
    super.key,
    required this.source,
  });

  final FoodSource source;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = switch (source) {
      FoodSource.usdaFdc => theme.colorScheme.primary,
      FoodSource.openFoodFacts => theme.colorScheme.secondary,
      FoodSource.nutritionix => theme.colorScheme.tertiary,
      FoodSource.custom => theme.colorScheme.onSurface,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        source.label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}
