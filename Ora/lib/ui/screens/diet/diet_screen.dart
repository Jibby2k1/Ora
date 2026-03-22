import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db/db.dart';
import '../../../data/food/food_repository.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../domain/models/diet_diary_models.dart';
import '../../../domain/models/diet_entry.dart';
import '../../../domain/services/diet_diary_service.dart';
import '../../widgets/diet/add_action_sheet.dart';
import '../../widgets/diet/meal_group_section.dart';
import '../../widgets/diet/summary_carousel.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'diet_goals_settings_page.dart';
import 'food_barcode_scan_page.dart';
import 'food_detail_page.dart';
import 'food_search_page.dart';
import 'recipes_page.dart';

class DietScreen extends StatefulWidget {
  const DietScreen({super.key});

  @override
  State<DietScreen> createState() => _DietScreenState();
}

class _DietScreenState extends State<DietScreen> {
  late final DietRepo _dietRepo;
  late final FoodRepository _foodRepository;
  late final DietDiaryService _diaryService;

  final DateFormat _dayFormat = DateFormat('EEE, MMM d, y');
  bool _loading = true;
  DateTime _selectedDay = _normalizeDay(DateTime.now());
  DietDiaryViewModel? _viewModel;
  final Map<String, bool> _collapsedByMeal = {
    for (final slot in DietDiaryService.mealSlots) slot: false,
  };

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _dietRepo = DietRepo(db);
    _foodRepository = FoodRepository(db: db, dietRepo: _dietRepo);
    _diaryService = DietDiaryService(db);
    _loadDay(_selectedDay);
  }

  static DateTime _normalizeDay(DateTime value) {
    return DateTime(value.year, value.month, value.day);
  }

  static bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  Future<void> _loadDay(DateTime day) async {
    final normalized = _normalizeDay(day);
    setState(() {
      _loading = true;
      _selectedDay = normalized;
    });

    final viewModel = await _diaryService.loadDay(normalized);
    if (!mounted) return;

    setState(() {
      _viewModel = viewModel;
      _loading = false;
    });
  }

  Future<void> _refresh() => _loadDay(_selectedDay);

  Future<void> _openDietSettings() async {
    final changed = await DietGoalsSettingsPage.show(context);
    if (!mounted || changed != true) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _openRecipesManager() async {
    final changed = await RecipesPage.showManage(
      context,
      selectedDay: _selectedDay,
    );
    if (!mounted || changed != true) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _goToPreviousDay() async {
    await _loadDay(_selectedDay.subtract(const Duration(days: 1)));
  }

  Future<void> _goToNextDay() async {
    final today = _normalizeDay(DateTime.now());
    if (_isSameDay(_selectedDay, today)) return;
    final next = _selectedDay.add(const Duration(days: 1));
    if (next.isAfter(today)) return;
    await _loadDay(next);
  }

  Future<void> _pickDay() async {
    final today = _normalizeDay(DateTime.now());
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedDay,
      firstDate: DateTime(2000),
      lastDate: today,
    );
    if (picked == null) return;
    await _loadDay(_normalizeDay(picked));
  }

  String _relativeDayLabel(DateTime day) {
    final today = _normalizeDay(DateTime.now());
    if (_isSameDay(day, today)) return 'Today';
    if (_isSameDay(day, today.subtract(const Duration(days: 1)))) {
      return 'Yesterday';
    }
    return _dayFormat.format(day);
  }

  Future<void> _openAddActions({String? mealSlot}) async {
    final action = await AddActionSheet.show(context, mealSlot: mealSlot);
    if (!mounted || action == null) return;
    await _handleAddAction(action, mealSlot: mealSlot);
  }

  Future<void> _handleAddAction(
    DiaryAddAction action, {
    String? mealSlot,
  }) async {
    final slot = mealSlot ?? DietDiaryService.mealSlots.first;
    switch (action) {
      case DiaryAddAction.addFood:
        await _openFoodSearch(slot);
        return;
      case DiaryAddAction.scanBarcode:
        await _scanBarcode(slot);
        return;
      case DiaryAddAction.quickAdd:
        await _showQuickAddDialog(mealSlot: slot);
        return;
      case DiaryAddAction.addRecipe:
        final added = await RecipesPage.showForDiary(
          context,
          foodRepository: _foodRepository,
          dietRepo: _dietRepo,
          selectedDay: _selectedDay,
          initialMealSlot: slot,
        );
        if (!mounted || added != true) return;
        await _loadDay(_selectedDay);
        return;
    }
  }

  Future<void> _openFoodSearch(String mealSlot) async {
    final added = await FoodSearchPage.show(
      context,
      foodRepository: _foodRepository,
      dietRepo: _dietRepo,
      initialMealSlot: mealSlot,
      selectedDay: _selectedDay,
    );
    if (!mounted || added != true) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _scanBarcode(String mealSlot) async {
    final barcode = await FoodBarcodeScanPage.show(context);
    if (!mounted || barcode == null || barcode.trim().isEmpty) return;

    final food = await _foodRepository.lookupBarcode(barcode.trim());
    if (!mounted) return;

    if (food == null) {
      final createCustom = await showDialog<bool>(
        context: context,
        builder: (context) {
          return AlertDialog(
            title: const Text('Food not found'),
            content: Text(
              'No product was found for barcode ${barcode.trim()}.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Create Custom Food'),
              ),
            ],
          );
        },
      );
      if (createCustom == true) {
        await _showQuickAddDialog(mealSlot: mealSlot);
      }
      return;
    }

    final added = await FoodDetailPage.show(
      context,
      food: food,
      dietRepo: _dietRepo,
      initialMealSlot: mealSlot,
      selectedDay: _selectedDay,
    );
    if (!mounted || added != true) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _showQuickAddDialog({
    required String mealSlot,
    DietEntry? editingEntry,
  }) async {
    final mealValue = ValueNotifier<String>(
      DietDiaryService.mealSlots.contains(mealSlot)
          ? mealSlot
          : DietDiaryService.mealSlots.first,
    );

    final nameController = TextEditingController(
      text: editingEntry?.mealName ?? '',
    );
    final caloriesController = TextEditingController(
      text: _asText(editingEntry?.calories),
    );
    final proteinController = TextEditingController(
      text: _asText(editingEntry?.proteinG),
    );
    final carbsController = TextEditingController(
      text: _asText(editingEntry?.carbsG),
    );
    final fatController = TextEditingController(
      text: _asText(editingEntry?.fatG),
    );
    final fiberController = TextEditingController(
      text: _asText(editingEntry?.fiberG),
    );
    final sodiumController = TextEditingController(
      text: _asText(editingEntry?.sodiumMg),
    );
    final notesController = TextEditingController(
      text: editingEntry?.notes ?? '',
    );

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(context).viewInsets.bottom + 16,
          ),
          child: GlassCard(
            padding: const EdgeInsets.all(16),
            child: ValueListenableBuilder<String>(
              valueListenable: mealValue,
              builder: (context, selectedMeal, _) {
                return ListView(
                  shrinkWrap: true,
                  children: [
                    Text(
                      editingEntry == null ? 'Quick Add' : 'Edit Entry',
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<String>(
                      initialValue: selectedMeal,
                      decoration: const InputDecoration(labelText: 'Meal'),
                      items: [
                        for (final slot in DietDiaryService.mealSlots)
                          DropdownMenuItem<String>(
                            value: slot,
                            child: Text(slot),
                          ),
                      ],
                      onChanged: (value) {
                        if (value == null) return;
                        mealValue.value = value;
                      },
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: nameController,
                      decoration: const InputDecoration(labelText: 'Food name'),
                    ),
                    const SizedBox(height: 8),
                    _numberField(caloriesController, 'Calories'),
                    const SizedBox(height: 8),
                    _numberField(proteinController, 'Protein (g)'),
                    const SizedBox(height: 8),
                    _numberField(carbsController, 'Carbs (g)'),
                    const SizedBox(height: 8),
                    _numberField(fatController, 'Fat (g)'),
                    const SizedBox(height: 8),
                    _numberField(fiberController, 'Fiber (g)'),
                    const SizedBox(height: 8),
                    _numberField(sodiumController, 'Sodium (mg)'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: notesController,
                      maxLines: 2,
                      decoration:
                          const InputDecoration(labelText: 'Notes (optional)'),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        TextButton(
                          onPressed: () => Navigator.of(context).pop(false),
                          child: const Text('Cancel'),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () => Navigator.of(context).pop(true),
                          child: const Text('Save'),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );

    final selectedMeal = mealValue.value;
    mealValue.dispose();

    if (confirmed != true || !mounted) {
      nameController.dispose();
      caloriesController.dispose();
      proteinController.dispose();
      carbsController.dispose();
      fatController.dispose();
      fiberController.dispose();
      sodiumController.dispose();
      notesController.dispose();
      return;
    }

    final name = nameController.text.trim().isEmpty
        ? (editingEntry?.mealName ?? 'Quick Add Food')
        : nameController.text.trim();

    if (editingEntry == null) {
      await _diaryService.quickAdd(
        day: _selectedDay,
        mealSlot: selectedMeal,
        foodName: name,
        calories: _parseDouble(caloriesController.text),
        proteinG: _parseDouble(proteinController.text),
        carbsG: _parseDouble(carbsController.text),
        fatG: _parseDouble(fatController.text),
        fiberG: _parseDouble(fiberController.text),
        sodiumMg: _parseDouble(sodiumController.text),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
    } else {
      await _diaryService.updateQuickEntry(
        entry: editingEntry,
        mealSlot: selectedMeal,
        foodName: name,
        calories: _parseDouble(caloriesController.text),
        proteinG: _parseDouble(proteinController.text),
        carbsG: _parseDouble(carbsController.text),
        fatG: _parseDouble(fatController.text),
        fiberG: _parseDouble(fiberController.text),
        sodiumMg: _parseDouble(sodiumController.text),
        notes: notesController.text.trim().isEmpty
            ? null
            : notesController.text.trim(),
      );
    }

    nameController.dispose();
    caloriesController.dispose();
    proteinController.dispose();
    carbsController.dispose();
    fatController.dispose();
    fiberController.dispose();
    sodiumController.dispose();
    notesController.dispose();

    if (!mounted) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _handleEntryEditOrCopy(DietDiaryEntryItem item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
          child: GlassCard(
            padding: const EdgeInsets.all(12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                ListTile(
                  leading: const Icon(Icons.edit_outlined),
                  title: const Text('Edit Entry'),
                  onTap: () => Navigator.of(context).pop('edit'),
                ),
                ListTile(
                  leading: const Icon(Icons.copy_outlined),
                  title: const Text('Copy Entry'),
                  onTap: () => Navigator.of(context).pop('copy'),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (!mounted || action == null) return;
    if (action == 'edit') {
      await _openFoodEditorForEntry(item);
      return;
    }

    await _diaryService.copyEntryToDay(
      entry: item.entry,
      day: _selectedDay,
      mealSlot: item.mealSlot,
    );
    if (!mounted) return;
    await _loadDay(_selectedDay);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Entry copied.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );
  }

  Future<void> _handleEntryTapEdit(DietDiaryEntryItem item) async {
    await _openFoodEditorForEntry(item);
  }

  Future<void> _openFoodEditorForEntry(DietDiaryEntryItem item) async {
    final updated = await FoodDetailPage.editEntry(
      context,
      entry: item.entry,
      dietRepo: _dietRepo,
      selectedDay: _selectedDay,
    );
    if (!mounted || updated != true) return;
    await _loadDay(_selectedDay);
  }

  Future<void> _handleEntryDelete(DietDiaryEntryItem item) async {
    await _diaryService.deleteEntry(item.entry.id);
    if (!mounted) return;
    await _loadDay(_selectedDay);
    if (!mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    final snackBarController = messenger.showSnackBar(
      SnackBar(
        content: const Text('Entry deleted.'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          onPressed: () async {
            await _diaryService.restoreEntry(item.entry);
            if (!mounted) return;
            await _loadDay(_selectedDay);
          },
        ),
      ),
    );

    await Future<void>.delayed(const Duration(seconds: 3));
    if (!mounted) return;
    snackBarController.close();
  }

  Future<void> _handleEntryDrop(
    DietDiaryEntryItem item,
    String targetMealSlot,
  ) async {
    if (item.mealSlot == targetMealSlot) return;
    await _diaryService.moveEntryToMeal(
      entry: item.entry,
      mealSlot: targetMealSlot,
    );
    if (!mounted) return;
    await _loadDay(_selectedDay);
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('Moved to $targetMealSlot'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  String _asText(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(1);
  }

  double _parseDouble(String input) {
    return double.tryParse(input.trim()) ?? 0;
  }

  Widget _numberField(TextEditingController controller, String label) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(labelText: label),
    );
  }

  Widget _buildDietMetric(String label, String value) {
    final theme = Theme.of(context);
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDietQuickAction({
    required IconData icon,
    required String label,
    required VoidCallback onPressed,
    bool primary = false,
  }) {
    if (primary) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 18),
        label: Text(label),
      );
    }
    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
      label: Text(label),
    );
  }

  Widget _buildDiaryView(
    DietDiaryViewModel? vm,
    bool isToday,
    ThemeData theme,
  ) {
    final hasDiary = vm != null;
    final consumedCalories =
        hasDiary ? vm.dailyTotals.calories.round().toString() : '--';
    final remainingCalories =
        hasDiary ? vm.remainingCalories.round().toString() : '--';
    final entries = hasDiary ? vm.totalEntries.toString() : '0';
    final mealSlot = DietDiaryService.mealSlots.first;

    return RefreshIndicator(
      onRefresh: _refresh,
      child: ListView(
        key: const ValueKey('diet-diary'),
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 94),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Icon(
                        Icons.restaurant_menu_rounded,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Diet',
                            style: theme.textTheme.titleLarge?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Track the selected day, log entries fast, and adjust targets without leaving the diary.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            _relativeDayLabel(_selectedDay),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildDietMetric('Consumed', consumedCalories),
                    _buildDietMetric('Remain', remainingCalories),
                    _buildDietMetric('Entries', entries),
                    _buildDietMetric('Day', _relativeDayLabel(_selectedDay)),
                  ],
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _buildDietQuickAction(
                      icon: Icons.add_circle_outline_rounded,
                      label: 'Log Food',
                      onPressed: () => _openAddActions(),
                      primary: true,
                    ),
                    _buildDietQuickAction(
                      icon: Icons.search_rounded,
                      label: 'Search',
                      onPressed: () => _openFoodSearch(mealSlot),
                    ),
                    _buildDietQuickAction(
                      icon: Icons.qr_code_scanner_rounded,
                      label: 'Scan',
                      onPressed: () => _scanBarcode(mealSlot),
                    ),
                    _buildDietQuickAction(
                      icon: Icons.tune_rounded,
                      label: 'Goals',
                      onPressed: _openDietSettings,
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              color: theme.colorScheme.surface.withValues(alpha: 0.14),
              border: Border.all(
                color: theme.colorScheme.outline.withValues(alpha: 0.18),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
            child: Row(
              children: [
                IconButton(
                  visualDensity:
                      const VisualDensity(horizontal: -2, vertical: -2),
                  onPressed: _goToPreviousDay,
                  icon: const Icon(Icons.chevron_left),
                ),
                Expanded(
                  child: InkWell(
                    onTap: _pickDay,
                    borderRadius: BorderRadius.circular(8),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _relativeDayLabel(_selectedDay),
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.onSurface
                                .withValues(alpha: 0.72),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 1),
                        Text(
                          _dayFormat.format(_selectedDay),
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                SizedBox(
                  width: 42,
                  child: isToday
                      ? const SizedBox.shrink()
                      : IconButton(
                          visualDensity: const VisualDensity(
                            horizontal: -2,
                            vertical: -2,
                          ),
                          onPressed: _goToNextDay,
                          icon: const Icon(Icons.chevron_right),
                        ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          if (vm != null) ...[
            SummaryCarousel(viewModel: vm),
            const SizedBox(height: 8),
            for (final group in vm.mealGroups) ...[
              MealGroupSection(
                group: group,
                collapsed: _collapsedByMeal[group.mealSlot] ?? false,
                onAdd: () => _openAddActions(mealSlot: group.mealSlot),
                onEdit: _handleEntryTapEdit,
                onToggleCollapsed: () {
                  setState(() {
                    _collapsedByMeal[group.mealSlot] =
                        !(_collapsedByMeal[group.mealSlot] ?? false);
                  });
                },
                onEditOrCopy: _handleEntryEditOrCopy,
                onDelete: _handleEntryDelete,
                onDropEntry: (item) => _handleEntryDrop(item, group.mealSlot),
              ),
              const SizedBox(height: 8),
            ],
          ],
          if (_loading)
            const Padding(
              padding: EdgeInsets.only(top: 12),
              child: Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final vm = _viewModel;
    final isToday = _isSameDay(_selectedDay, DateTime.now());
    final theme = Theme.of(context);
    final showInitialLoader = vm == null && _loading;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diet'),
        actions: [
          IconButton(
            tooltip: 'Saved recipes',
            onPressed: _openRecipesManager,
            icon: const Icon(Icons.menu_book_rounded),
          ),
          IconButton(
            tooltip: 'Diet settings',
            onPressed: _openDietSettings,
            icon: const Icon(Icons.tune_rounded),
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          if (showInitialLoader)
            const Center(child: CircularProgressIndicator())
          else
            _buildDiaryView(vm, isToday, theme),
          if (!showInitialLoader)
            SafeArea(
              minimum: const EdgeInsets.only(right: 16, bottom: 16),
              child: Align(
                alignment: Alignment.bottomRight,
                child: FloatingActionButton(
                  backgroundColor:
                      theme.colorScheme.primary.withValues(alpha: 0.92),
                  foregroundColor: theme.colorScheme.onPrimary,
                  elevation: 0,
                  onPressed: () => _openAddActions(),
                  child: const Icon(Icons.add),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
