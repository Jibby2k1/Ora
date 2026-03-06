import 'package:flutter/material.dart';

import '../glass/glass_card.dart';

enum DiaryAddAction {
  addFood,
  scanBarcode,
  quickAdd,
  addRecipe,
}

class AddActionSheet extends StatelessWidget {
  const AddActionSheet({
    super.key,
    this.mealSlot,
  });

  static Future<DiaryAddAction?> show(
    BuildContext context, {
    String? mealSlot,
  }) {
    return showModalBottomSheet<DiaryAddAction>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => AddActionSheet(mealSlot: mealSlot),
    );
  }

  final String? mealSlot;

  @override
  Widget build(BuildContext context) {
    final subtitle = mealSlot == null
        ? 'Choose how to add to your diary'
        : 'Add an item to $mealSlot';
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      child: GlassCard(
        padding: const EdgeInsets.all(14),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Quick Actions',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            _ActionTile(
              icon: Icons.search,
              title: 'Add Food',
              subtitle: 'Search and select foods',
              onTap: () => Navigator.of(context).pop(DiaryAddAction.addFood),
            ),
            _ActionTile(
              icon: Icons.qr_code_scanner,
              title: 'Scan Barcode',
              subtitle: 'Scan packaged foods',
              onTap: () =>
                  Navigator.of(context).pop(DiaryAddAction.scanBarcode),
            ),
            _ActionTile(
              icon: Icons.flash_on,
              title: 'Quick Add',
              subtitle: 'Manual calories and macros',
              onTap: () => Navigator.of(context).pop(DiaryAddAction.quickAdd),
            ),
            _ActionTile(
              icon: Icons.menu_book,
              title: 'Add Recipe',
              subtitle: 'Choose saved recipes',
              onTap: () => Navigator.of(context).pop(DiaryAddAction.addRecipe),
            ),
          ],
        ),
      ),
    );
  }
}

class _ActionTile extends StatelessWidget {
  const _ActionTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: 0, vertical: 2),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: theme.colorScheme.primary.withValues(alpha: 0.15),
          border: Border.all(
            color: theme.colorScheme.primary.withValues(alpha: 0.25),
          ),
        ),
        child: Icon(
          icon,
          color: theme.colorScheme.primary,
          size: 18,
        ),
      ),
      title: Text(
        title,
        style:
            theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
      ),
      subtitle: Text(
        subtitle,
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
        ),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
      ),
    );
  }
}
