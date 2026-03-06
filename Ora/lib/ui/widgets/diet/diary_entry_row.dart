import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../domain/models/diet_diary_models.dart';

class DiaryEntryRow extends StatelessWidget {
  const DiaryEntryRow({
    super.key,
    required this.item,
    required this.onEditOrCopy,
    required this.onDelete,
  });

  final DietDiaryEntryItem item;
  final VoidCallback onEditOrCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeLabel = DateFormat.Hm().format(item.entry.loggedAt);

    return Dismissible(
      key: ValueKey(
          'diet-entry-${item.entry.id}-${item.entry.loggedAt.toIso8601String()}'),
      direction: DismissDirection.horizontal,
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          onEditOrCopy();
          return false;
        }
        return true;
      },
      onDismissed: (_) => onDelete(),
      background: _SwipeBackground(
        alignment: Alignment.centerLeft,
        color: theme.colorScheme.primary.withValues(alpha: 0.2),
        icon: Icons.edit,
        label: 'Edit / Copy',
      ),
      secondaryBackground: _SwipeBackground(
        alignment: Alignment.centerRight,
        color: theme.colorScheme.error.withValues(alpha: 0.2),
        icon: Icons.delete_outline,
        label: 'Delete',
      ),
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: theme.colorScheme.surface.withValues(alpha: 0.2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        child: Row(
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: theme.colorScheme.primary.withValues(alpha: 0.14),
              ),
              child: Icon(
                Icons.restaurant,
                color: theme.colorScheme.primary,
                size: 15,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.entry.mealName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$timeLabel • ${item.servingDescription}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelMedium?.copyWith(
                      color:
                          theme.colorScheme.onSurface.withValues(alpha: 0.68),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${item.calories.round()}',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(width: 2),
            Text(
              'kcal',
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.alignment,
    required this.color,
    required this.icon,
    required this.label,
  });

  final Alignment alignment;
  final Color color;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(14),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      alignment: alignment,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}
