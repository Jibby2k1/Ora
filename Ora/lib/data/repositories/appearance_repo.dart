import '../../domain/models/appearance_entry.dart';
import '../db/db.dart';

class AppearanceRepo {
  AppearanceRepo(this._db);

  final AppDatabase _db;

  Future<int> addEntry({
    required DateTime createdAt,
    String? measurements,
    String? notes,
  }) async {
    final db = await _db.database;
    return db.insert('appearance_entry', {
      'created_at': createdAt.toIso8601String(),
      'measurements': measurements,
      'notes': notes,
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
    );
  }
}
