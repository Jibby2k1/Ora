import '../../data/db/db.dart';
import '../../data/repositories/diet_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../models/diet_diary_models.dart';
import '../models/diet_entry.dart';
import 'calorie_service.dart';

class DietDiaryService {
  DietDiaryService(AppDatabase db)
      : _dietRepo = DietRepo(db),
        _settingsRepo = SettingsRepo(db),
        _calorieService = CalorieService(db);

  static const List<String> mealSlots = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
  ];

  final DietRepo _dietRepo;
  final SettingsRepo _settingsRepo;
  final CalorieService _calorieService;

  Future<DietDiaryViewModel> loadDay(DateTime day) async {
    final normalizedDay = _normalizeDay(day);
    final end = normalizedDay.add(const Duration(days: 1));

    final targets = await _loadTargets();
    final summary = await _dietRepo.getSummaryForDay(normalizedDay);
    final micros = await _dietRepo.getMicrosForRange(normalizedDay, end);
    final entries = await _dietRepo.getEntriesForDay(normalizedDay);
    final workoutEstimate = await _calorieService
        .estimateWorkoutCaloriesForRange(normalizedDay, end);

    final dailyTotals = DietMacroTotals(
      calories: summary.calories ?? 0,
      proteinG: summary.proteinG ?? 0,
      carbsG: summary.carbsG ?? 0,
      fatG: summary.fatG ?? 0,
      fiberG: summary.fiberG ?? 0,
      sodiumMg: summary.sodiumMg ?? 0,
    );

    final mealEntries = <String, List<DietDiaryEntryItem>>{
      for (final slot in mealSlots) slot: <DietDiaryEntryItem>[],
    };

    for (final entry in entries) {
      final slot = resolveMealSlot(entry);
      mealEntries[slot]!.add(
        DietDiaryEntryItem(
          entry: entry,
          mealSlot: slot,
          servingDescription: _extractServingDescription(entry.notes),
        ),
      );
    }

    final groups = <DietDiaryMealGroup>[];
    for (final slot in mealSlots) {
      final slotEntries = mealEntries[slot]!
        ..sort(
          (left, right) => right.entry.loggedAt.compareTo(left.entry.loggedAt),
        );
      var totals = const DietMacroTotals.zero();
      for (final item in slotEntries) {
        totals = totals.add(
          calories: item.calories,
          proteinG: item.entry.proteinG ?? 0,
          carbsG: item.entry.carbsG ?? 0,
          fatG: item.entry.fatG ?? 0,
          fiberG: item.entry.fiberG ?? 0,
          sodiumMg: item.entry.sodiumMg ?? 0,
        );
      }
      groups.add(
        DietDiaryMealGroup(
          mealSlot: slot,
          entries: List.unmodifiable(slotEntries),
          totals: totals,
        ),
      );
    }

    final burnedCalories = workoutEstimate.workoutCalories;
    final remainingCalories =
        targets.calories - dailyTotals.calories + burnedCalories;
    final entriesWithMicros =
        entries.where((entry) => (entry.micros?.isNotEmpty ?? false)).length;

    return DietDiaryViewModel(
      day: normalizedDay,
      targets: targets,
      dailyTotals: dailyTotals,
      burnedCalories: burnedCalories,
      remainingCalories: remainingCalories,
      mealGroups: groups,
      highlightedNutrients: _buildHighlightedNutrients(
        totals: dailyTotals,
        micros: micros,
      ),
      totalEntries: entries.length,
      entriesWithMicros: entriesWithMicros,
    );
  }

  Future<void> deleteEntry(int id) {
    return _dietRepo.deleteEntry(id);
  }

  Future<void> restoreEntry(DietEntry entry) {
    return _dietRepo.addEntry(
      mealName: entry.mealName,
      loggedAt: entry.loggedAt,
      mealType: entry.mealType,
      calories: entry.calories,
      proteinG: entry.proteinG,
      carbsG: entry.carbsG,
      fatG: entry.fatG,
      fiberG: entry.fiberG,
      sodiumMg: entry.sodiumMg,
      micros: entry.micros,
      notes: entry.notes,
      imagePath: entry.imagePath,
    );
  }

  Future<void> quickAdd({
    required DateTime day,
    required String mealSlot,
    required String foodName,
    required double calories,
    required double proteinG,
    required double carbsG,
    required double fatG,
    required double fiberG,
    required double sodiumMg,
    String? notes,
  }) {
    final mealLineNotes = _upsertMealLine(notes, mealSlot);
    return _dietRepo.addEntry(
      mealName: foodName,
      loggedAt: _entryTimestampForDay(day),
      mealType: _mealTypeFromSlot(mealSlot),
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      fiberG: fiberG,
      sodiumMg: sodiumMg,
      notes: mealLineNotes,
    );
  }

  Future<void> updateQuickEntry({
    required DietEntry entry,
    required String mealSlot,
    required String foodName,
    required double calories,
    required double proteinG,
    required double carbsG,
    required double fatG,
    required double fiberG,
    required double sodiumMg,
    String? notes,
  }) {
    final mergedNotes = _upsertMealLine(notes, mealSlot);
    return _dietRepo.updateEntry(
      id: entry.id,
      mealName: foodName,
      calories: calories,
      proteinG: proteinG,
      carbsG: carbsG,
      fatG: fatG,
      fiberG: fiberG,
      sodiumMg: sodiumMg,
      notes: mergedNotes,
      imagePath: entry.imagePath,
      micros: entry.micros,
    );
  }

  Future<void> copyEntryToDay({
    required DietEntry entry,
    required DateTime day,
    required String mealSlot,
  }) {
    final notes = _upsertMealLine(entry.notes, mealSlot);
    return _dietRepo.addEntry(
      mealName: entry.mealName,
      loggedAt: _entryTimestampForDay(day),
      mealType: _mealTypeFromSlot(mealSlot),
      calories: entry.calories,
      proteinG: entry.proteinG,
      carbsG: entry.carbsG,
      fatG: entry.fatG,
      fiberG: entry.fiberG,
      sodiumMg: entry.sodiumMg,
      micros: entry.micros,
      notes: notes,
      imagePath: entry.imagePath,
    );
  }

  Future<void> moveEntryToMeal({
    required DietEntry entry,
    required String mealSlot,
  }) {
    final notes = _upsertMealLine(entry.notes, mealSlot);
    return _dietRepo.updateEntry(
      id: entry.id,
      mealType: _mealTypeFromSlot(mealSlot),
      notes: notes,
    );
  }

  String resolveMealSlot(DietEntry entry) {
    final notes = entry.notes;
    if (notes != null) {
      final match = RegExp(
        r'^Meal:\s*(Breakfast|Lunch|Dinner|Snacks)\b',
        caseSensitive: false, multiLine: true,
      ).firstMatch(notes);
      if (match != null) {
        final raw = match.group(1)!;
        return _titleCase(raw);
      }
    }

    final hour = entry.loggedAt.hour;
    if (hour >= 5 && hour < 11) return 'Breakfast';
    if (hour >= 11 && hour < 15) return 'Lunch';
    if (hour >= 15 && hour < 21) return 'Dinner';
    return 'Snacks';
  }

  String _extractServingDescription(String? notes) {
    if (notes == null || notes.trim().isEmpty) {
      return '1 serving';
    }
    final servingMatch =
        RegExp(r'^Serving:\s*(.+)$', multiLine: true).firstMatch(notes);
    if (servingMatch != null) {
      return _normalizeServingDescription(servingMatch.group(1)!.trim());
    }

    final lines = notes
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return '1 serving';

    for (final line in lines) {
      if (line.startsWith('Meal:') || line.startsWith('Source:')) continue;
      return _normalizeServingDescription(line);
    }
    return '1 serving';
  }

  String _normalizeServingDescription(String raw) {
    final cleaned = raw.trim();
    if (cleaned.isEmpty) return '1 serving';
    return cleaned.replaceFirstMapped(
      RegExp(r'^(\d+(?:\.\d+)?)\s*x\s+', caseSensitive: false),
      (match) => '${match.group(1)} ',
    );
  }

  List<DietHighlightedNutrient> _buildHighlightedNutrients({
    required DietMacroTotals totals,
    required Map<String, double> micros,
  }) {
    final normalizedMicros = <String, double>{};
    for (final entry in micros.entries) {
      normalizedMicros[entry.key.trim().toLowerCase()] = entry.value;
    }
    return [
      DietHighlightedNutrient(
        key: 'fiber',
        label: 'Fiber',
        amount: totals.fiberG,
        target: 30,
        unit: 'g',
      ),
      DietHighlightedNutrient(
        key: 'iron',
        label: 'Iron',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['iron'],
        ),
        target: 18,
        unit: 'mg',
      ),
      DietHighlightedNutrient(
        key: 'calcium',
        label: 'Calcium',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['calcium'],
        ),
        target: 1000,
        unit: 'mg',
      ),
      DietHighlightedNutrient(
        key: 'vitamin_a',
        label: 'Vitamin A',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['vitamin_a', 'vitamin a'],
        ),
        target: 900,
        unit: 'mcg',
      ),
      DietHighlightedNutrient(
        key: 'vitamin_c',
        label: 'Vitamin C',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['vitamin_c', 'vitamin c'],
        ),
        target: 90,
        unit: 'mg',
      ),
      DietHighlightedNutrient(
        key: 'vitamin_b12',
        label: 'B12 (Cobalamin)',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['vitamin_b12', 'vitamin b12', 'b12'],
        ),
        target: 2.4,
        unit: 'mcg',
      ),
      DietHighlightedNutrient(
        key: 'folate',
        label: 'Folate',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['folate'],
        ),
        target: 400,
        unit: 'mcg',
      ),
      DietHighlightedNutrient(
        key: 'potassium',
        label: 'Potassium',
        amount: _firstPresentMicro(
          normalizedMicros,
          const ['potassium'],
        ),
        target: 3400,
        unit: 'mg',
      ),
    ];
  }

  double? _firstPresentMicro(
    Map<String, double> micros,
    List<String> keys,
  ) {
    for (final rawKey in keys) {
      final key = rawKey.trim().toLowerCase();
      if (micros.containsKey(key)) {
        return micros[key];
      }
      if (micros.containsKey(rawKey)) {
        return micros[rawKey];
      }
    }
    return null;
  }

  Future<DietMacroTargets> _loadTargets() async {
    return DietMacroTargets(
      calories:
          _readGoal(await _settingsRepo.getValue('diet_goal_calories'), 2500),
      proteinG:
          _readGoal(await _settingsRepo.getValue('diet_goal_protein'), 180),
      carbsG: _readGoal(await _settingsRepo.getValue('diet_goal_carbs'), 250),
      fatG: _readGoal(await _settingsRepo.getValue('diet_goal_fat'), 70),
      fiberG: _readGoal(await _settingsRepo.getValue('diet_goal_fiber'), 30),
      sodiumMg:
          _readGoal(await _settingsRepo.getValue('diet_goal_sodium'), 2300),
    );
  }

  double _readGoal(String? raw, double fallback) {
    final parsed = double.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  String _upsertMealLine(String? notes, String mealSlot) {
    final normalizedSlot = _titleCase(mealSlot);
    final lines = <String>[];

    var insertedMeal = false;
    if (notes != null && notes.trim().isNotEmpty) {
      for (final line in notes.split('\n')) {
        if (line.trim().isEmpty) continue;
        if (line.toLowerCase().startsWith('meal:')) {
          if (!insertedMeal) {
            lines.add('Meal: $normalizedSlot');
            insertedMeal = true;
          }
          continue;
        }
        lines.add(line.trim());
      }
    }

    if (!insertedMeal) {
      lines.insert(0, 'Meal: $normalizedSlot');
    }

    return lines.join('\n');
  }

  DietMealType _mealTypeFromSlot(String mealSlot) {
    switch (mealSlot.trim().toLowerCase()) {
      case 'breakfast':
        return DietMealType.breakfast;
      case 'lunch':
        return DietMealType.lunch;
      case 'dinner':
        return DietMealType.dinner;
      case 'snacks':
      case 'snack':
      default:
        return DietMealType.snack;
    }
  }

  DateTime _entryTimestampForDay(DateTime day) {
    final normalizedDay = _normalizeDay(day);
    final now = DateTime.now();
    if (_isSameDay(normalizedDay, now)) {
      return now;
    }
    return DateTime(
      normalizedDay.year,
      normalizedDay.month,
      normalizedDay.day,
      12,
    );
  }

  DateTime _normalizeDay(DateTime day) {
    return DateTime(day.year, day.month, day.day);
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  String _titleCase(String text) {
    if (text.isEmpty) return text;
    return text[0].toUpperCase() + text.substring(1).toLowerCase();
  }
}
