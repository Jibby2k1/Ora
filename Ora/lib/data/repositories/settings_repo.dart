import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

enum CloudModelTask {
  inputRouting,
  voiceCommandParsing,
  programInterpretation,
  documentImageAnalysis,
  exerciseEnrichment,
}

extension CloudModelTaskMeta on CloudModelTask {
  String get label {
    switch (this) {
      case CloudModelTask.inputRouting:
        return 'Input routing';
      case CloudModelTask.voiceCommandParsing:
        return 'Voice command parsing';
      case CloudModelTask.programInterpretation:
        return 'Program interpretation';
      case CloudModelTask.documentImageAnalysis:
        return 'Document + image analysis';
      case CloudModelTask.exerciseEnrichment:
        return 'Exercise enrichment';
    }
  }

  String get description {
    switch (this) {
      case CloudModelTask.inputRouting:
        return 'Classifies Orb text/file/camera inputs into app intents.';
      case CloudModelTask.voiceCommandParsing:
        return 'Parses workout voice commands during sessions.';
      case CloudModelTask.programInterpretation:
        return 'Extracts structured plans from uploaded program files.';
      case CloudModelTask.documentImageAnalysis:
        return 'Runs deeper cloud analysis for uploaded docs and images.';
      case CloudModelTask.exerciseEnrichment:
        return 'Infers muscles and metadata for exercises.';
    }
  }
}

class SettingsRepo {
  SettingsRepo(this._db);

  final AppDatabase _db;

  static const String keyUnit = 'unit';
  static const String keyIncrement = 'increment';
  static const String keyRestDefault = 'rest_default';
  static const String keyVoiceEnabled = 'voice_enabled';
  static const String keyHeightUnit = 'height_unit';
  static const String keyWakeWordEnabled = 'wake_word_enabled';
  static const String keyCloudEnabled = 'cloud_enabled';
  static const String keyCloudApiKey = 'cloud_api_key';
  static const String keyCloudApiKeyPresent = 'cloud_api_key_present';
  static const String keyCloudModel = 'cloud_model';
  static const String keyCloudModelInputRouting = 'cloud_model_input_routing';
  static const String keyCloudModelVoiceCommandParsing =
      'cloud_model_voice_command_parsing';
  static const String keyCloudModelProgramInterpretation =
      'cloud_model_program_interpretation';
  static const String keyCloudModelDocumentImageAnalysis =
      'cloud_model_document_image_analysis';
  static const String keyCloudModelExerciseEnrichment =
      'cloud_model_exercise_enrichment';
  static const String keyCloudProvider = 'cloud_provider';
  static const String keyCloudConsentDiet = 'cloud_consent_diet';
  static const String keyCloudConsentAppearance = 'cloud_consent_appearance';
  static const String keyCloudConsentLeaderboard = 'cloud_consent_leaderboard';
  static const String keyAppearanceProfileEnabled =
      'appearance_profile_enabled';
  static const String keyAppearanceProfileSex = 'appearance_profile_sex';
  static const String keyAppearanceAccessEnabled = 'appearance_access_enabled';
  static const String keyOrbHidden = 'orb_hidden';
  static const String keyOrbDocked = 'orb_docked';
  static const String keyOrbPosX = 'orb_pos_x';
  static const String keyOrbPosY = 'orb_pos_y';
  static const String keyProfileAvatarPath = 'profile_avatar_path';
  static const String keySnackbarHighContrast = 'snackbar_high_contrast';

  static const List<CloudModelTask> configurableCloudModelTasks = [
    CloudModelTask.programInterpretation,
    CloudModelTask.documentImageAnalysis,
    CloudModelTask.inputRouting,
    CloudModelTask.voiceCommandParsing,
    CloudModelTask.exerciseEnrichment,
  ];

  Future<String> getUnit() async {
    return (await _get(keyUnit)) ?? 'lb';
  }

  Future<void> setUnit(String unit) async {
    await _set(keyUnit, unit);
  }

  Future<double> getIncrement() async {
    final raw = await _get(keyIncrement);
    return double.tryParse(raw ?? '') ?? 2.5;
  }

  Future<void> setIncrement(double value) async {
    await _set(keyIncrement, value.toString());
  }

  Future<int> getRestDefault() async {
    final raw = await _get(keyRestDefault);
    return int.tryParse(raw ?? '') ?? 120;
  }

  Future<void> setRestDefault(int value) async {
    await _set(keyRestDefault, value.toString());
  }

  Future<bool> getVoiceEnabled() async {
    final raw = await _get(keyVoiceEnabled);
    return raw == null ? true : raw == '1';
  }

  Future<void> setVoiceEnabled(bool enabled) async {
    await _set(keyVoiceEnabled, enabled ? '1' : '0');
  }

  Future<bool> getWakeWordEnabled() async {
    final raw = await _get(keyWakeWordEnabled);
    return raw == '1';
  }

  Future<void> setWakeWordEnabled(bool enabled) async {
    await _set(keyWakeWordEnabled, enabled ? '1' : '0');
  }

  Future<String> getHeightUnit() async {
    return (await _get(keyHeightUnit)) ?? 'cm';
  }

  Future<void> setHeightUnit(String unit) async {
    await _set(keyHeightUnit, unit);
  }

  Future<bool> getCloudEnabled() async {
    final raw = await _get(keyCloudEnabled);
    if (raw == null) return true;
    return raw == '1';
  }

  Future<void> setCloudEnabled(bool enabled) async {
    await _set(keyCloudEnabled, enabled ? '1' : '0');
  }

  Future<String?> getCloudApiKey() async {
    if (_supportsSecureStorage()) {
      final marker = await _get(keyCloudApiKeyPresent);
      final legacy = await _get(keyCloudApiKey);
      if (marker != '1' && (legacy == null || legacy.trim().isEmpty)) {
        return null;
      }
      final secure = await _secureStorage.read(key: keyCloudApiKey);
      if (secure != null && secure.trim().isNotEmpty) {
        await _set(keyCloudApiKeyPresent, '1');
        return secure.trim();
      }
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _secureStorage.write(key: keyCloudApiKey, value: legacy.trim());
        await _delete(keyCloudApiKey);
        await _set(keyCloudApiKeyPresent, '1');
        return legacy.trim();
      }
      await _set(keyCloudApiKeyPresent, '0');
      return null;
    }
    return _get(keyCloudApiKey);
  }

  Future<bool> hasCloudApiKey() async {
    if (!_supportsSecureStorage()) {
      final raw = await _get(keyCloudApiKey);
      return raw != null && raw.trim().isNotEmpty;
    }
    if ((await _get(keyCloudApiKeyPresent)) == '1') {
      return true;
    }
    final legacy = await _get(keyCloudApiKey);
    if (legacy != null && legacy.trim().isNotEmpty) {
      await _set(keyCloudApiKeyPresent, '1');
      return true;
    }
    return false;
  }

  Future<void> setCloudApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      if (_supportsSecureStorage()) {
        await _secureStorage.delete(key: keyCloudApiKey);
      } else {
        await _delete(keyCloudApiKey);
      }
      await _set(keyCloudApiKeyPresent, '0');
      return;
    }
    if (_supportsSecureStorage()) {
      await _secureStorage.write(key: keyCloudApiKey, value: apiKey.trim());
      await _delete(keyCloudApiKey);
    } else {
      await _set(keyCloudApiKey, apiKey.trim());
    }
    await _set(keyCloudApiKeyPresent, '1');
  }

  Future<String> getCloudModel() async {
    return (await _get(keyCloudModel)) ?? 'gemini-2.5-pro';
  }

  Future<void> setCloudModel(String model) async {
    await _set(keyCloudModel, model.trim());
  }

  Future<String> getCloudModelForTask(CloudModelTask task) async {
    final raw = await _get(_cloudModelTaskKey(task));
    if (raw != null && raw.trim().isNotEmpty) {
      return raw.trim();
    }
    final provider = await getCloudProvider();
    return defaultCloudModelForTask(provider: provider, task: task);
  }

  Future<void> setCloudModelForTask(CloudModelTask task, String model) async {
    await _set(_cloudModelTaskKey(task), model.trim());
  }

  String _cloudModelTaskKey(CloudModelTask task) {
    switch (task) {
      case CloudModelTask.inputRouting:
        return keyCloudModelInputRouting;
      case CloudModelTask.voiceCommandParsing:
        return keyCloudModelVoiceCommandParsing;
      case CloudModelTask.programInterpretation:
        return keyCloudModelProgramInterpretation;
      case CloudModelTask.documentImageAnalysis:
        return keyCloudModelDocumentImageAnalysis;
      case CloudModelTask.exerciseEnrichment:
        return keyCloudModelExerciseEnrichment;
    }
  }

  static String defaultCloudModelForTask({
    required String provider,
    required CloudModelTask task,
  }) {
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider == 'openai') {
      switch (task) {
        case CloudModelTask.programInterpretation:
          return 'gpt-5-mini';
        case CloudModelTask.documentImageAnalysis:
          return 'gpt-5';
        case CloudModelTask.inputRouting:
          return 'gpt-5-mini';
        case CloudModelTask.voiceCommandParsing:
          return 'gpt-5-mini';
        case CloudModelTask.exerciseEnrichment:
          return 'gpt-5-mini';
      }
    }
    switch (task) {
      case CloudModelTask.programInterpretation:
        return 'gemini-2.0-flash';
      case CloudModelTask.documentImageAnalysis:
        return 'gemini-2.5-pro';
      case CloudModelTask.inputRouting:
        return 'gemini-2.0-flash';
      case CloudModelTask.voiceCommandParsing:
        return 'gemini-2.0-flash';
      case CloudModelTask.exerciseEnrichment:
        return 'gemini-2.0-flash';
    }
  }

  static List<String> cloudModelOptionsForTask({
    required String provider,
    required CloudModelTask task,
  }) {
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider == 'openai') {
      switch (task) {
        case CloudModelTask.programInterpretation:
          return const ['gpt-5-mini', 'gpt-5', 'gpt-5-nano', 'gpt-4o'];
        case CloudModelTask.documentImageAnalysis:
          return const ['gpt-5', 'gpt-5-mini', 'gpt-4o'];
        case CloudModelTask.inputRouting:
          return const ['gpt-5-mini', 'gpt-5-nano', 'gpt-4o-mini', 'gpt-4o'];
        case CloudModelTask.voiceCommandParsing:
          return const ['gpt-5-mini', 'gpt-5-nano', 'gpt-4o-mini', 'gpt-4o'];
        case CloudModelTask.exerciseEnrichment:
          return const ['gpt-5-mini', 'gpt-5-nano', 'gpt-4o-mini', 'gpt-4o'];
      }
    }
    switch (task) {
      case CloudModelTask.programInterpretation:
        return const ['gemini-2.0-flash', 'gemini-2.5-pro', 'gemini-1.5-flash'];
      case CloudModelTask.documentImageAnalysis:
        return const ['gemini-2.5-pro', 'gemini-2.0-flash', 'gemini-1.5-flash'];
      case CloudModelTask.inputRouting:
        return const ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-2.5-pro'];
      case CloudModelTask.voiceCommandParsing:
        return const ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-2.5-pro'];
      case CloudModelTask.exerciseEnrichment:
        return const ['gemini-2.0-flash', 'gemini-1.5-flash', 'gemini-2.5-pro'];
    }
  }

  Future<String> getCloudProvider() async {
    return (await _get(keyCloudProvider)) ?? 'gemini';
  }

  Future<void> setCloudProvider(String provider) async {
    await _set(keyCloudProvider, provider.trim());
  }

  Future<bool> getCloudConsentDiet() async {
    final raw = await _get(keyCloudConsentDiet);
    return raw == '1';
  }

  Future<void> setCloudConsentDiet(bool value) async {
    await _set(keyCloudConsentDiet, value ? '1' : '0');
  }

  Future<bool> getCloudConsentAppearance() async {
    final raw = await _get(keyCloudConsentAppearance);
    return raw == '1';
  }

  Future<void> setCloudConsentAppearance(bool value) async {
    await _set(keyCloudConsentAppearance, value ? '1' : '0');
  }

  Future<bool> getCloudConsentLeaderboard() async {
    final raw = await _get(keyCloudConsentLeaderboard);
    return raw == '1';
  }

  Future<void> setCloudConsentLeaderboard(bool value) async {
    await _set(keyCloudConsentLeaderboard, value ? '1' : '0');
  }

  Future<bool> getAppearanceProfileEnabled() async {
    final raw = await _get(keyAppearanceProfileEnabled);
    return raw == '1';
  }

  Future<void> setAppearanceProfileEnabled(bool value) async {
    await _set(keyAppearanceProfileEnabled, value ? '1' : '0');
  }

  Future<String> getAppearanceProfileSex() async {
    return (await _get(keyAppearanceProfileSex)) ?? 'neutral';
  }

  Future<void> setAppearanceProfileSex(String value) async {
    await _set(keyAppearanceProfileSex, value.trim());
  }

  Future<bool?> getAppearanceAccessEnabled() async {
    final raw = await _get(keyAppearanceAccessEnabled);
    if (raw == null) return null;
    return raw == '1';
  }

  Future<void> setAppearanceAccessEnabled(bool value) async {
    await _set(keyAppearanceAccessEnabled, value ? '1' : '0');
  }

  Future<bool> getOrbHidden() async {
    final raw = await _get(keyOrbHidden);
    return raw == '1';
  }

  Future<String?> getProfileAvatarPath() async {
    return _get(keyProfileAvatarPath);
  }

  Future<void> setProfileAvatarPath(String? path) async {
    if (path == null || path.trim().isEmpty) {
      await _delete(keyProfileAvatarPath);
      return;
    }
    await _set(keyProfileAvatarPath, path.trim());
  }

  Future<bool> getSnackbarHighContrast() async {
    final raw = await _get(keySnackbarHighContrast);
    if (raw == null) return true;
    return raw == '1';
  }

  Future<void> setSnackbarHighContrast(bool value) async {
    await _set(keySnackbarHighContrast, value ? '1' : '0');
  }

  Future<void> setOrbHidden(bool value) async {
    await _set(keyOrbHidden, value ? '1' : '0');
  }

  Future<bool> getOrbDocked() async {
    final raw = await _get(keyOrbDocked);
    return raw == null ? true : raw == '1';
  }

  Future<void> setOrbDocked(bool value) async {
    await _set(keyOrbDocked, value ? '1' : '0');
  }

  Future<double?> getOrbPosX() async {
    final raw = await _get(keyOrbPosX);
    return raw == null ? null : double.tryParse(raw);
  }

  Future<double?> getOrbPosY() async {
    final raw = await _get(keyOrbPosY);
    return raw == null ? null : double.tryParse(raw);
  }

  Future<void> setOrbPosition({required double x, required double y}) async {
    await _set(keyOrbPosX, x.toStringAsFixed(4));
    await _set(keyOrbPosY, y.toStringAsFixed(4));
  }

  Future<String?> getValue(String key) async {
    return _get(key);
  }

  Future<void> setValue(String key, String value) async {
    await _set(key, value);
  }

  Future<String?> _get(String key) async {
    final db = await _db.database;
    final rows = await db.query(
      'app_setting',
      columns: ['value'],
      where: 'key = ?',
      whereArgs: [key],
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return rows.first['value'] as String?;
  }

  Future<void> _set(String key, String value) async {
    final db = await _db.database;
    await db.insert(
      'app_setting',
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  Future<void> _delete(String key) async {
    final db = await _db.database;
    await db.delete('app_setting', where: 'key = ?', whereArgs: [key]);
  }

  bool _supportsSecureStorage() {
    return Platform.isAndroid || Platform.isIOS;
  }

  FlutterSecureStorage get _secureStorage => const FlutterSecureStorage();
}
