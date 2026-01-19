import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import 'migrations/m0001_init.dart';
import 'migrations/m0002_set_blocks.dart';
import 'schema.dart';

class AppDatabase {
  static final AppDatabase instance = AppDatabase._();

  AppDatabase._();

  Database? _db;

  Future<Database> get database async {
    if (_db != null) return _db!;
    _db = await _open();
    return _db!;
  }

  Future<Database> _open() async {
    if (kIsWeb) {
      throw Exception('Web is not supported for local SQLite in this demo. Use desktop or mobile.');
    }
    final Directory dir = await getApplicationDocumentsDirectory();
    final String path = p.join(dir.path, dbName);

    return openDatabase(
      path,
      version: dbVersion,
      onCreate: (db, version) async {
        await _runMigrations(db, 0, version);
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        await _runMigrations(db, oldVersion, newVersion);
      },
    );
  }

  Future<void> _runMigrations(Database db, int from, int to) async {
    final batches = <List<String>>[];
    if (from < 1 && to >= 1) {
      batches.add(migration0001());
    }
    if (from < 2 && to >= 2) {
      batches.add(migration0002());
    }

    for (final statements in batches) {
      final batch = db.batch();
      for (final sql in statements) {
        batch.execute(sql);
      }
      await batch.commit(noResult: true);
    }
  }

  Future<void> seedExercisesIfNeeded(String jsonAssetOrPath, {bool fromAsset = true}) async {
    final db = await database;
    final count = Sqflite.firstIntValue(await db.rawQuery('SELECT COUNT(*) FROM exercise;')) ?? 0;
    if (count > 0) return;

    final source = await _loadSeed(jsonAssetOrPath, fromAsset: fromAsset);
    final List<dynamic> data = jsonDecode(source) as List<dynamic>;
    final batch = db.batch();
    for (final item in data) {
      final map = item as Map<String, dynamic>;
      batch.insert('exercise', {
        'canonical_name': map['canonical_name'],
        'equipment_type': map['equipment_type'],
        'primary_muscle': map['primary_muscle'],
        'secondary_muscles_json': jsonEncode(map['secondary_muscles'] ?? []),
        'is_builtin': 1,
        'weight_mode_default': map['weight_mode_default'],
        'created_at': DateTime.now().toIso8601String(),
      });
    }
    final results = await batch.commit();

    // Insert aliases after IDs are created.
    final exercises = await db.query('exercise', columns: ['id', 'canonical_name']);
    final nameToId = {for (final row in exercises) row['canonical_name'] as String: row['id'] as int};
    final aliasBatch = db.batch();
    for (final item in data) {
      final map = item as Map<String, dynamic>;
      final exerciseId = nameToId[map['canonical_name'] as String];
      if (exerciseId == null) continue;
      final aliases = (map['aliases'] as List<dynamic>? ?? []).cast<String>();
      for (final alias in aliases) {
        final normalized = alias.toLowerCase().replaceAll(RegExp(r'[^a-z0-9 ]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
        if (normalized.isEmpty) continue;
        aliasBatch.insert('exercise_alias', {
          'exercise_id': exerciseId,
          'alias_normalized': normalized,
          'source': 'builtin',
        }, conflictAlgorithm: ConflictAlgorithm.ignore);
      }
    }
    await aliasBatch.commit(noResult: true);
    if (results.isEmpty) {
      return;
    }
  }

  Future<String> _loadSeed(String jsonAssetOrPath, {required bool fromAsset}) async {
    if (fromAsset) {
      return rootBundle.loadString(jsonAssetOrPath);
    }
    final file = File(jsonAssetOrPath);
    return file.readAsString();
  }
}
