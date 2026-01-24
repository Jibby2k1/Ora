import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
  static const String keyCloudConsentDiet = 'cloud_consent_diet';
  static const String keyCloudConsentAppearance = 'cloud_consent_appearance';
  static const String keyCloudConsentLeaderboard = 'cloud_consent_leaderboard';
  static const String keyAppearanceProfileEnabled = 'appearance_profile_enabled';
  static const String keyAppearanceProfileSex = 'appearance_profile_sex';
  static const String keyAppearanceAccessEnabled = 'appearance_access_enabled';

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
    if (_supportsSecureStorage()) {
      final secure = await _secureStorage.read(key: keyCloudApiKey);
      if (secure != null && secure.trim().isNotEmpty) {
        return secure.trim();
      }
      final legacy = await _get(keyCloudApiKey);
      if (legacy != null && legacy.trim().isNotEmpty) {
        await _secureStorage.write(key: keyCloudApiKey, value: legacy.trim());
        await _delete(keyCloudApiKey);
        return legacy.trim();
      }
      return null;
    }
    return _get(keyCloudApiKey);
  }

  Future<void> setCloudApiKey(String? apiKey) async {
    if (apiKey == null || apiKey.trim().isEmpty) {
      if (_supportsSecureStorage()) {
        await _secureStorage.delete(key: keyCloudApiKey);
      } else {
        await _delete(keyCloudApiKey);
      }
      return;
    }
    if (_supportsSecureStorage()) {
      await _secureStorage.write(key: keyCloudApiKey, value: apiKey.trim());
      await _delete(keyCloudApiKey);
    } else {
      await _set(keyCloudApiKey, apiKey.trim());
    }
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
