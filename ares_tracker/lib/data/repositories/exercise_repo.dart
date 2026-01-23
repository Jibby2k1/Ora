import 'dart:convert';

import 'package:sqflite/sqflite.dart';

import '../db/db.dart';

class ExerciseRepo {
  ExerciseRepo(this._db);

  final AppDatabase _db;

  Future<List<Map<String, Object?>>> getAll() async {
    final db = await _db.database;
    return db.query('exercise', orderBy: 'canonical_name ASC');
  }

  Future<List<Map<String, Object?>>> getMissingMuscles({int limit = 500}) async {
    final db = await _db.database;
    return db.query(
      'exercise',
      where: 'primary_muscle IS NULL OR trim(primary_muscle) = ""',
      orderBy: 'canonical_name ASC',
      limit: limit,
    );
  }

  Future<Map<String, Object?>?> getById(int id) async {
    final db = await _db.database;
    final rows = await db.query('exercise', where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : rows.first;
  }

  Future<List<Map<String, Object?>>> findByCanonical(String normalized) async {
    final db = await _db.database;
    return db.query('exercise', where: 'lower(canonical_name) = ?', whereArgs: [normalized]);
  }

  Future<List<Map<String, Object?>>> findByAlias(String normalized) async {
    final db = await _db.database;
    final rows = await db.query('exercise_alias',
        columns: ['exercise_id'], where: 'alias_normalized = ?', whereArgs: [normalized]);
    if (rows.isEmpty) return [];
    final ids = rows.map((e) => e['exercise_id'] as int).toList();
    final placeholders = List.filled(ids.length, '?').join(',');
    return db.query('exercise', where: 'id IN ($placeholders)', whereArgs: ids);
  }

  Future<List<Map<String, Object?>>> findByTokenContains(List<String> tokens) async {
    if (tokens.isEmpty) return [];
    final db = await _db.database;
    final all = await db.query('exercise', columns: ['id', 'canonical_name', 'equipment_type', 'primary_muscle', 'secondary_muscles_json', 'weight_mode_default']);
    final lowerTokens = tokens.map((t) => t.toLowerCase()).toList();
    return all.where((row) {
      final name = (row['canonical_name'] as String).toLowerCase();
      return lowerTokens.every((t) => name.contains(t));
    }).toList();
  }

  Future<List<Map<String, Object?>>> getAllAliases() async {
    final db = await _db.database;
    return db.query(
      'exercise_alias',
      columns: ['exercise_id', 'alias_normalized'],
    );
  }

  Future<int> createExercise({
    required String canonicalName,
    required String equipmentType,
    required String weightModeDefault,
    String? primaryMuscle,
    List<String>? secondaryMuscles,
    bool isBuiltin = false,
  }) async {
    final db = await _db.database;
    return db.insert('exercise', {
      'canonical_name': canonicalName,
      'equipment_type': equipmentType,
      'primary_muscle': primaryMuscle,
      'secondary_muscles_json': jsonEncode(secondaryMuscles ?? []),
      'is_builtin': isBuiltin ? 1 : 0,
      'weight_mode_default': weightModeDefault,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> updateMuscles({
    required int exerciseId,
    required String primaryMuscle,
    required List<String> secondaryMuscles,
  }) async {
    final db = await _db.database;
    await db.update(
      'exercise',
      {
        'primary_muscle': primaryMuscle,
        'secondary_muscles_json': jsonEncode(secondaryMuscles),
      },
      where: 'id = ?',
      whereArgs: [exerciseId],
    );
  }

  Future<List<Map<String, Object?>>> search(String query, {int limit = 50}) async {
    final db = await _db.database;
    final normalized = query.toLowerCase().trim();
    if (normalized.isEmpty) return [];
    final like = '%$normalized%';
    return db.rawQuery('''\nSELECT DISTINCT e.*\nFROM exercise e\nLEFT JOIN exercise_alias a ON a.exercise_id = e.id\nWHERE lower(e.canonical_name) LIKE ? OR a.alias_normalized LIKE ?\nORDER BY e.canonical_name ASC\nLIMIT ?\n''', [like, like, limit]);
  }

  List<String> decodeSecondaryMuscles(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List<dynamic>).cast<String>();
    } catch (_) {
      return [];
    }
  }
}
