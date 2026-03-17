import 'package:flutter/material.dart';

import '../../../domain/models/diet_diary_models.dart';
import '../glass/glass_card.dart';
import 'diary_entry_row.dart';

class MealGroupSection extends StatelessWidget {
  const MealGroupSection({
    super.key,
    required this.group,
    required this.collapsed,
    required this.onAdd,
    required this.onEdit,
    required this.onToggleCollapsed,
    required this.onEditOrCopy,
    required this.onDelete,
    required this.onDropEntry,
  });

  final DietDiaryMealGroup group;
  final bool collapsed;
  final VoidCallback onAdd;
  final ValueChanged<DietDiaryEntryItem> onEdit;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<DietDiaryEntryItem> onEditOrCopy;
  final ValueChanged<DietDiaryEntryItem> onDelete;
  final ValueChanged<DietDiaryEntryItem> onDropEntry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final caloriesLine = '${group.totals.calories.round()} kcal';
    final macroLine =
        'Protein: ${group.totals.proteinG.toStringAsFixed(0)} g • '
        'Carbs: ${group.totals.carbsG.toStringAsFixed(0)} g • '
        'Fats: ${group.totals.fatG.toStringAsFixed(0)} g';

    return DragTarget<DietDiaryEntryItem>(
      onWillAcceptWithDetails: (details) {
        return details.data.mealSlot != group.mealSlot;
      },
      onAcceptWithDetails: (details) => onDropEntry(details.data),
      builder: (context, candidateData, _) {
        final hasActiveDrop = candidateData.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: hasActiveDrop
                  ? theme.colorScheme.primary.withValues(alpha: 0.5)
                  : Colors.transparent,
              width: 1.4,
            ),
            boxShadow: hasActiveDrop
                ? [
                    BoxShadow(
                      color: theme.colorScheme.primary.withValues(alpha: 0.2),
                      blurRadius: 16,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Material(
                      color: theme.colorScheme.primary.withValues(alpha: 0.16),
                      borderRadius: BorderRadius.circular(10),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: onAdd,
                        child: SizedBox(
                          width: 34,
                          height: 34,
                          child: Icon(
                            Icons.add,
                            size: 20,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: InkWell(
                        onTap: onToggleCollapsed,
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Expanded(
                                    child: Text(
                                      group.mealSlot,
                                      style:
                                          theme.textTheme.titleMedium?.copyWith(
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Text(
                                    caloriesLine,
                                    style: theme.textTheme.labelLarge?.copyWith(
                                      fontWeight: FontWeight.w700,
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.82),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 1),
                              SizedBox(
                                width: double.infinity,
                                child: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    macroLine,
                                    maxLines: 1,
                                    style:
                                        theme.textTheme.labelMedium?.copyWith(
                                      color: theme.colorScheme.onSurface
                                          .withValues(alpha: 0.68),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: onToggleCollapsed,
                      icon: Icon(
                        collapsed ? Icons.expand_more : Icons.expand_less,
                      ),
                    ),
                  ],
                ),
                if (!collapsed) ...[
                  const SizedBox(height: 6),
                  if (group.entries.isEmpty)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color:
                            theme.colorScheme.surface.withValues(alpha: 0.16),
                        border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.restaurant_outlined,
                            size: 16,
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.55),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'Add your first item',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurface
                                  .withValues(alpha: 0.66),
                            ),
                          ),
                        ],
                      ),
                    )
                  else
                    Column(
                      children: [
                        for (var index = 0;
                            index < group.entries.length;
                            index++) ...[
                          DiaryEntryRow(
                            item: group.entries[index],
                            onTapEdit: () => onEdit(group.entries[index]),
                            onEditOrCopy: () =>
                                onEditOrCopy(group.entries[index]),
                            onDelete: () => onDelete(group.entries[index]),
                          ),
                          if (index < group.entries.length - 1)
                            const SizedBox(height: 6),
                        ],
                      ],
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}
