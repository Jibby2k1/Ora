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

  List<String> decodeSecondaryMuscles(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      return (jsonDecode(json) as List<dynamic>).cast<String>();
    } catch (_) {
      return [];
    }
  }
}
