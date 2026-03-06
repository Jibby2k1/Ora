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
    final db = await _db.database;
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
  }

  Future<void> purgeExpired() async {
    final db = await _db.database;
    await db.delete(
      'food_cache',
      where: 'expires_at <= ?',
      whereArgs: [DateTime.now().toIso8601String()],
    );
  }

  Future<void> delete(String cacheKey) async {
    final db = await _db.database;
    await db.delete(
      'food_cache',
      where: 'cache_key = ?',
      whereArgs: [cacheKey],
    );
  }
}
