import 'dart:io';

import '../../domain/models/appearance_entry.dart';
import '../db/db.dart';

class AppearanceRepo {
  AppearanceRepo(this._db);

  final AppDatabase _db;

  Future<int> addEntry({
    required DateTime createdAt,
    String? measurements,
    String? notes,
    String? imagePath,
  }) async {
    final db = await _db.database;
    return db.insert('appearance_entry', {
      'created_at': createdAt.toIso8601String(),
      'measurements': measurements,
      'notes': notes,
      'image_path': imagePath,
    });
  }

  Future<List<AppearanceEntry>> getRecentEntries({int limit = 20}) async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_entry',
      orderBy: 'created_at DESC',
      limit: limit,
    );
    return rows.map(_fromRow).toList();
  }

  AppearanceEntry _fromRow(Map<String, Object?> row) {
    return AppearanceEntry(
      id: row['id'] as int,
      createdAt: DateTime.parse(row['created_at'] as String),
      measurements: row['measurements'] as String?,
      notes: row['notes'] as String?,
      imagePath: row['image_path'] as String?,
    );
  }

  Future<void> updateEntry({
    required int id,
    String? measurements,
    String? notes,
    String? imagePath,
  }) async {
    final db = await _db.database;
    await db.update(
      'appearance_entry',
      {
        if (measurements != null) 'measurements': measurements,
        if (notes != null) 'notes': notes,
        if (imagePath != null) 'image_path': imagePath,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteEntry(int id) async {
    final db = await _db.database;
    final rows = await db.query(
      'appearance_entry',
      columns: ['image_path'],
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      final path = rows.first['image_path'] as String?;
      if (path != null) {
        try {
          final file = File(path);
          if (await file.exists()) {
            await file.delete();
          }
        } catch (_) {
          // Ignore deletion failures to avoid blocking DB cleanup.
        }
      }
    }
    await db.delete('appearance_entry', where: 'id = ?', whereArgs: [id]);
  }
}
