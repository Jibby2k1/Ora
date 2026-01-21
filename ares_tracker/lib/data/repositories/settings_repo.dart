import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

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
  static const String keyCloudModel = 'cloud_model';
  static const String keyCloudProvider = 'cloud_provider';

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
    return raw == '1';
  }

  Future<void> setCloudEnabled(bool enabled) async {
    await _set(keyCloudEnabled, enabled ? '1' : '0');
  }

  Future<String?> getCloudApiKey() async {
    return _get(keyCloudApiKey);
  }

  Future<void> setCloudApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      await _delete(keyCloudApiKey);
      return;
    }
    await _set(keyCloudApiKey, apiKey.trim());
  }

  Future<String> getCloudModel() async {
    return (await _get(keyCloudModel)) ?? 'gemini-2.5-pro';
  }

  Future<void> setCloudModel(String model) async {
    await _set(keyCloudModel, model.trim());
  }

  Future<String> getCloudProvider() async {
    return (await _get(keyCloudProvider)) ?? 'gemini';
  }

  Future<void> setCloudProvider(String provider) async {
    await _set(keyCloudProvider, provider.trim());
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
}
