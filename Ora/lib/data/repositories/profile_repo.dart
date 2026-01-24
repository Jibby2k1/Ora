import '../db/db.dart';
import '../../domain/models/user_profile.dart';

class ProfileRepo {
  ProfileRepo(this._db);

  final AppDatabase _db;

  Future<UserProfile?> getProfile() async {
    final db = await _db.database;
    final rows = await db.query(
      'user_profile',
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    return _fromRow(rows.first);
  }

  Future<UserProfile> upsertProfile({
    String? displayName,
    int? age,
    double? heightCm,
    double? weightKg,
    String? notes,
  }) async {
    final db = await _db.database;
    final now = DateTime.now().toIso8601String();
    final existing = await getProfile();
    if (existing == null) {
      final id = await db.insert('user_profile', {
        'display_name': displayName,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'notes': notes,
        'created_at': now,
        'updated_at': now,
      });
      return UserProfile(
        id: id,
        displayName: displayName,
        age: age,
        heightCm: heightCm,
        weightKg: weightKg,
        notes: notes,
        createdAt: DateTime.parse(now),
        updatedAt: DateTime.parse(now),
      );
    }

    await db.update(
      'user_profile',
      {
        'display_name': displayName,
        'age': age,
        'height_cm': heightCm,
        'weight_kg': weightKg,
        'notes': notes,
        'updated_at': now,
      },
      where: 'id = ?',
      whereArgs: [existing.id],
    );
    return existing.copyWith(
      displayName: displayName,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes,
      updatedAt: DateTime.parse(now),
    );
  }

  UserProfile _fromRow(Map<String, Object?> row) {
    return UserProfile(
      id: row['id'] as int,
      displayName: row['display_name'] as String?,
      age: row['age'] as int?,
      heightCm: row['height_cm'] as double?,
      weightKg: row['weight_kg'] as double?,
      notes: row['notes'] as String?,
      createdAt: DateTime.parse(row['created_at'] as String),
      updatedAt: DateTime.parse(row['updated_at'] as String),
    );
  }
}
