import '../../data/db/db.dart';
import '../../data/repositories/settings_repo.dart';
import '../models/diet_goal_settings.dart';

class DietGoalSettingsService {
  DietGoalSettingsService(AppDatabase db) : _settingsRepo = SettingsRepo(db);

  final SettingsRepo _settingsRepo;

  static const String _modeKey = 'diet_goal_mode';

  static const String _manualProteinKey = 'diet_goal_manual_protein';
  static const String _manualCarbsKey = 'diet_goal_manual_carbs';
  static const String _manualFatKey = 'diet_goal_manual_fat';

  static const String _percentCaloriesKey = 'diet_goal_percent_calories';
  static const String _percentProteinKey = 'diet_goal_percent_protein';
  static const String _percentCarbsKey = 'diet_goal_percent_carbs';
  static const String _percentFatKey = 'diet_goal_percent_fat';

  static const String _optimalCaloriesKey = 'diet_goal_optimal_calories';
  static const String _optimalTypeKey = 'diet_goal_optimal_type';

  static const String _activeCaloriesKey = 'diet_goal_calories';
  static const String _activeProteinKey = 'diet_goal_protein';
  static const String _activeCarbsKey = 'diet_goal_carbs';
  static const String _activeFatKey = 'diet_goal_fat';

  Future<DietGoalSettings> load() async {
    final mode =
        DietGoalModeX.fromStorage(await _settingsRepo.getValue(_modeKey));

    final fallbackCalories =
        _readPositive(await _settingsRepo.getValue(_activeCaloriesKey), 2500);
    final fallbackProtein =
        _readPositive(await _settingsRepo.getValue(_activeProteinKey), 180);
    final fallbackCarbs =
        _readPositive(await _settingsRepo.getValue(_activeCarbsKey), 250);
    final fallbackFat =
        _readPositive(await _settingsRepo.getValue(_activeFatKey), 70);

    final manualProtein = _readPositive(
        await _settingsRepo.getValue(_manualProteinKey), fallbackProtein);
    final manualCarbs = _readPositive(
        await _settingsRepo.getValue(_manualCarbsKey), fallbackCarbs);
    final manualFat =
        _readPositive(await _settingsRepo.getValue(_manualFatKey), fallbackFat);

    final percentCalories = _readPositive(
        await _settingsRepo.getValue(_percentCaloriesKey), fallbackCalories);
    final percentProtein =
        _readNonNegative(await _settingsRepo.getValue(_percentProteinKey), 30);
    final percentCarbs =
        _readNonNegative(await _settingsRepo.getValue(_percentCarbsKey), 40);
    final percentFat =
        _readNonNegative(await _settingsRepo.getValue(_percentFatKey), 30);

    final optimalCalories = _readPositive(
        await _settingsRepo.getValue(_optimalCaloriesKey), fallbackCalories);
    final optimalType = DietOptimalGoalTypeX.fromStorage(
        await _settingsRepo.getValue(_optimalTypeKey));

    return DietGoalSettings(
      mode: mode,
      manualProteinG: manualProtein,
      manualCarbsG: manualCarbs,
      manualFatG: manualFat,
      percentageCalories: percentCalories,
      percentageProtein: percentProtein,
      percentageCarbs: percentCarbs,
      percentageFat: percentFat,
      optimalCalories: optimalCalories,
      optimalGoalType: optimalType,
    );
  }

  Future<void> save(DietGoalSettings settings) async {
    await _settingsRepo.setValue(_modeKey, settings.mode.storageValue);

    await _settingsRepo.setValue(
      _manualProteinKey,
      settings.manualProteinG.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _manualCarbsKey,
      settings.manualCarbsG.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _manualFatKey,
      settings.manualFatG.toStringAsFixed(2),
    );

    await _settingsRepo.setValue(
      _percentCaloriesKey,
      settings.percentageCalories.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _percentProteinKey,
      settings.percentageProtein.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _percentCarbsKey,
      settings.percentageCarbs.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _percentFatKey,
      settings.percentageFat.toStringAsFixed(2),
    );

    await _settingsRepo.setValue(
      _optimalCaloriesKey,
      settings.optimalCalories.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _optimalTypeKey,
      settings.optimalGoalType.storageValue,
    );

    final effective = settings.effectiveTargetsForMode(settings.mode);
    await _settingsRepo.setValue(
      _activeCaloriesKey,
      effective.calories.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _activeProteinKey,
      effective.proteinG.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _activeCarbsKey,
      effective.carbsG.toStringAsFixed(2),
    );
    await _settingsRepo.setValue(
      _activeFatKey,
      effective.fatG.toStringAsFixed(2),
    );
  }

  double _readPositive(String? raw, double fallback) {
    final parsed = double.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed <= 0) return fallback;
    return parsed;
  }

  double _readNonNegative(String? raw, double fallback) {
    final parsed = double.tryParse(raw?.trim() ?? '');
    if (parsed == null || parsed < 0) return fallback;
    return parsed;
  }
}
