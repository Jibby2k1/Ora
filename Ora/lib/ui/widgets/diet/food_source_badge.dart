import 'package:flutter/material.dart';

import '../../../domain/models/food_models.dart';

class FoodSourceBadge extends StatelessWidget {
  const FoodSourceBadge({
    super.key,
    this.source,
    this.resultType,
    this.labelOverride,
  }) : assert(
          source != null || resultType != null || labelOverride != null,
          'source, resultType, or labelOverride must be provided.',
        );

  final FoodSource? source;
  final FoodResultType? resultType;
  final String? labelOverride;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final badgeLabel =
        labelOverride ?? resultType?.label ?? source?.label ?? 'SOURCE';

    final color = switch (resultType ?? _fallbackTypeFromSource(source)) {
      FoodResultType.generic => theme.colorScheme.primary,
      FoodResultType.branded => theme.colorScheme.secondary,
      FoodResultType.custom => theme.colorScheme.onSurface,
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(10),
        color: color.withValues(alpha: 0.16),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        badgeLabel.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  FoodResultType _fallbackTypeFromSource(FoodSource? source) {
    return switch (source) {
      FoodSource.custom => FoodResultType.custom,
      FoodSource.usdaFdc => FoodResultType.generic,
      FoodSource.openFoodFacts ||
      FoodSource.nutritionix =>
        FoodResultType.branded,
      null => FoodResultType.generic,
    };
  }
}
