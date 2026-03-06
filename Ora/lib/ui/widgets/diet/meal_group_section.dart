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
    required this.onToggleCollapsed,
    required this.onEditOrCopy,
    required this.onDelete,
  });

  final DietDiaryMealGroup group;
  final bool collapsed;
  final VoidCallback onAdd;
  final VoidCallback onToggleCollapsed;
  final ValueChanged<DietDiaryEntryItem> onEditOrCopy;
  final ValueChanged<DietDiaryEntryItem> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final macroLine = '${group.totals.calories.round()} kcal • '
        'P ${group.totals.proteinG.toStringAsFixed(0)} • '
        'C ${group.totals.carbsG.toStringAsFixed(0)} • '
        'F ${group.totals.fatG.toStringAsFixed(0)}';

    return GlassCard(
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
                        Text(
                          group.mealSlot,
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          macroLine,
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.68),
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
                  color: theme.colorScheme.surface.withValues(alpha: 0.16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.18),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.restaurant_outlined,
                      size: 16,
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.55),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Add your first item',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.66),
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
                      onEditOrCopy: () => onEditOrCopy(group.entries[index]),
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
    );
  }
}
