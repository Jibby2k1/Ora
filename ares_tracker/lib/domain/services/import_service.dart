import 'dart:io';
import 'dart:typed_data';

import 'package:excel/excel.dart';

import '../../data/db/db.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/program_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../core/voice/muscle_enricher.dart';

class ImportResult {
  ImportResult({
    required this.programId,
    required this.dayCount,
    required this.exerciseCount,
    required this.missingExercises,
  });

  final int programId;
  final int dayCount;
  final int exerciseCount;
  final List<String> missingExercises;
}

class ExerciseScanResult {
  ExerciseScanResult({
    required this.totalExercises,
    required this.missingExercises,
  });

  final int totalExercises;
  final List<String> missingExercises;
}

class ImportService {
  ImportService(this._db);

  final AppDatabase _db;
  final Map<String, MuscleInfo?> _muscleCache = {};

  Future<ImportResult> importFromXlsxPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('File not found: $path');
    }

    final bytes = file.readAsBytesSync();
    return importFromXlsxBytes(bytes);
  }

  Future<ImportResult> importFromXlsxBytes(Uint8List bytes, {String? programNameOverride}) async {
    final excel = Excel.decodeBytes(bytes);
    return _importFromExcel(excel, programNameOverride: programNameOverride);
  }

  Future<ExerciseScanResult> scanExercisesFromXlsxBytes(Uint8List bytes) async {
    final excel = Excel.decodeBytes(bytes);
    return _scanFromExcel(excel);
  }

  Future<ExerciseScanResult> scanExercisesFromXlsxPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('File not found: $path');
    }
    final bytes = file.readAsBytesSync();
    return scanExercisesFromXlsxBytes(bytes);
  }

  Future<ImportResult> _importFromExcel(Excel excel, {String? programNameOverride}) async {
    final sheet = excel.tables.values.first;
    if (sheet == null) {
      throw Exception('No sheets found');
    }

    final programRepo = ProgramRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);

    final rawName = programNameOverride?.trim().isNotEmpty == true
        ? programNameOverride!.trim()
        : excel.tables.keys.first;
    final resolvedName = await _uniqueProgramName(rawName.isEmpty ? 'Imported Program' : rawName);
    final programId = await programRepo.createProgram(name: resolvedName);

    final rows = sheet.rows;
    final missingExercises = <String>{};
    var dayIndex = 0;
    var exerciseCount = 0;

    int r = 0;
    while (r < rows.length) {
      final dayName = _dayStartName(rows[r]);
      if (dayName == null) {
        r += 1;
        continue;
      }
      final isRestDay = dayName.toLowerCase().contains('rest');
      final dayId = isRestDay
          ? null
          : await programRepo.addProgramDay(
              programId: programId,
              dayIndex: dayIndex,
              dayName: dayName,
            );
      if (!isRestDay) {
        dayIndex += 1;
      }

      r += 1;
      while (r < rows.length && !_dayEndRow(rows[r]) && _dayStartName(rows[r]) == null) {
        final row = rows[r];
        if (!isRestDay) {
          if (_rowHasHeaderTokens(row)) {
            r += 1;
            continue;
          }
          final exerciseName = _exerciseNameForRow(row, 0);
          if (exerciseName == null || exerciseName.isEmpty) {
            r += 1;
            continue;
          }
          final exerciseLower = exerciseName.toLowerCase();
          if (exerciseLower.contains('warm up') || exerciseLower.contains('optional warm up')) {
            r += 1;
            continue;
          }
          final setsValue = _cellValue(row, 1);
          final setsCount = _parseInt(setsValue);
          if (setsCount == null || setsCount < 1) {
            r += 1;
            continue;
          }

          final repsValue = _cellValue(row, 2);
          final restValue = _cellValue(row, 3);
          final rpeValue = _cellValue(row, 4);
          final notes = _cellString(row, 5);
          final repsRange = _parseRange(repsValue);

          final exerciseId = await _resolveExerciseId(exerciseRepo, exerciseName, createIfMissing: true);
          if (exerciseId == null) {
            missingExercises.add(exerciseName.trim());
            r += 1;
            continue;
          }
          await _maybeFillMuscles(exerciseId, exerciseName);
          final dayExerciseId = await programRepo.addProgramDayExercise(
            programDayId: dayId!,
            exerciseId: exerciseId,
            orderIndex: await _nextOrderIndex(programRepo, dayId),
            notes: notes,
          );
          exerciseCount += 1;

          final rpeRange = _parseRange(rpeValue, allowDecimal: true);
          final restRange = _parseRestRange(restValue);
          final dropPercent = _parseDropPercent(notes ?? '');

          final blocksToInsert = _buildBlocks(
            setsCount: setsCount,
            repsRange: repsRange,
            restRange: restRange,
            rpeRange: rpeRange,
            notes: notes ?? '',
            dropPercent: dropPercent,
          );
          await programRepo.replaceSetPlanBlocks(dayExerciseId, blocksToInsert);

          final notesCandidate = _cellString(row, 5);
          if (notesCandidate != null &&
              _isLikelyExerciseName(notesCandidate) &&
              r + 1 < rows.length &&
              !_dayEndRow(rows[r + 1]) &&
              _dayStartName(rows[r + 1]) == null) {
            final nextRow = rows[r + 1];
            final nextExercise = _exerciseNameForRow(nextRow, 0);
            final nextSetsValue = _cellValue(nextRow, 1);
            final nextSetsCount = _parseInt(nextSetsValue);
            final nextNotes = _cellString(nextRow, 5);
            if ((nextExercise == null || _looksLikeNote(nextExercise)) &&
                (nextNotes == null || !_dayEndRow(nextRow)) &&
                nextSetsCount != null &&
                nextSetsCount >= 1) {
              final nextRepsValue = _cellValue(nextRow, 2);
              final nextRestValue = _cellValue(nextRow, 3);
              final nextRpeValue = _cellValue(nextRow, 4);
              final nextRepsRange = _parseRange(nextRepsValue);
              final shiftedExerciseId =
                  await _resolveExerciseId(exerciseRepo, notesCandidate, createIfMissing: true);
              if (shiftedExerciseId != null) {
                final shiftedDayExerciseId = await programRepo.addProgramDayExercise(
                  programDayId: dayId!,
                  exerciseId: shiftedExerciseId,
                  orderIndex: await _nextOrderIndex(programRepo, dayId),
                  notes: nextExercise,
                );
                exerciseCount += 1;

                final shiftedRpeRange = _parseRange(nextRpeValue, allowDecimal: true);
                final shiftedRestRange = _parseRestRange(nextRestValue);
                final shiftedDropPercent = _parseDropPercent(nextExercise ?? '');
                final shiftedBlocks = _buildBlocks(
                  setsCount: nextSetsCount,
                  repsRange: nextRepsRange,
                  restRange: shiftedRestRange,
                  rpeRange: shiftedRpeRange,
                  notes: nextExercise ?? '',
                  dropPercent: shiftedDropPercent,
                );
                await programRepo.replaceSetPlanBlocks(shiftedDayExerciseId, shiftedBlocks);
                r += 1;
              }
            }
          }
        }
        r += 1;
      }
      if (r < rows.length && _dayEndRow(rows[r])) {
        r += 1;
      }
    }

    return ImportResult(
      programId: programId,
      dayCount: dayIndex,
      exerciseCount: exerciseCount,
      missingExercises: missingExercises.toList()..sort(),
    );
  }

  Future<ExerciseScanResult> _scanFromExcel(Excel excel) async {
    final sheet = excel.tables.values.first;
    if (sheet == null) {
      throw Exception('No sheets found');
    }

    final exerciseRepo = ExerciseRepo(_db);
    final rows = sheet.rows;
    final missing = <String>{};
    final seen = <String>{};
    var total = 0;
    int r = 0;
    while (r < rows.length) {
      final dayName = _dayStartName(rows[r]);
      if (dayName == null) {
        r += 1;
        continue;
      }
      final isRestDay = dayName.toLowerCase().contains('rest');
      r += 1;
      while (r < rows.length && !_dayEndRow(rows[r]) && _dayStartName(rows[r]) == null) {
        final row = rows[r];
        if (!isRestDay) {
          if (_rowHasHeaderTokens(row)) {
            r += 1;
            continue;
          }
          final exerciseName = _exerciseNameForRow(row, 0);
          if (exerciseName == null || exerciseName.isEmpty) {
            r += 1;
            continue;
          }
          final exerciseLower = exerciseName.toLowerCase();
          if (exerciseLower.contains('warm up') || exerciseLower.contains('optional warm up')) {
            r += 1;
            continue;
          }
          final setsValue = _cellValue(row, 1);
          final setsCount = _parseInt(setsValue);
          if (setsCount == null || setsCount < 1) {
            r += 1;
            continue;
          }
          final repsValue = _cellValue(row, 2);
          final repsRange = _parseRange(repsValue);
          final key = exerciseName.toLowerCase().trim();
          if (seen.contains(key)) {
            r += 1;
            continue;
          }
          seen.add(key);
          total += 1;
          final exists = await _exerciseExists(exerciseRepo, exerciseName);
          if (!exists) {
            missing.add(exerciseName.trim());
          }
          if (exists) {
            final byId = await _resolveExerciseId(exerciseRepo, exerciseName, createIfMissing: false);
            if (byId != null) {
              await _maybeFillMuscles(byId, exerciseName);
            }
          }

          final notesCandidate = _cellString(row, 5);
          if (notesCandidate != null &&
              _isLikelyExerciseName(notesCandidate) &&
              r + 1 < rows.length &&
              !_dayEndRow(rows[r + 1]) &&
              _dayStartName(rows[r + 1]) == null) {
            final nextRow = rows[r + 1];
            final nextExercise = _exerciseNameForRow(nextRow, 0);
            final nextSetsValue = _cellValue(nextRow, 1);
            final nextSetsCount = _parseInt(nextSetsValue);
            final nextNotes = _cellString(nextRow, 5);
            if ((nextExercise == null || _looksLikeNote(nextExercise)) &&
                (nextNotes == null || !_dayEndRow(nextRow)) &&
                nextSetsCount != null &&
                nextSetsCount >= 1) {
              final shiftedKey = notesCandidate.toLowerCase().trim();
              if (!seen.contains(shiftedKey)) {
                seen.add(shiftedKey);
                total += 1;
                final existsShifted = await _exerciseExists(exerciseRepo, notesCandidate);
                if (!existsShifted) {
                  missing.add(notesCandidate.trim());
                }
              }
              r += 1;
            }
          }
        }
        r += 1;
      }
      if (r < rows.length && _dayEndRow(rows[r])) {
        r += 1;
      }
    }

    return ExerciseScanResult(
      totalExercises: total,
      missingExercises: missing.toList()..sort(),
    );
  }

  Future<int> _nextOrderIndex(ProgramRepo repo, int dayId) async {
    final existing = await repo.getProgramDayExerciseDetails(dayId);
    return existing.length;
  }

  Future<String> _uniqueProgramName(String baseName) async {
    final repo = ProgramRepo(_db);
    final existing = await repo.getPrograms();
    final names = existing.map((e) => e['name']).toSet();
    if (!names.contains(baseName)) return baseName;
    var i = 2;
    while (names.contains('$baseName ($i)')) {
      i++;
    }
    return '$baseName ($i)';
  }

  String? _dayStartName(List<Data?> row) {
    if (row.isEmpty) return null;
    final value = row[0]?.value;
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    final trimmed = text.trim();
    if (!trimmed.toUpperCase().startsWith('DAY')) return null;
    if (trimmed.toUpperCase().contains('END')) return null;
    return trimmed;
  }

  bool _dayEndRow(List<Data?> row) {
    if (row.isEmpty) return false;
    final value = row[0]?.value;
    if (value == null) return false;
    final text = value is String ? value : value.toString();
    final trimmed = text.trim().toUpperCase();
    return trimmed.startsWith('DAY') && trimmed.contains('END');
  }

  String? _cellString(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    final value = row[index]?.value;
    if (value == null) return null;
    if (value is DateTime) {
      return '${value.month}-${value.day}';
    }
    final text = value is String ? value : value.toString();
    return text.trim();
  }

  String? _exerciseNameForRow(List<Data?> row, int exerciseCol) {
    final direct = _cellString(row, exerciseCol);
    if (direct == null || direct.isEmpty) return null;
    if (_isHeaderToken(direct)) return null;
    if (_looksLikeNote(direct)) return null;
    return direct;
  }

  bool _rowHasHeaderTokens(List<Data?> row) {
    for (final cell in row) {
      final value = cell?.value;
      if (value == null) continue;
      final text = value is String ? value : value.toString();
      if (_isHeaderToken(text)) return true;
    }
    return false;
  }

  bool _isHeaderToken(String text) {
    final lower = text.trim().toLowerCase();
    return lower == 'sets' || lower == 'reps' || lower == 'rest' || lower == 'rpe' || lower == 'notes';
  }

  bool _looksLikeNote(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('top set') || lower.contains('back-off') || lower.contains('drop')) return true;
    if (lower.contains('focus on') ||
        lower.contains('keep ') ||
        lower.contains('use ') ||
        lower.contains('important') ||
        lower.contains('pause ') ||
        lower.contains('squeeze') ||
        lower.contains('full rom') ||
        lower.contains('warm up') ||
        lower.contains('optional warm up')) {
      return true;
    }
    if (lower.startsWith('progression') || lower.startsWith('weekly direct volume')) return true;
    return false;
  }

  bool _isLikelyExerciseName(String text) {
    if (text.trim().isEmpty) return false;
    if (_isHeaderToken(text)) return false;
    if (_looksLikeNote(text)) return false;
    final lower = text.trim().toLowerCase();
    if (lower.startsWith('day')) return false;
    return true;
  }

  dynamic _cellValue(List<Data?> row, int index) {
    if (index < 0 || index >= row.length) return null;
    return row[index]?.value;
  }

  int? _parseInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.toInt();
    final text = value is String ? value : value.toString();
    return int.tryParse(text.trim());
  }

  _Range? _parseRange(dynamic value, {bool allowDecimal = false}) {
    if (value == null) return null;
    if (value is DateTime) {
      return _Range(min: value.month.toDouble(), max: value.day.toDouble());
    }
    if (value is num) {
      return _Range(min: value.toDouble(), max: value.toDouble());
    }
    final text = value is String ? value : value.toString();
    if (text.isNotEmpty) {
      final cleaned = text.trim();
      if (cleaned.isEmpty) return null;
      final dateMatch = RegExp(r'^(\\d{4})-(\\d{2})-(\\d{2})').firstMatch(cleaned);
      if (dateMatch != null) {
        final month = double.tryParse(dateMatch.group(2) ?? '');
        final day = double.tryParse(dateMatch.group(3) ?? '');
        if (month != null && day != null) {
          return _Range(min: month, max: day);
        }
      }
      if (cleaned.contains('-')) {
        final parts = cleaned.split('-').map((p) => p.trim()).toList();
        if (parts.length == 2) {
          final min = double.tryParse(parts[0]);
          final max = double.tryParse(parts[1]);
          if (min != null && max != null) {
            return _Range(min: min, max: max);
          }
        }
      }
      final numValue = double.tryParse(cleaned);
      if (numValue != null) {
        return _Range(min: numValue, max: numValue);
      }
    }
    return null;
  }

  _Range? _parseRestRange(dynamic value) {
    if (value == null) return null;
    final text = value is String ? value : value.toString();
    final cleaned = text.toLowerCase();
    final numbers = RegExp(r'(\\d+)').allMatches(cleaned).map((m) => int.parse(m.group(1)!)).toList();
    if (numbers.isEmpty) return null;
    final isMin = cleaned.contains('min');
    final factor = isMin ? 60 : 1;
    if (numbers.length == 1) {
      return _Range(min: numbers[0] * factor.toDouble(), max: numbers[0] * factor.toDouble());
    }
    return _Range(min: numbers[0] * factor.toDouble(), max: numbers[1] * factor.toDouble());
  }

  _Range? _parseDropPercent(String notes) {
    final match = RegExp(r'Drop\s*~?\s*(\d+)(?:-(\d+))?%').firstMatch(notes);
    if (match == null) return null;
    final min = double.tryParse(match.group(1) ?? '');
    final max = double.tryParse(match.group(2) ?? match.group(1) ?? '');
    if (min == null || max == null) return null;
    return _Range(min: min, max: max);
  }

  List<Map<String, Object?>> _buildBlocks({
    required int setsCount,
    required _Range? repsRange,
    required _Range? restRange,
    required _Range? rpeRange,
    required String notes,
    required _Range? dropPercent,
  }) {
    final blocks = <Map<String, Object?>>[];
    final topReps = _extractRange(notes, 'Top Set');
    final backoffReps = _extractRange(notes, 'Back-Off');

    if (topReps != null && setsCount >= 2) {
      blocks.add(_blockMap(
        orderIndex: 0,
        role: 'TOP',
        setCount: 1,
        repsRange: topReps,
        restRange: restRange,
        rpeRange: rpeRange,
        loadRuleType: 'NONE',
        dropPercent: null,
      ));
      blocks.add(_blockMap(
        orderIndex: 1,
        role: 'BACKOFF',
        setCount: setsCount - 1,
        repsRange: backoffReps ?? repsRange,
        restRange: restRange,
        rpeRange: rpeRange,
        loadRuleType: dropPercent == null ? 'NONE' : 'DROP_PERCENT_FROM_TOP',
        dropPercent: dropPercent,
      ));
      return blocks;
    }

    blocks.add(_blockMap(
      orderIndex: 0,
      role: 'TOP',
      setCount: setsCount,
      repsRange: repsRange,
      restRange: restRange,
      rpeRange: rpeRange,
      loadRuleType: 'NONE',
      dropPercent: null,
    ));
    return blocks;
  }

  _Range? _extractRange(String notes, String label) {
    final match = RegExp('$label[^:]*:([^\\n]+)').firstMatch(notes);
    if (match == null) return null;
    return _parseRange(match.group(1)?.trim());
  }

  Map<String, Object?> _blockMap({
    required int orderIndex,
    required String role,
    required int setCount,
    required _Range? repsRange,
    required _Range? restRange,
    required _Range? rpeRange,
    required String loadRuleType,
    required _Range? dropPercent,
  }) {
    return {
      'order_index': orderIndex,
      'role': role,
      'set_count': setCount,
      'reps_min': repsRange?.minInt,
      'reps_max': repsRange?.maxInt,
      'rest_sec_min': restRange?.minInt,
      'rest_sec_max': restRange?.maxInt,
      'target_rpe_min': rpeRange?.min,
      'target_rpe_max': rpeRange?.max,
      'target_rir_min': null,
      'target_rir_max': null,
      'load_rule_type': loadRuleType,
      'load_rule_min': dropPercent?.min,
      'load_rule_max': dropPercent?.max,
      'amrap_last_set': 0,
      'partials_target_min': null,
      'partials_target_max': null,
      'notes': null,
    };
  }

  Future<int?> _resolveExerciseId(ExerciseRepo repo, String name, {required bool createIfMissing}) async {
    final normalized = name.toLowerCase().trim();
    final canonical = await repo.findByCanonical(normalized);
    if (canonical.isNotEmpty) return canonical.first['id'] as int;
    final alias = await repo.findByAlias(normalized);
    if (alias.isNotEmpty) return alias.first['id'] as int;
    final search = await repo.search(name, limit: 1);
    if (search.isNotEmpty) return search.first['id'] as int;
    if (!createIfMissing) return null;

    final equipment = _inferEquipmentType(name);
    final weightMode = equipment == 'DUMBBELL' ? 'EACH' : 'TOTAL';
    return repo.createExercise(
      canonicalName: name.trim(),
      equipmentType: equipment,
      weightModeDefault: weightMode,
    );
  }

  Future<void> _maybeFillMuscles(int exerciseId, String exerciseName) async {
    final exerciseRepo = ExerciseRepo(_db);
    final existing = await exerciseRepo.getById(exerciseId);
    final primary = existing?['primary_muscle'] as String?;
    if (primary != null && primary.trim().isNotEmpty) return;

    final settings = SettingsRepo(_db);
    final cloudEnabled = await settings.getCloudEnabled();
    final apiKey = await settings.getCloudApiKey();
    if (!cloudEnabled || apiKey == null || apiKey.trim().isEmpty) return;

    final cacheKey = exerciseName.toLowerCase().trim();
    if (_muscleCache.containsKey(cacheKey)) {
      final cached = _muscleCache[cacheKey];
      if (cached != null) {
        await exerciseRepo.updateMuscles(
          exerciseId: exerciseId,
          primaryMuscle: cached.primary,
          secondaryMuscles: cached.secondary,
        );
      }
      return;
    }

    final provider = await settings.getCloudProvider();
    final model = await settings.getCloudModel();
    final enricher = MuscleEnricher();
    final info = await enricher.enrich(
      exerciseName: exerciseName,
      provider: provider,
      apiKey: apiKey,
      model: model,
    );
    _muscleCache[cacheKey] = info;
    if (info == null) return;
    await exerciseRepo.updateMuscles(
      exerciseId: exerciseId,
      primaryMuscle: info.primary,
      secondaryMuscles: info.secondary,
    );
  }

  Future<bool> _exerciseExists(ExerciseRepo repo, String name) async {
    final normalized = name.toLowerCase().trim();
    final canonical = await repo.findByCanonical(normalized);
    if (canonical.isNotEmpty) return true;
    final alias = await repo.findByAlias(normalized);
    if (alias.isNotEmpty) return true;
    final search = await repo.search(name, limit: 1);
    return search.isNotEmpty;
  }

  String _inferEquipmentType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('dumbbell') || lower.contains('db')) return 'DUMBBELL';
    if (lower.contains('barbell') || lower.contains('ez bar')) return 'BARBELL';
    if (lower.contains('cable')) return 'CABLE';
    if (lower.contains('smith') ||
        lower.contains('machine') ||
        lower.contains('hammer strength') ||
        lower.contains('plate loaded') ||
        lower.contains('selectorized')) {
      return 'MACHINE';
    }
    return 'MACHINE';
  }

  // Equipment inference removed while missing exercises are ignored.
}

class _Range {
  _Range({required this.min, required this.max});

  final double min;
  final double max;

  int? get minInt => min.isNaN ? null : min.round();
  int? get maxInt => max.isNaN ? null : max.round();
}
