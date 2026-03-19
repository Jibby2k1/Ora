import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/diet_entry.dart';
import '../../../domain/models/food_detail_computed.dart';
import '../../../domain/models/food_models.dart';
import '../../../domain/services/food_detail_computer.dart';
import '../../../domain/services/food_nutrient_scaler.dart';
import '../../../domain/services/food_serving_converter.dart';
import '../../widgets/diet/food_source_badge.dart';
import '../../widgets/diet/layered_progress_bar.dart';
import '../../widgets/diet/macro_donut_chart.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class FoodDetailPage extends StatefulWidget {
  const FoodDetailPage({
    super.key,
    required this.food,
    required this.dietRepo,
    this.initialMealSlot,
    this.selectedDay,
    this.editingEntry,
    this.initialAmount,
    this.initialLoggedAt,
    this.initialServingLabel,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FoodItem food,
    required DietRepo dietRepo,
    String? initialMealSlot,
    DateTime? selectedDay,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodDetailPage(
          food: food,
          dietRepo: dietRepo,
          initialMealSlot: initialMealSlot,
          selectedDay: selectedDay,
        ),
      ),
    );
  }

  static Future<bool?> editEntry(
    BuildContext context, {
    required DietEntry entry,
    required DietRepo dietRepo,
    DateTime? selectedDay,
  }) {
    final normalizedDay = DateTime(
      (selectedDay ?? entry.loggedAt).year,
      (selectedDay ?? entry.loggedAt).month,
      (selectedDay ?? entry.loggedAt).day,
    );
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodDetailPage(
          food: _foodItemFromEntry(entry),
          dietRepo: dietRepo,
          initialMealSlot: _mealSlotFromEntry(entry),
          selectedDay: normalizedDay,
          editingEntry: entry,
          initialAmount: entry.portionAmount,
          initialLoggedAt: entry.loggedAt,
          initialServingLabel: entry.portionLabel,
        ),
      ),
    );
  }

  static String _mealSlotFromEntry(DietEntry entry) {
    switch (entry.mealType) {
      case DietMealType.breakfast:
        return 'Breakfast';
      case DietMealType.lunch:
        return 'Lunch';
      case DietMealType.dinner:
        return 'Dinner';
      case DietMealType.snack:
        return 'Snacks';
    }
  }

  static FoodSource _sourceFromStorage(String? value) {
    switch (value?.trim().toLowerCase()) {
      case 'usda_fdc':
        return FoodSource.usdaFdc;
      case 'open_food_facts':
        return FoodSource.openFoodFacts;
      case 'nutritionix':
        return FoodSource.nutritionix;
      case 'custom':
      default:
        return FoodSource.custom;
    }
  }

  static NutrientKey? _nutrientKeyFromStoredId(String rawKey) {
    final normalized = rawKey.trim().toLowerCase();
    for (final key in NutrientKey.values) {
      if (key.id == normalized) return key;
    }
    final cleaned = normalized.replaceAll(' ', '_');
    for (final key in NutrientKey.values) {
      if (key.id == cleaned) return key;
    }
    return null;
  }

  static double _derivedCalories({
    required double? calories,
    required double? proteinG,
    required double? carbsG,
    required double? fatG,
  }) {
    if (calories != null && calories > 0) return calories;
    final protein = proteinG ?? 0;
    final carbs = carbsG ?? 0;
    final fat = fatG ?? 0;
    final derived = (protein * 4) + (carbs * 4) + (fat * 9);
    return derived > 0 ? derived : 0;
  }

  static FoodItem _foodItemFromEntry(DietEntry entry) {
    final servingAmount =
        (entry.portionAmount != null && entry.portionAmount! > 0)
            ? entry.portionAmount!
            : 1.0;
    final gramsPerServing =
        (entry.portionGrams != null && entry.portionGrams! > 0)
            ? entry.portionGrams! / servingAmount
            : null;
    final calories = FoodDetailPage._derivedCalories(
      calories: entry.calories,
      proteinG: entry.proteinG,
      carbsG: entry.carbsG,
      fatG: entry.fatG,
    );

    final nutrients = <NutrientKey, NutrientValue>{
      if (calories > 0)
        NutrientKey.calories: NutrientValue(
          key: NutrientKey.calories,
          amount: calories / servingAmount,
          unit: NutrientKey.calories.defaultUnit,
        ),
      if ((entry.proteinG ?? 0) > 0)
        NutrientKey.protein: NutrientValue(
          key: NutrientKey.protein,
          amount: (entry.proteinG ?? 0) / servingAmount,
          unit: NutrientKey.protein.defaultUnit,
        ),
      if ((entry.carbsG ?? 0) > 0)
        NutrientKey.carbs: NutrientValue(
          key: NutrientKey.carbs,
          amount: (entry.carbsG ?? 0) / servingAmount,
          unit: NutrientKey.carbs.defaultUnit,
        ),
      if ((entry.fatG ?? 0) > 0)
        NutrientKey.fatTotal: NutrientValue(
          key: NutrientKey.fatTotal,
          amount: (entry.fatG ?? 0) / servingAmount,
          unit: NutrientKey.fatTotal.defaultUnit,
        ),
      if ((entry.fiberG ?? 0) > 0)
        NutrientKey.fiber: NutrientValue(
          key: NutrientKey.fiber,
          amount: (entry.fiberG ?? 0) / servingAmount,
          unit: NutrientKey.fiber.defaultUnit,
        ),
      if ((entry.sodiumMg ?? 0) > 0)
        NutrientKey.sodium: NutrientValue(
          key: NutrientKey.sodium,
          amount: (entry.sodiumMg ?? 0) / servingAmount,
          unit: NutrientKey.sodium.defaultUnit,
        ),
    };

    entry.micros?.forEach((key, totalAmount) {
      final nutrientKey = _nutrientKeyFromStoredId(key);
      if (nutrientKey == null || totalAmount <= 0) return;
      if (nutrients.containsKey(nutrientKey)) return;
      nutrients[nutrientKey] = NutrientValue(
        key: nutrientKey,
        amount: totalAmount / servingAmount,
        unit: nutrientKey.defaultUnit,
      );
    });

    return FoodItem(
      id: entry.foodSourceId ?? 'diet_entry_${entry.id}',
      source: _sourceFromStorage(entry.foodSource),
      name: entry.mealName,
      barcode: entry.barcode,
      servingOptions: [
        ServingOption(
          id: 'entry_serving',
          label: entry.portionLabel ??
              (entry.portionUnit == null
                  ? '1 serving'
                  : '1 ${entry.portionUnit}'),
          amount: 1,
          unit: entry.portionUnit ?? 'serving',
          gramWeight: gramsPerServing,
          isDefault: true,
        ),
      ],
      nutrients: nutrients,
      nutrientsPer100g: false,
      lastUpdated: entry.loggedAt,
      sourceDescription: entry.foodSource ?? 'Diary Entry',
    );
  }

  final FoodItem food;
  final DietRepo dietRepo;
  final String? initialMealSlot;
  final DateTime? selectedDay;
  final DietEntry? editingEntry;
  final double? initialAmount;
  final DateTime? initialLoggedAt;
  final String? initialServingLabel;

  @override
  State<FoodDetailPage> createState() => _FoodDetailPageState();
}

class _FoodDetailPageState extends State<FoodDetailPage> {
  static const List<String> _mealSlots = [
    'Breakfast',
    'Lunch',
    'Dinner',
    'Snacks',
  ];

  final FoodServingConverter _servingConverter = const FoodServingConverter();
  final FoodDetailComputer _detailComputer = const FoodDetailComputer();
  final NumberFormat _decimal = NumberFormat('#,##0.##');
  final TextEditingController _amountController =
      TextEditingController(text: '1');
  final FocusNode _amountFocusNode = FocusNode();

  late final SettingsRepo _settingsRepo;
  late final DateTime _selectedDay;
  late final FoodServingCatalog _servingCatalog;

  FoodDiarySnapshot? _diarySnapshot;

  String _selectedServingId = '';
  double _amount = 1;
  late DateTime _loggedAt;
  String _mealSlot = _mealSlots.first;
  bool _showAllNutrients = false;
  bool _loadingDiary = true;
  bool _saving = false;
  bool _amountPadOpen = false;
  String? _diaryError;
  bool get _isEditing => widget.editingEntry != null;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _selectedDay = _normalizeDay(widget.selectedDay ?? DateTime.now());
    _servingCatalog = _servingConverter.buildCatalog(widget.food);
    _selectedServingId = _servingCatalog.defaultChoiceId;
    _loggedAt = widget.initialLoggedAt ?? _defaultLoggedAt(_selectedDay);

    final initialAmount = widget.initialAmount;
    if (initialAmount != null && initialAmount > 0) {
      _amount = initialAmount;
      _amountController.text = _formatAmount(initialAmount);
    }

    final initialSlot = widget.initialMealSlot?.trim();
    if (initialSlot != null && _mealSlots.contains(initialSlot)) {
      _mealSlot = initialSlot;
    }

    final initialServingLabel =
        widget.initialServingLabel?.trim().toLowerCase();
    if (initialServingLabel != null && initialServingLabel.isNotEmpty) {
      for (final choice in _servingCatalog.choices) {
        if (choice.label.trim().toLowerCase() == initialServingLabel) {
          _selectedServingId = choice.id;
          break;
        }
      }
    }

    _loadDiarySnapshot();
  }

  @override
  void dispose() {
    _amountFocusNode.dispose();
    _amountController.dispose();
    super.dispose();
  }

  DateTime _normalizeDay(DateTime day) =>
      DateTime(day.year, day.month, day.day);

  DateTime _defaultLoggedAt(DateTime day) {
    final now = DateTime.now();
    if (_isSameDay(day, now)) return now;
    return DateTime(day.year, day.month, day.day, 12);
  }

  bool _isSameDay(DateTime left, DateTime right) {
    return left.year == right.year &&
        left.month == right.month &&
        left.day == right.day;
  }

  FoodServingChoice get _selectedServing {
    return _servingCatalog.byId(_selectedServingId) ??
        _servingCatalog.defaultChoice;
  }

  FoodServingScaleResult get _scaledResult {
    return _servingConverter.scale(
      food: widget.food,
      choice: _selectedServing,
      amount: _amount,
    );
  }

  FoodDiarySnapshot get _effectiveSnapshot {
    return _diarySnapshot ??
        FoodDiarySnapshot(
          day: _selectedDay,
          consumed: const <NutrientKey, double>{},
          targets: _buildDefaultTargets(),
          totalEntries: 0,
          entriesWithMicros: 0,
        );
  }

  FoodDetailComputedData _buildComputed({
    required bool useDeltaForProgress,
  }) {
    final scaledNutrients = useDeltaForProgress
        ? _progressDeltaNutrients(_scaledResult.scaled)
        : _scaledResult.scaled.nutrients;
    return _detailComputer.compute(
      scaledNutrients: scaledNutrients,
      diary: _effectiveSnapshot,
      showAllNutrients: _showAllNutrients,
    );
  }

  Map<NutrientKey, NutrientValue> _progressDeltaNutrients(
      FoodScaledView scaled) {
    if (!_isEditing) {
      return scaled.nutrients;
    }
    final entry = widget.editingEntry;
    if (entry == null) {
      return scaled.nutrients;
    }

    final previous = _editingEntryNutrients(entry);
    final delta = <NutrientKey, NutrientValue>{};
    final allKeys = <NutrientKey>{
      ...scaled.nutrients.keys,
      ...previous.keys,
    };

    for (final key in allKeys) {
      final nextAmount = scaled.nutrients[key]?.amount ?? 0;
      final previousAmount = previous[key]?.amount ?? 0;
      final diff = nextAmount - previousAmount;
      if (diff.abs() < 0.000001) {
        continue;
      }
      delta[key] = NutrientValue(
        key: key,
        amount: diff,
        unit: key.defaultUnit,
        displayName:
            scaled.nutrients[key]?.displayName ?? previous[key]?.displayName,
      );
    }

    return delta;
  }

  Map<NutrientKey, NutrientValue> _editingEntryNutrients(DietEntry entry) {
    final nutrients = <NutrientKey, NutrientValue>{};

    final calories = FoodDetailPage._derivedCalories(
      calories: entry.calories,
      proteinG: entry.proteinG,
      carbsG: entry.carbsG,
      fatG: entry.fatG,
    );
    if (calories > 0) {
      nutrients[NutrientKey.calories] = NutrientValue(
        key: NutrientKey.calories,
        amount: calories,
        unit: NutrientKey.calories.defaultUnit,
      );
    }
    if ((entry.proteinG ?? 0) != 0) {
      nutrients[NutrientKey.protein] = NutrientValue(
        key: NutrientKey.protein,
        amount: entry.proteinG ?? 0,
        unit: NutrientKey.protein.defaultUnit,
      );
    }
    if ((entry.carbsG ?? 0) != 0) {
      nutrients[NutrientKey.carbs] = NutrientValue(
        key: NutrientKey.carbs,
        amount: entry.carbsG ?? 0,
        unit: NutrientKey.carbs.defaultUnit,
      );
    }
    if ((entry.fatG ?? 0) != 0) {
      nutrients[NutrientKey.fatTotal] = NutrientValue(
        key: NutrientKey.fatTotal,
        amount: entry.fatG ?? 0,
        unit: NutrientKey.fatTotal.defaultUnit,
      );
    }
    if ((entry.fiberG ?? 0) != 0) {
      nutrients[NutrientKey.fiber] = NutrientValue(
        key: NutrientKey.fiber,
        amount: entry.fiberG ?? 0,
        unit: NutrientKey.fiber.defaultUnit,
      );
    }
    if ((entry.sodiumMg ?? 0) != 0) {
      nutrients[NutrientKey.sodium] = NutrientValue(
        key: NutrientKey.sodium,
        amount: entry.sodiumMg ?? 0,
        unit: NutrientKey.sodium.defaultUnit,
      );
    }

    entry.micros?.forEach((rawKey, amount) {
      final key = _parseStoredNutrientKey(rawKey);
      if (key == null || amount == 0) return;
      if (nutrients.containsKey(key)) return;
      nutrients[key] = NutrientValue(
        key: key,
        amount: amount,
        unit: key.defaultUnit,
      );
    });

    return nutrients;
  }

  double _effectiveScaledCalories(FoodScaledView scaled) {
    if (scaled.calories > 0) return scaled.calories;
    final derived =
        (scaled.protein * 4) + (scaled.carbs * 4) + (scaled.fat * 9);
    return derived > 0 ? derived : 0;
  }

  Future<void> _loadDiarySnapshot() async {
    setState(() {
      _loadingDiary = true;
      _diaryError = null;
    });

    try {
      final start = _selectedDay;
      final end = start.add(const Duration(days: 1));
      final summary = await widget.dietRepo.getSummaryForDay(start);
      final micros = await widget.dietRepo.getMicrosForRange(start, end);
      final entries = await widget.dietRepo.getEntriesForDay(start);
      final targets = await _loadTargets();

      final consumed = <NutrientKey, double>{
        NutrientKey.calories: summary.calories ?? 0,
        NutrientKey.protein: summary.proteinG ?? 0,
        NutrientKey.carbs: summary.carbsG ?? 0,
        NutrientKey.fatTotal: summary.fatG ?? 0,
        NutrientKey.fiber: summary.fiberG ?? 0,
        NutrientKey.sodium: summary.sodiumMg ?? 0,
      };

      micros.forEach((rawKey, value) {
        final key = _parseStoredNutrientKey(rawKey);
        if (key == null) return;
        consumed[key] = (consumed[key] ?? 0) + value;
      });

      final entriesWithMicros =
          entries.where((entry) => (entry.micros?.isNotEmpty ?? false)).length;

      if (!mounted) return;
      setState(() {
        _diarySnapshot = FoodDiarySnapshot(
          day: _selectedDay,
          consumed: consumed,
          targets: targets,
          totalEntries: entries.length,
          entriesWithMicros: entriesWithMicros,
        );
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _diaryError = 'Unable to load diary totals for this day.';
      });
    } finally {
      if (mounted) {
        setState(() {
          _loadingDiary = false;
        });
      }
    }
  }

  Future<Map<NutrientKey, double>> _loadTargets() async {
    final targets = _buildDefaultTargets();
    targets[NutrientKey.calories] = _readGoal(
      await _settingsRepo.getValue('diet_goal_calories'),
      2500,
    );
    targets[NutrientKey.protein] = _readGoal(
      await _settingsRepo.getValue('diet_goal_protein'),
      180,
    );
    targets[NutrientKey.carbs] = _readGoal(
      await _settingsRepo.getValue('diet_goal_carbs'),
      250,
    );
    targets[NutrientKey.fatTotal] = _readGoal(
      await _settingsRepo.getValue('diet_goal_fat'),
      70,
    );
    targets[NutrientKey.fiber] = _readGoal(
      await _settingsRepo.getValue('diet_goal_fiber'),
      30,
    );
    targets[NutrientKey.sodium] = _readGoal(
      await _settingsRepo.getValue('diet_goal_sodium'),
      2300,
    );
    return targets;
  }

  Map<NutrientKey, double> _buildDefaultTargets() {
    return <NutrientKey, double>{
      ...FoodDetailComputer.defaultMicronutrientTargets,
    };
  }

  double _readGoal(String? raw, double fallback) {
    final parsed = double.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  NutrientKey? _parseStoredNutrientKey(String rawKey) {
    final normalized = _normalizeToken(rawKey);
    for (final key in NutrientKey.values) {
      if (_normalizeToken(key.id) == normalized ||
          _normalizeToken(key.label) == normalized) {
        return key;
      }
    }
    return null;
  }

  String _normalizeToken(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }

  Future<void> _editAmountWithNumberPad() async {
    if (_amountPadOpen) return;
    final originalRaw = _amountController.text.trim();
    _amountFocusNode.requestFocus();
    _amountController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: _amountController.text.length,
    );
    _amountPadOpen = true;
    final raw = await _showFoodNumberPad(
      context: context,
      title: 'Amount',
      initialValue: originalRaw,
      mode: _FoodNumberPadMode.decimal,
      onChanged: (value) {
        if (!mounted) return;
        setState(() {
          _amountController.value = TextEditingValue(
            text: value,
            selection: TextSelection.collapsed(offset: value.length),
          );
          final parsed = double.tryParse(value.trim());
          if (parsed != null && parsed > 0) {
            _amount = parsed;
          }
        });
        _amountFocusNode.requestFocus();
      },
    );
    _amountPadOpen = false;
    if (!mounted) return;

    if (raw == null) {
      setState(() {
        _amountController.value = TextEditingValue(
          text: originalRaw,
          selection: TextSelection.collapsed(offset: originalRaw.length),
        );
        final parsed = double.tryParse(originalRaw);
        if (parsed != null && parsed > 0) {
          _amount = parsed;
        }
      });
      _amountFocusNode.requestFocus();
      return;
    }

    final parsed = double.tryParse(raw.trim());
    if (parsed == null || parsed <= 0) {
      setState(() {
        _amountController.value = TextEditingValue(
          text: originalRaw,
          selection: TextSelection.collapsed(offset: originalRaw.length),
        );
      });
      _amountFocusNode.requestFocus();
      return;
    }

    final formatted = _formatAmount(parsed);
    setState(() {
      _amount = parsed;
      _amountController.value = TextEditingValue(
        text: formatted,
        selection: TextSelection.collapsed(offset: formatted.length),
      );
    });
    _amountFocusNode.requestFocus();
  }

  Future<void> _pickTimestamp() async {
    final initial = TimeOfDay.fromDateTime(_loggedAt);
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
      builder: (context, child) {
        return Theme(
          data: Theme.of(context),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null) return;
    setState(() {
      _loggedAt = DateTime(
        _selectedDay.year,
        _selectedDay.month,
        _selectedDay.day,
        picked.hour,
        picked.minute,
      );
    });
  }

  Future<void> _addToDiary() async {
    if (_saving) return;
    setState(() {
      _saving = true;
    });

    try {
      final scaledResult = _scaledResult;
      final scaled = scaledResult.scaled;
      final notes = [
        'Meal: $_mealSlot',
        'Source: ${widget.food.source.label}',
        'Serving: ${_formatAmount(_amount)} x ${_selectedServing.label}',
        'Logged: ${DateFormat('MMM d, yyyy h:mm a').format(_loggedAt)}',
        if (widget.food.barcode != null && widget.food.barcode!.isNotEmpty)
          'Barcode: ${widget.food.barcode}',
        if (scaledResult.isApproximate) 'Serving conversion uses an estimate.',
      ].join('\n');

      final micros = <String, double>{};
      for (final entry in scaled.nutrients.entries) {
        final key = entry.key;
        if (key == NutrientKey.calories ||
            key == NutrientKey.protein ||
            key == NutrientKey.carbs ||
            key == NutrientKey.fatTotal ||
            key == NutrientKey.fiber ||
            key == NutrientKey.sodium) {
          continue;
        }
        micros[key.id] = entry.value.amount;
      }

      if (_isEditing) {
        final entry = widget.editingEntry!;
        await widget.dietRepo.updateEntry(
          id: entry.id,
          mealName: widget.food.name,
          loggedAt: _loggedAt,
          mealType: _mealTypeFromSlot(_mealSlot),
          calories: scaled.calories,
          proteinG: scaled.protein,
          carbsG: scaled.carbs,
          fatG: scaled.fat,
          fiberG: scaled.fiber,
          sodiumMg: scaled.sodium,
          micros: micros.isEmpty ? null : micros,
          notes: notes,
          imagePath: entry.imagePath,
          barcode: widget.food.barcode,
          foodSource: widget.food.source.cacheKey,
          foodSourceId: widget.food.id,
          portionLabel: _selectedServing.label,
          portionGrams: scaled.totalGrams,
          portionAmount: _amount,
          portionUnit: _selectedServing.unitLabel,
        );
      } else {
        await widget.dietRepo.addEntry(
          mealName: widget.food.name,
          loggedAt: _loggedAt,
          mealType: _mealTypeFromSlot(_mealSlot),
          calories: scaled.calories,
          proteinG: scaled.protein,
          carbsG: scaled.carbs,
          fatG: scaled.fat,
          fiberG: scaled.fiber,
          sodiumMg: scaled.sodium,
          micros: micros.isEmpty ? null : micros,
          notes: notes,
          barcode: widget.food.barcode,
          foodSource: widget.food.source.cacheKey,
          foodSourceId: widget.food.id,
          portionLabel: _selectedServing.label,
          portionGrams: scaled.totalGrams,
          portionAmount: _amount,
          portionUnit: _selectedServing.unitLabel,
        );
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content:
              Text(_isEditing ? 'Food entry updated.' : 'Food added to diary.'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
        ),
      );
      Navigator.of(context).pop(true);
    } catch (error, stackTrace) {
      debugPrint('FoodDetailPage._addToDiary failed: $error\n$stackTrace');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Could not add this food right now.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) {
        setState(() {
          _saving = false;
        });
      }
    }
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

  String _formatAmount(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value
        .toStringAsFixed(2)
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  String _formatValue(double value, {int maxDecimals = 1}) {
    if (value.abs() >= 1000) return _decimal.format(value);
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(maxDecimals);
  }

  String _formatCompactValue(double value, String unit) {
    if (unit == 'kcal') {
      return '${value.toStringAsFixed(0)} $unit';
    }
    if (unit == 'g' || unit == 'mg' || unit == 'mcg') {
      final decimals = value.abs() >= 10 ? 1 : 2;
      return '${_formatValue(value, maxDecimals: decimals)} $unit';
    }
    return '${_formatValue(value, maxDecimals: 2)} $unit';
  }

  Color _macroColor(String id) {
    return switch (id) {
      'calories' => Colors.white,
      'protein' => Colors.green,
      'carbs' => Colors.blue,
      'fat' => Colors.red,
      _ => Theme.of(context).colorScheme.primary,
    };
  }

  String _servingPlaceholder() {
    if (_selectedServing.unitType == FoodServingUnitType.grams) {
      return 'grams';
    }
    if (_selectedServing.unitType == FoodServingUnitType.cups) {
      return 'cups';
    }
    return 'amount';
  }

  InputDecoration _compactInputDecoration({
    required String label,
    String? hint,
  }) {
    return InputDecoration(
      labelText: label,
      hintText: hint,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final summaryComputed = _buildComputed(useDeltaForProgress: false);
    final progressComputed = _buildComputed(useDeltaForProgress: true);
    final scaledResult = _scaledResult;
    final scaled = scaledResult.scaled;

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          onPressed: () => Navigator.of(context).pop(false),
          icon: const Icon(Icons.close),
          tooltip: 'Close',
        ),
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.food.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w800,
              ),
            ),
            if ((widget.food.brand ?? '').trim().isNotEmpty)
              Text(
                widget.food.brand!.trim(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'copy') {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Copy to Custom Food is coming soon.'),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem<String>(
                value: 'copy',
                child: Text('Copy to Custom Food'),
              ),
            ],
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 128),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeaderCard(theme),
                const SizedBox(height: 12),
                _buildEntryControlsCard(theme, scaledResult),
                const SizedBox(height: 12),
                _buildMacroSummaryCard(
                  theme: theme,
                  computed: summaryComputed,
                  scaled: scaled,
                ),
                const SizedBox(height: 12),
                _buildMacroProgressCard(theme, progressComputed),
                const SizedBox(height: 12),
                _buildMicronutrientsCard(theme, progressComputed),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        child: GlassCard(
          padding: const EdgeInsets.all(10),
          child: ElevatedButton(
            onPressed: _saving ? null : _addToDiary,
            style: ElevatedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
            child: Text(_saving
                ? (_isEditing ? 'Saving...' : 'Adding...')
                : (_isEditing ? 'Save Changes' : 'Add to Diary')),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard(ThemeData theme) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FoodSourceBadge(source: widget.food.source),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  widget.food.sourceDescription ?? 'Food source',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if ((widget.food.barcode ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              'Barcode: ${widget.food.barcode!.trim()}',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
          if ((widget.food.ingredientsText ?? '').trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              widget.food.ingredientsText!.trim(),
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildEntryControlsCard(
    ThemeData theme,
    FoodServingScaleResult scaledResult,
  ) {
    final timestampLabel = DateFormat('EEE, MMM d • h:mm a').format(_loggedAt);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Entry Controls',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _amountController,
                  focusNode: _amountFocusNode,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  readOnly: true,
                  showCursor: true,
                  enableInteractiveSelection: true,
                  decoration: _compactInputDecoration(
                    label: 'Amount',
                    hint: _servingPlaceholder(),
                  ),
                  onTap: _editAmountWithNumberPad,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>('serving_$_selectedServingId'),
                  initialValue: _selectedServingId,
                  isDense: true,
                  decoration: _compactInputDecoration(label: 'Serving Size'),
                  items: [
                    for (final option in _servingCatalog.choices)
                      DropdownMenuItem<String>(
                        value: option.id,
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _selectedServingId = value;
                    });
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _pickTimestamp,
                  child: InputDecorator(
                    decoration: _compactInputDecoration(label: 'Timestamp'),
                    child: Text(timestampLabel),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  key: ValueKey<String>('meal_$_mealSlot'),
                  initialValue: _mealSlot,
                  isDense: true,
                  decoration: _compactInputDecoration(label: 'Meal Group'),
                  items: [
                    for (final slot in _mealSlots)
                      DropdownMenuItem<String>(
                        value: slot,
                        child: Text(slot),
                      ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() {
                      _mealSlot = value;
                    });
                  },
                ),
              ),
            ],
          ),
          if (scaledResult.isApproximate) ...[
            const SizedBox(height: 9),
            Text(
              'Some serving conversions are estimated due to missing density/gram mapping in source data.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMacroSummaryCard({
    required ThemeData theme,
    required FoodDetailComputedData computed,
    required FoodScaledView scaled,
  }) {
    final proteinColor = _macroColor('protein');
    final carbsColor = _macroColor('carbs');
    final fatColor = _macroColor('fat');

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Energy Summary',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxWidth < 390;
              final legend = _buildMacroLegend(
                theme: theme,
                segments: computed.macroPieSegments,
                proteinColor: proteinColor,
                carbsColor: carbsColor,
                fatColor: fatColor,
              );
              if (compact) {
                return Column(
                  children: [
                    MacroDonutChart(
                      segments: computed.macroPieSegments,
                      totalCalories: computed.totalCalories,
                      proteinColor: proteinColor,
                      carbsColor: carbsColor,
                      fatColor: fatColor,
                    ),
                    const SizedBox(height: 8),
                    legend,
                  ],
                );
              }
              return Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: MacroDonutChart(
                      segments: computed.macroPieSegments,
                      totalCalories: computed.totalCalories,
                      proteinColor: proteinColor,
                      carbsColor: carbsColor,
                      fatColor: fatColor,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    flex: 6,
                    child: legend,
                  ),
                ],
              );
            },
          ),
          const SizedBox(height: 10),
          Text(
            'Selected serving: ${_formatAmount(_amount)} x ${_selectedServing.label}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Calories: ${_formatCompactValue(_effectiveScaledCalories(scaled), 'kcal')}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMacroLegend({
    required ThemeData theme,
    required List<MacroPieSegment> segments,
    required Color proteinColor,
    required Color carbsColor,
    required Color fatColor,
  }) {
    final colors = [proteinColor, carbsColor, fatColor];
    return Column(
      children: [
        for (var i = 0; i < segments.length; i++) ...[
          Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: colors[i],
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  segments[i].label,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                '${_formatValue(segments[i].grams, maxDecimals: 1)} g',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${(segments[i].percent * 100).round()}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.76),
                ),
              ),
            ],
          ),
          if (i < segments.length - 1) const SizedBox(height: 8),
        ],
      ],
    );
  }

  Widget _buildMacroProgressCard(
      ThemeData theme, FoodDetailComputedData computed) {
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Macronutrient Targets',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              if (_loadingDiary)
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (_diaryError != null) ...[
            const SizedBox(height: 6),
            Text(
              _diaryError!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
              ),
            ),
          ],
          const SizedBox(height: 8),
          for (var i = 0; i < computed.macroRows.length; i++) ...[
            _NutrientProgressRow(
              row: computed.macroRows[i],
              barColor: _macroColor(computed.macroRows[i].id),
              addedColor:
                  _macroColor(computed.macroRows[i].id).withValues(alpha: 0.48),
              formatter: _formatCompactValue,
              icon: switch (computed.macroRows[i].id) {
                'calories' => Icons.local_fire_department,
                'protein' => Icons.fitness_center,
                'carbs' => Icons.grain,
                'fat' => Icons.water_drop,
                _ => null,
              },
            ),
            if (i < computed.macroRows.length - 1) const SizedBox(height: 12),
          ],
        ],
      ),
    );
  }

  Widget _buildMicronutrientsCard(
      ThemeData theme, FoodDetailComputedData computed) {
    final baseBlue = theme.colorScheme.primary;
    final addBlue = baseBlue.withValues(alpha: 0.45);

    return GlassCard(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Complete Nutrient Summary',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                'Show all',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                ),
              ),
              Switch(
                value: _showAllNutrients,
                onChanged: (value) {
                  setState(() {
                    _showAllNutrients = value;
                  });
                },
              ),
            ],
          ),
          if (computed.showCoverageHint) ...[
            const SizedBox(height: 4),
            Text(
              'Some logged foods are label-only, so micronutrient totals may be understated.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
          ],
          const SizedBox(height: 8),
          if (computed.micronutrientSections.isEmpty)
            Text(
              'No nutrient details available for this food.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            )
          else
            for (var i = 0; i < computed.micronutrientSections.length; i++) ...[
              Text(
                computed.micronutrientSections[i].title.toUpperCase(),
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                  letterSpacing: 0.8,
                ),
              ),
              const SizedBox(height: 8),
              for (var rowIndex = 0;
                  rowIndex < computed.micronutrientSections[i].rows.length;
                  rowIndex++) ...[
                _NutrientProgressRow(
                  row: computed.micronutrientSections[i].rows[rowIndex],
                  barColor: baseBlue,
                  addedColor: addBlue,
                  formatter: _formatCompactValue,
                ),
                if (rowIndex <
                    computed.micronutrientSections[i].rows.length - 1)
                  const SizedBox(height: 8),
              ],
              if (i < computed.micronutrientSections.length - 1)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Divider(height: 1),
                ),
            ],
        ],
      ),
    );
  }
}

class _NutrientProgressRow extends StatelessWidget {
  const _NutrientProgressRow({
    required this.row,
    required this.barColor,
    required this.addedColor,
    required this.formatter,
    this.icon,
  });

  final NutrientProgressRowData row;
  final Color barColor;
  final Color addedColor;
  final String Function(double value, String unit) formatter;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isNegativeDelta = row.add < 0;
    final baseProgress =
        isNegativeDelta ? row.projectedProgress : row.currentProgress;
    final projectedProgress =
        isNegativeDelta ? row.currentProgress : row.projectedProgress;
    final rightText = row.hasTarget
        ? '${(row.projectedProgress * 100).round()}%'
        : 'No target';
    final middleText = row.hasTarget
        ? '${formatter(row.current, row.unit)} / ${formatter(row.target ?? 0, row.unit)}'
        : formatter(row.current, row.unit);
    final addMagnitude = formatter(row.add.abs(), row.unit);
    final addText = row.add > 0
        ? '+$addMagnitude'
        : row.add < 0
            ? '-$addMagnitude'
            : addMagnitude;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (icon != null) ...[
              Icon(icon, size: 15, color: barColor.withValues(alpha: 0.92)),
              const SizedBox(width: 6),
            ],
            Expanded(
              child: Text(
                row.label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            Text(
              rightText,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 3),
        Text(
          '$middleText • $addText',
          style: theme.textTheme.bodySmall?.copyWith(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
          ),
        ),
        const SizedBox(height: 6),
        LayeredProgressBar(
          baseProgress: baseProgress,
          projectedProgress: projectedProgress,
          baseColor: barColor,
          addedColor: isNegativeDelta
              ? theme.colorScheme.error.withValues(alpha: 0.45)
              : addedColor,
          height: 8,
        ),
      ],
    );
  }
}

enum _FoodNumberPadMode {
  decimal,
}

Future<String?> _showFoodNumberPad({
  required BuildContext context,
  required String title,
  required String initialValue,
  required _FoodNumberPadMode mode,
  required ValueChanged<String> onChanged,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.transparent,
    enableDrag: false,
    requestFocus: false,
    builder: (_) => _FoodNumberPadSheet(
      title: title,
      initialValue: initialValue,
      mode: mode,
      onChanged: onChanged,
    ),
  );
}

class _FoodNumberPadSheet extends StatefulWidget {
  const _FoodNumberPadSheet({
    required this.title,
    required this.initialValue,
    required this.mode,
    required this.onChanged,
  });

  final String title;
  final String initialValue;
  final _FoodNumberPadMode mode;
  final ValueChanged<String> onChanged;

  @override
  State<_FoodNumberPadSheet> createState() => _FoodNumberPadSheetState();
}

class _FoodNumberPadSheetState extends State<_FoodNumberPadSheet> {
  late String _rawValue;
  late bool _replacePending;

  @override
  void initState() {
    super.initState();
    _rawValue = widget.initialValue.trim();
    _replacePending = _rawValue.isNotEmpty;
  }

  void _append(String char) {
    setState(() {
      if (_replacePending) {
        _rawValue = '';
        _replacePending = false;
      }
      if (char == '.') {
        if (widget.mode != _FoodNumberPadMode.decimal ||
            _rawValue.contains('.')) {
          return;
        }
        _rawValue = _rawValue.isEmpty ? '0.' : '$_rawValue.';
        return;
      }
      if (_rawValue == '0') {
        _rawValue = char;
      } else {
        _rawValue += char;
      }
    });
    widget.onChanged(_rawValue);
  }

  void _backspace() {
    if (_replacePending) {
      setState(() {
        _rawValue = '';
        _replacePending = false;
      });
      widget.onChanged(_rawValue);
      return;
    }
    if (_rawValue.isEmpty) return;
    setState(() {
      _rawValue = _rawValue.substring(0, _rawValue.length - 1);
    });
    widget.onChanged(_rawValue);
  }

  void _clear() {
    setState(() {
      _rawValue = '';
      _replacePending = false;
    });
    widget.onChanged(_rawValue);
  }

  Widget _keyButton(
    BuildContext context,
    String label, {
    required VoidCallback onPressed,
    Color? backgroundColor,
    Color? foregroundColor,
  }) {
    final theme = Theme.of(context);
    return Expanded(
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: SizedBox(
          height: 56,
          child: ElevatedButton(
            onPressed: onPressed,
            style: ElevatedButton.styleFrom(
              elevation: 0,
              backgroundColor: backgroundColor ??
                  theme.colorScheme.surface.withValues(alpha: 0.74),
              foregroundColor: foregroundColor ?? theme.colorScheme.onSurface,
              shadowColor: Colors.transparent,
              side: BorderSide(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.12),
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: label == '⌫'
                ? const Icon(Icons.backspace_outlined, size: 20)
                : Text(
                    label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final supportsDecimal = widget.mode == _FoodNumberPadMode.decimal;
    final keypadPanelTopColor =
        theme.colorScheme.surface.withValues(alpha: 0.66);
    final keypadPanelBottomColor =
        theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5);
    final keypadPanelBorderColor =
        theme.colorScheme.outline.withValues(alpha: 0.18);

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: ClipRRect(
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(28),
          ),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    keypadPanelTopColor,
                    keypadPanelBottomColor,
                  ],
                ),
                borderRadius: const BorderRadius.vertical(
                  top: Radius.circular(28),
                ),
                border: Border.all(color: keypadPanelBorderColor),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    widget.title,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _keyButton(context, '1', onPressed: () => _append('1')),
                      _keyButton(context, '2', onPressed: () => _append('2')),
                      _keyButton(context, '3', onPressed: () => _append('3')),
                    ],
                  ),
                  Row(
                    children: [
                      _keyButton(context, '4', onPressed: () => _append('4')),
                      _keyButton(context, '5', onPressed: () => _append('5')),
                      _keyButton(context, '6', onPressed: () => _append('6')),
                    ],
                  ),
                  Row(
                    children: [
                      _keyButton(context, '7', onPressed: () => _append('7')),
                      _keyButton(context, '8', onPressed: () => _append('8')),
                      _keyButton(context, '9', onPressed: () => _append('9')),
                    ],
                  ),
                  Row(
                    children: [
                      _keyButton(
                        context,
                        supportsDecimal ? '.' : 'C',
                        onPressed:
                            supportsDecimal ? () => _append('.') : _clear,
                      ),
                      _keyButton(context, '0', onPressed: () => _append('0')),
                      _keyButton(context, '⌫', onPressed: _backspace),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      _keyButton(
                        context,
                        'Cancel',
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      _keyButton(
                        context,
                        'OK',
                        onPressed: () => Navigator.of(context).pop(_rawValue),
                        backgroundColor: theme.colorScheme.primary,
                        foregroundColor: theme.colorScheme.surface,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
