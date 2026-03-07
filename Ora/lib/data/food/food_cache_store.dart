import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class FoodCacheStore {
  FoodCacheStore(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getJson(
    String cacheKey, {
    int expectedSchemaVersion = 1,
  }) async {
    return _runWithTableReady<Map<String, dynamic>?>((db) async {
      final rows = await db.query(
        'food_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
        limit: 1,
      );
      if (rows.isEmpty) return null;
      final row = rows.first;

      final schemaVersion = (row['schema_version'] as int?) ?? 1;
      if (schemaVersion != expectedSchemaVersion) {
        await db.delete(
          'food_cache',
          where: 'cache_key = ?',
          whereArgs: [cacheKey],
        );
        return null;
      }

      final expiresAtRaw = row['expires_at']?.toString();
      final expiresAt =
          expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw);
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await db.delete(
          'food_cache',
          where: 'cache_key = ?',
          whereArgs: [cacheKey],
        );
        return null;
      }

      final payload = row['payload_json']?.toString();
      if (payload == null || payload.isEmpty) return null;

      final decoded = jsonDecode(payload);
      if (decoded is Map<String, dynamic>) {
        return decoded;
      }
      if (decoded is Map) {
        return Map<String, dynamic>.from(decoded);
      }
      return null;
    });
  }

  Future<void> setJson(
    String cacheKey,
    Map<String, dynamic> json, {
    Duration ttl = const Duration(days: 7),
    int schemaVersion = 1,
  }) async {
    await _runWithTableReady<void>((db) async {
      final now = DateTime.now();
      final expiresAt = now.add(ttl);
      await db.insert(
        'food_cache',
        {
          'cache_key': cacheKey,
          'payload_json': jsonEncode(json),
          'updated_at': now.toIso8601String(),
          'expires_at': expiresAt.toIso8601String(),
          'schema_version': schemaVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      );
    });
  }

  Future<void> purgeExpired() async {
    await _runWithTableReady<void>((db) async {
      await db.delete(
        'food_cache',
        where: 'expires_at <= ?',
        whereArgs: [DateTime.now().toIso8601String()],
      );
    });
  }

  Future<void> delete(String cacheKey) async {
    await _runWithTableReady<void>((db) async {
      await db.delete(
        'food_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      );
    });
  }

  Future<T> _runWithTableReady<T>(
    Future<T> Function(Database db) action,
  ) async {
    final db = await _db.database;
    try {
      return await action(db);
    } on DatabaseException catch (error) {
      if (!_isMissingFoodCacheTable(error)) {
        rethrow;
      }
      await _ensureFoodCacheTable(db);
      return action(db);
    }
  }

  bool _isMissingFoodCacheTable(DatabaseException error) {
    final message = error.toString().toLowerCase();
    return message.contains('no such table') && message.contains('food_cache');
  }

  Future<void> _ensureFoodCacheTable(Database db) async {
    await db.execute('''
CREATE TABLE IF NOT EXISTS food_cache(
  cache_key TEXT PRIMARY KEY,
  payload_json TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  expires_at TEXT NOT NULL,
  schema_version INTEGER NOT NULL DEFAULT 1
);
''');
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_food_cache_expires ON food_cache(expires_at);',
    );
  }
}
