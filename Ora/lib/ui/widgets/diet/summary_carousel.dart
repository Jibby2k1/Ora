import 'package:flutter/material.dart';

import '../../../domain/models/diet_diary_models.dart';
import '../glass/glass_card.dart';
import 'macro_breakdown_card.dart';

class SummaryCarousel extends StatefulWidget {
  const SummaryCarousel({
    super.key,
    required this.viewModel,
    required this.includeBurnedCalories,
    required this.burnedCalories,
  });

  final DietDiaryViewModel viewModel;
  final bool includeBurnedCalories;
  final double burnedCalories;

  @override
  State<SummaryCarousel> createState() => _SummaryCarouselState();
}

class _SummaryCarouselState extends State<SummaryCarousel> {
  late final PageController _controller;
  int _pageIndex = 0;

  @override
  void initState() {
    super.initState();
    _controller = PageController();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.viewModel;
    final summary = DietSummaryComputedData.build(
      calorieGoal: vm.targets.calories,
      consumedCalories: vm.dailyTotals.calories,
      burnedCalories: widget.burnedCalories,
      includeBurnedCalories: widget.includeBurnedCalories,
    );
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: Column(
        children: [
          SizedBox(
            height: 236,
            child: PageView(
              controller: _controller,
              onPageChanged: (index) {
                setState(() {
                  _pageIndex = index;
                });
              },
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Center(
                    child: FractionallySizedBox(
                      widthFactor: 0.94,
                      child: MacroBreakdownCard(
                        totals: vm.dailyTotals,
                        targets: vm.targets,
                        summary: summary,
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: _HighlightedNutrientsPage(
                    nutrients: vm.highlightedNutrients,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(2, (index) {
              final active = _pageIndex == index;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                margin: const EdgeInsets.symmetric(horizontal: 4),
                width: active ? 16 : 6,
                height: 6,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(999),
                  color: active
                      ? Theme.of(context)
                          .colorScheme
                          .primary
                          .withValues(alpha: 0.9)
                      : Theme.of(context)
                          .colorScheme
                          .onSurface
                          .withValues(alpha: 0.22),
                ),
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _HighlightedNutrientsPage extends StatelessWidget {
  const _HighlightedNutrientsPage({
    required this.nutrients,
  });

  final List<DietHighlightedNutrient> nutrients;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = nutrients.take(8).toList(growable: false);
    final leftColumn = shown.take(4).toList(growable: false);
    final rightColumn = shown.skip(4).take(4).toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'HIGHLIGHTED NUTRIENTS',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 0.8,
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < leftColumn.length; i++) ...[
                      _NutrientProgressTile(item: leftColumn[i]),
                      if (i < leftColumn.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  children: [
                    for (var i = 0; i < rightColumn.length; i++) ...[
                      _NutrientProgressTile(item: rightColumn[i]),
                      if (i < rightColumn.length - 1) const SizedBox(height: 8),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NutrientProgressTile extends StatelessWidget {
  const _NutrientProgressTile({
    required this.item,
  });

  final DietHighlightedNutrient item;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final percentText =
        item.hasData ? '${(item.progress * 100).round()}%' : '--';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                item.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              percentText,
              style: theme.textTheme.titleMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(999),
          child: LinearProgressIndicator(
            value: item.progress,
            minHeight: 8,
            backgroundColor:
                theme.colorScheme.onSurface.withValues(alpha: 0.16),
            color: theme.colorScheme.primary,
          ),
        ),
      ],
    );
  }
}
