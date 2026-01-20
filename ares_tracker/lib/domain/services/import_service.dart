import 'dart:io';

import 'package:excel/excel.dart';

import '../../data/db/db.dart';
import '../../data/repositories/exercise_repo.dart';
import '../../data/repositories/program_repo.dart';

class ImportResult {
  ImportResult({required this.programId, required this.dayCount, required this.exerciseCount});

  final int programId;
  final int dayCount;
  final int exerciseCount;
}

class ImportService {
  ImportService(this._db);

  final AppDatabase _db;

  Future<ImportResult> importFromXlsxPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('File not found: $path');
    }

    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    final sheet = excel.tables.values.first;
    if (sheet == null) {
      throw Exception('No sheets found');
    }

    final programRepo = ProgramRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);

    final programName = excel.tables.keys.first;
    final resolvedName = await _uniqueProgramName(programName);
    final programId = await programRepo.createProgram(name: resolvedName);

    final rows = sheet.rows;
    final headerRows = <int>[];
    for (var i = 0; i < rows.length; i++) {
      if (_rowContainsDay(rows[i])) {
        headerRows.add(i);
      }
    }
    if (headerRows.isEmpty) {
      throw Exception('No day headers found in sheet');
    }

    var dayIndex = 0;
    var exerciseCount = 0;
    for (var h = 0; h < headerRows.length; h++) {
      final startRow = headerRows[h];
      final endRow = h + 1 < headerRows.length ? headerRows[h + 1] : rows.length;
      final blocks = _dayBlocks(rows[startRow]);
      for (final block in blocks) {
        final dayId = await programRepo.addProgramDay(
          programId: programId,
          dayIndex: dayIndex,
          dayName: block.dayName,
        );
        dayIndex += 1;

        for (var r = startRow + 1; r < endRow; r++) {
          final row = rows[r];
          final exerciseName = _cellString(row, block.startCol);
          if (exerciseName == null || exerciseName.isEmpty) continue;
          if (exerciseName.toLowerCase().contains('warm up')) {
            continue;
          }

          final setsValue = _cellValue(row, block.startCol + 2);
          final setsCount = _parseInt(setsValue);
          if (setsCount == null) continue;

          final repsValue = _cellValue(row, block.startCol + 3);
          final restValue = _cellValue(row, block.startCol + 4);
          final rpeValue = _cellValue(row, block.startCol + 5);
          final notes = _cellString(row, block.startCol + 6);

          final exerciseId = await _resolveExerciseId(exerciseRepo, exerciseName);
          final dayExerciseId = await programRepo.addProgramDayExercise(
            programDayId: dayId,
            exerciseId: exerciseId,
            orderIndex: await _nextOrderIndex(programRepo, dayId),
            notes: notes,
          );
          exerciseCount += 1;

          final repsRange = _parseRange(repsValue);
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
        }
      }
    }

    return ImportResult(programId: programId, dayCount: dayIndex, exerciseCount: exerciseCount);
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

  bool _rowContainsDay(List<Data?> row) {
    for (final cell in row) {
      final value = cell?.value;
      if (value == null) continue;
      final text = value is String ? value : value.toString();
      if (text.trim().toUpperCase().startsWith('DAY')) {
        return true;
      }
    }
    return false;
  }

  List<_DayBlock> _dayBlocks(List<Data?> row) {
    final blocks = <_DayBlock>[];
    for (var i = 0; i < row.length; i++) {
      final value = row[i]?.value;
      if (value == null) continue;
      final text = value is String ? value : value.toString();
      if (text.trim().toUpperCase().startsWith('DAY')) {
        final setsHeader = _cellString(row, i + 2);
        final repsHeader = _cellString(row, i + 3);
        if (setsHeader?.toLowerCase() == 'sets' && repsHeader?.toLowerCase() == 'reps') {
          blocks.add(_DayBlock(startCol: i, dayName: text.trim()));
        }
      }
    }
    return blocks;
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

  Future<int> _resolveExerciseId(ExerciseRepo repo, String name) async {
    final normalized = name.toLowerCase().trim();
    final canonical = await repo.findByCanonical(normalized);
    if (canonical.isNotEmpty) return canonical.first['id'] as int;
    final alias = await repo.findByAlias(normalized);
    if (alias.isNotEmpty) return alias.first['id'] as int;
    final search = await repo.search(name, limit: 1);
    if (search.isNotEmpty) return search.first['id'] as int;

    final equipment = _inferEquipmentType(name);
    final weightMode = equipment == 'DUMBBELL' ? 'EACH' : 'TOTAL';
    return repo.createExercise(
      canonicalName: name.trim(),
      equipmentType: equipment,
      weightModeDefault: weightMode,
    );
  }

  String _inferEquipmentType(String name) {
    final lower = name.toLowerCase();
    if (lower.contains('dumbbell')) return 'DUMBBELL';
    if (lower.contains('barbell') || lower.contains('ez bar')) return 'BARBELL';
    if (lower.contains('cable')) return 'CABLE';
    if (lower.contains('smith') || lower.contains('machine') || lower.contains('hammer strength') || lower.contains('plate loaded') || lower.contains('selectorized')) {
      return 'MACHINE';
    }
    return 'MACHINE';
  }
}

class _DayBlock {
  _DayBlock({required this.startCol, required this.dayName});

  final int startCol;
  final String dayName;
}

class _Range {
  _Range({required this.min, required this.max});

  final double min;
  final double max;

  int? get minInt => min.isNaN ? null : min.round();
  int? get maxInt => max.isNaN ? null : max.round();
}
