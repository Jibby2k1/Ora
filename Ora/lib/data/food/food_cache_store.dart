import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/db.dart';
import '../db/schema.dart';

class FoodCacheStore {
  FoodCacheStore(this._db);

  final AppDatabase _db;

  Future<Map<String, dynamic>?> getJson(
    String cacheKey, {
    int expectedSchemaVersion = 1,
  }) async {
    final rows = await _runRead<List<Map<String, Object?>>?>(
      (db) => db.query(
        'food_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
        limit: 1,
      ),
    );
    if (rows == null || rows.isEmpty) return null;
    final row = rows.first;

    try {
      final schemaVersion = (row['schema_version'] as int?) ?? 1;
      if (schemaVersion != expectedSchemaVersion) {
        await delete(cacheKey);
        return null;
      }

      final expiresAtRaw = row['expires_at']?.toString();
      final expiresAt =
          expiresAtRaw == null ? null : DateTime.tryParse(expiresAtRaw);
      if (expiresAt != null && DateTime.now().isAfter(expiresAt)) {
        await delete(cacheKey);
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
    } catch (_) {
      return null;
    }
    return null;
  }

  Future<void> setJson(
    String cacheKey,
    Map<String, dynamic> json, {
    Duration ttl = const Duration(days: 7),
    int schemaVersion = 1,
  }) async {
    final db = await _db.database;
    final now = DateTime.now();
    final expiresAt = now.add(ttl);
    await _runWrite(
      db: db,
      action: (database) => database.insert(
        'food_cache',
        {
          'cache_key': cacheKey,
          'payload_json': jsonEncode(json),
          'updated_at': now.toIso8601String(),
          'expires_at': expiresAt.toIso8601String(),
          'schema_version': schemaVersion,
        },
        conflictAlgorithm: ConflictAlgorithm.replace,
      ),
    );
  }

  Future<void> purgeExpired() async {
    final db = await _db.database;
    await _runWrite(
      db: db,
      action: (database) => database.delete(
        'food_cache',
        where: 'expires_at <= ?',
        whereArgs: [DateTime.now().toIso8601String()],
      ),
    );
  }

  Future<void> delete(String cacheKey) async {
    final db = await _db.database;
    await _runWrite(
      db: db,
      action: (database) => database.delete(
        'food_cache',
        where: 'cache_key = ?',
        whereArgs: [cacheKey],
      ),
    );
  }

  Future<T?> _runRead<T>(
    Future<T> Function(Database db) action,
  ) async {
    final db = await _db.database;
    try {
      return await action(db);
    } on DatabaseException catch (error) {
      if (_isRecoverableCacheError(error)) {
        await _recreateCacheTable(db);
        try {
          return await action(db);
        } catch (_) {
          return null;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  Future<void> _runWrite({
    required Database db,
    required Future<Object?> Function(Database db) action,
  }) async {
    try {
      await action(db);
    } on DatabaseException catch (error) {
      if (_isRecoverableCacheError(error)) {
        await _recreateCacheTable(db);
        try {
          await action(db);
        } catch (_) {}
      }
    } catch (_) {}
  }

  bool _isRecoverableCacheError(DatabaseException error) {
    final message = error.toString().toLowerCase();
    if (!message.contains('food_cache')) return false;
    return message.contains('no such table') ||
        message.contains('no such column') ||
        message.contains('has no column named');
  }

  Future<void> _recreateCacheTable(Database db) async {
    await db.execute('DROP TABLE IF EXISTS food_cache;');
    await db.execute(createTableFoodCache);
    await db.execute(
      'CREATE INDEX IF NOT EXISTS idx_food_cache_expires ON food_cache(expires_at);',
    );
  }
}
