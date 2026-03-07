import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:excel/excel.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../core/cloud/gemini_queue.dart';
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

  Future<ImportResult> importFromXlsxBytes(Uint8List bytes,
      {String? programNameOverride}) async {
    _logImport(
      'importFromXlsxBytes bytes=${bytes.length} override_name="${programNameOverride ?? ''}"',
    );
    _logImport('importFromXlsxBytes fingerprint=${_fingerprintBytes(bytes)}');
    final excel = Excel.decodeBytes(bytes);
    final tableSummaries = excel.tables.entries
        .map((entry) => '${entry.key}:${entry.value.maxRows}')
        .join(', ');
    _logImport('xlsx_tables=${excel.tables.length} [$tableSummaries]');
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

  Future<ImportResult> importFromSharedProgramPath(String path) async {
    final file = File(path);
    if (!file.existsSync()) {
      throw Exception('File not found: $path');
    }
    int? sizeBytes;
    try {
      sizeBytes = file.lengthSync();
    } catch (_) {
      sizeBytes = null;
    }
    _logImport(
      'importFromSharedProgramPath path="$path" size_bytes=${sizeBytes ?? -1}',
    );
    try {
      final stat = file.statSync();
      _logImport(
        'importFromSharedProgramPath file_stat type=${stat.type} modified=${stat.modified.toIso8601String()} changed=${stat.changed.toIso8601String()}',
      );
    } catch (_) {}

    final lowerPath = file.path.toLowerCase();
    if (lowerPath.endsWith('.xlsx')) {
      final bytes = file.readAsBytesSync();
      _logImport(
        'importFromSharedProgramPath fingerprint=${_fingerprintBytes(bytes)}',
      );
      final spreadsheetResult = await importFromXlsxBytes(bytes);
      if (spreadsheetResult.exerciseCount > 0) {
        return spreadsheetResult;
      }
      try {
        await ProgramRepo(_db).deleteProgram(spreadsheetResult.programId);
      } catch (_) {}
    }

    final interpreted = await _interpretSharedProgramFile(file);
    if (interpreted == null) {
      throw Exception(
        'Could not interpret this program file. Enable cloud parsing in Settings or use the template XLSX format.',
      );
    }
    _logImport(
        'using_interpreted_program_fallback days=${interpreted.days.length}');
    return _importFromStructuredProgram(interpreted);
  }

  Future<_StructuredProgram?> _interpretSharedProgramFile(File file) async {
    final rawText = _extractProgramFileText(file);
    if (rawText == null || rawText.trim().isEmpty) {
      return null;
    }
    final fallbackProgram = _heuristicProgramFromText(
      fileText: rawText,
      fileName: file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last,
    );

    final settings = SettingsRepo(_db);
    final cloudEnabled = await settings.getCloudEnabled();
    final apiKey = await settings.getCloudApiKey();
    final provider = await settings.getCloudProvider();
    if (!cloudEnabled || apiKey == null || apiKey.trim().isEmpty) {
      return fallbackProgram;
    }
    final model = await settings.getCloudModelForTask(
      CloudModelTask.programInterpretation,
    );
    final prompt = _buildProgramInterpretPrompt(
      fileName: file.uri.pathSegments.isEmpty
          ? file.path
          : file.uri.pathSegments.last,
      fileText: rawText,
    );

    String? responseText;
    try {
      if (provider.trim().toLowerCase() == 'openai') {
        responseText = await _interpretProgramWithOpenAi(
          prompt: prompt,
          apiKey: apiKey,
          model: model,
        );
      } else {
        responseText = await _interpretProgramWithGemini(
          prompt: prompt,
          apiKey: apiKey,
          model: model,
        );
      }
    } on TimeoutException catch (error) {
      stderr.writeln('[Import][program-interpret-timeout] $error');
      return fallbackProgram;
    } catch (error, stackTrace) {
      stderr.writeln('[Import][program-interpret-error] $error\n$stackTrace');
      return fallbackProgram;
    }
    if (responseText == null || responseText.trim().isEmpty) {
      return fallbackProgram;
    }

    final jsonText = _extractJsonObject(responseText);
    if (jsonText == null) return fallbackProgram;

    try {
      final decoded = jsonDecode(jsonText);
      if (decoded is! Map<String, dynamic>) return fallbackProgram;
      return _structuredProgramFromMap(decoded) ?? fallbackProgram;
    } catch (error, stackTrace) {
      stderr.writeln('[Import][program-interpret-json] $error\n$stackTrace');
      return fallbackProgram;
    }
  }

  Future<String?> _interpretProgramWithOpenAi({
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    final useResponses = _openAiUsesResponses(model);
    final uri = Uri.https(
      'api.openai.com',
      useResponses ? '/v1/responses' : '/v1/chat/completions',
    );
    final payload = useResponses
        ? <String, dynamic>{
            'model': model,
            'input': [
              {
                'role': 'system',
                'content': [
                  {
                    'type': 'input_text',
                    'text':
                        'Extract workout programs from shared files. Return JSON only.',
                  },
                ],
              },
              {
                'role': 'user',
                'content': [
                  {'type': 'input_text', 'text': prompt},
                ],
              },
            ],
          }
        : <String, dynamic>{
            'model': model,
            if (_openAiSupportsTemperature(model)) 'temperature': 0.1,
            'messages': [
              {
                'role': 'system',
                'content':
                    'Extract workout programs from shared files. Return JSON only.',
              },
              {'role': 'user', 'content': prompt},
            ],
            'response_format': {'type': 'json_object'},
          };

    final response = await http
        .post(
          uri,
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $apiKey',
          },
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 45));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      if (useResponses) {
        return _extractOpenAiResponseText(decoded);
      }
      final choices = decoded['choices'] as List<dynamic>? ?? const [];
      if (choices.isEmpty) return null;
      final message = choices.first['message'] as Map<String, dynamic>?;
      return message?['content']?.toString();
    } catch (_) {
      return null;
    }
  }

  Future<String?> _interpretProgramWithGemini({
    required String prompt,
    required String apiKey,
    required String model,
  }) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      {'key': apiKey},
    );
    final payload = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 2048,
      },
    };

    final response = await GeminiQueue.instance.run(
      () => http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45)),
      label: 'program-import',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    try {
      final decoded = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = decoded['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      if (parts.isEmpty) return null;
      return parts.first['text']?.toString();
    } catch (_) {
      return null;
    }
  }

  _StructuredProgram? _structuredProgramFromMap(Map<String, dynamic> map) {
    final programName =
        map['program_name']?.toString().trim().isNotEmpty == true
            ? map['program_name'].toString().trim()
            : map['name']?.toString().trim().isNotEmpty == true
                ? map['name'].toString().trim()
                : 'Imported Program';
    final daysRaw = map['days'];
    if (daysRaw is! List) return null;

    final days = <_StructuredProgramDay>[];
    for (final rawDay in daysRaw) {
      if (rawDay is! Map) continue;
      final day = _structuredDayFromMap(Map<String, dynamic>.from(rawDay));
      if (day != null) {
        days.add(day);
      }
    }
    if (days.isEmpty) return null;
    return _StructuredProgram(programName: programName, days: days);
  }

  _StructuredProgramDay? _structuredDayFromMap(Map<String, dynamic> dayMap) {
    final dayName = dayMap['day_name']?.toString().trim().isNotEmpty == true
        ? dayMap['day_name'].toString().trim()
        : dayMap['name']?.toString().trim().isNotEmpty == true
            ? dayMap['name'].toString().trim()
            : 'Day';
    final exercisesRaw = dayMap['exercises'];
    if (exercisesRaw is! List) {
      return _StructuredProgramDay(dayName: dayName, exercises: const []);
    }
    final exercises = <_StructuredExercise>[];
    for (final rawExercise in exercisesRaw) {
      if (rawExercise is! Map) continue;
      final parsedExercise = _structuredExerciseFromMap(
        Map<String, dynamic>.from(rawExercise),
      );
      if (parsedExercise != null) {
        exercises.add(parsedExercise);
      }
    }
    return _StructuredProgramDay(dayName: dayName, exercises: exercises);
  }

  _StructuredExercise? _structuredExerciseFromMap(
      Map<String, dynamic> exerciseMap) {
    final name = exerciseMap['name']?.toString().trim().isNotEmpty == true
        ? exerciseMap['name'].toString().trim()
        : exerciseMap['exercise']?.toString().trim().isNotEmpty == true
            ? exerciseMap['exercise'].toString().trim()
            : exerciseMap['exercise_name']?.toString().trim().isNotEmpty == true
                ? exerciseMap['exercise_name'].toString().trim()
                : null;
    if (name == null || name.isEmpty) return null;

    final sets = _parseInt(exerciseMap['sets']) ??
        _parseLeadingInt(exerciseMap['sets']?.toString()) ??
        3;

    final repsRange = _rangeFromMinMax(
          min: exerciseMap['reps_min'],
          max: exerciseMap['reps_max'],
        ) ??
        _parseRange(exerciseMap['reps']);

    final restRange = _rangeFromMinMax(
          min: exerciseMap['rest_sec_min'],
          max: exerciseMap['rest_sec_max'],
        ) ??
        _parseRestRange(exerciseMap['rest']) ??
        _parseRestRange(exerciseMap['rest_seconds']);

    final rpeRange = _rangeFromMinMax(
          min: exerciseMap['rpe_min'],
          max: exerciseMap['rpe_max'],
        ) ??
        _parseRange(exerciseMap['rpe'], allowDecimal: true);

    final dropPercentRange = _rangeFromMinMax(
          min: exerciseMap['drop_percent_min'],
          max: exerciseMap['drop_percent_max'],
        ) ??
        _parseDropPercent(exerciseMap['notes']?.toString() ?? '');

    final notes = exerciseMap['notes']?.toString().trim();
    final amrap = _parseBool(exerciseMap['amrap_last_set']) ?? false;
    final role = _normalizeRole(exerciseMap['role']?.toString());

    return _StructuredExercise(
      name: name,
      setCount: sets.clamp(1, 20).toInt(),
      repsRange: repsRange,
      restRange: restRange,
      rpeRange: rpeRange,
      dropPercentRange: dropPercentRange,
      notes: notes == null || notes.isEmpty ? null : notes,
      amrapLastSet: amrap,
      role: role,
    );
  }

  Future<ImportResult> _importFromStructuredProgram(
      _StructuredProgram program) async {
    _logImport(
      'importFromStructuredProgram begin program="${program.programName}" days=${program.days.length}',
    );
    final programRepo = ProgramRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);
    final programName = program.programName.trim().isEmpty
        ? 'Imported Program'
        : program.programName.trim();
    final resolvedName = await _uniqueProgramName(programName);
    final programId = await programRepo.createProgram(
      name: resolvedName,
      notes: program.meta.isEmpty ? null : jsonEncode(program.meta),
    );

    final missingExercises = <String>{};
    var dayCount = 0;
    var exerciseCount = 0;

    for (final day in program.days) {
      final dayName = day.dayName.trim().isEmpty
          ? 'Day ${dayCount + 1}'
          : day.dayName.trim();
      _logImport(
        'structured_day index=${dayCount + 1} name="$dayName" exercises=${day.exercises.length}',
      );
      final dayId = await programRepo.addProgramDay(
        programId: programId,
        dayIndex: dayCount,
        dayName: dayName,
      );
      dayCount += 1;
      if (day.exercises.isEmpty || dayName.toLowerCase().contains('rest')) {
        continue;
      }

      var orderIndex = 0;
      for (final exercise in day.exercises) {
        final exerciseId = await _resolveExerciseId(
          exerciseRepo,
          exercise.name,
          createIfMissing: true,
        );
        if (exerciseId == null) {
          missingExercises.add(exercise.name.trim());
          _logImport(
            'structured_exercise_missing day="$dayName" exercise="${exercise.name}"',
          );
          continue;
        }

        await _maybeFillMuscles(exerciseId, exercise.name);
        final dayExerciseId = await programRepo.addProgramDayExercise(
          programDayId: dayId,
          exerciseId: exerciseId,
          orderIndex: orderIndex,
          notes: exercise.notes,
        );
        orderIndex += 1;
        exerciseCount += 1;
        _logImport(
          'structured_exercise_added day="$dayName" order=$orderIndex exercise="${exercise.name}" sets=${exercise.setCount}',
        );

        final drop = exercise.dropPercentRange;
        await programRepo.replaceSetPlanBlocks(
          dayExerciseId,
          [
            _blockMap(
              orderIndex: 0,
              role: exercise.role,
              setCount: exercise.setCount,
              repsRange: exercise.repsRange,
              restRange: exercise.restRange,
              rpeRange: exercise.rpeRange,
              loadRuleType: drop == null ? 'NONE' : 'DROP_PERCENT_FROM_TOP',
              dropPercent: drop,
              amrapLastSet: exercise.amrapLastSet,
            ),
          ],
        );
      }
    }

    if (exerciseCount == 0) {
      await programRepo.deleteProgram(programId);
      throw Exception(
        'Could not find importable exercises in this file.',
      );
    }

    _logImport(
      'importFromStructuredProgram complete program_id=$programId day_count=$dayCount exercise_count=$exerciseCount missing=${missingExercises.length}',
    );
    return ImportResult(
      programId: programId,
      dayCount: dayCount,
      exerciseCount: exerciseCount,
      missingExercises: missingExercises.toList()..sort(),
    );
  }

  String _buildProgramInterpretPrompt({
    required String fileName,
    required String fileText,
  }) {
    final clippedText =
        fileText.length > 30000 ? fileText.substring(0, 30000) : fileText;
    return '''
You convert shared workout program files into strict JSON for app import.
Return JSON only. Do not include markdown.

Schema:
{
  "program_name": "string",
  "days": [
    {
      "day_name": "string",
      "exercises": [
        {
          "name": "string",
          "sets": 3,
          "reps_min": 8,
          "reps_max": 12,
          "rest_sec_min": 90,
          "rest_sec_max": 120,
          "rpe_min": null,
          "rpe_max": null,
          "drop_percent_min": null,
          "drop_percent_max": null,
          "amrap_last_set": false,
          "role": "TOP",
          "notes": "optional string"
        }
      ]
    }
  ]
}

Rules:
- Extract only exercises that are part of the lifting plan.
- Ignore warm-up-only, cardio-only, and commentary rows unless they are explicit exercises.
- Infer day boundaries from headings (e.g., Day 1, Upper, Pull, etc.).
- Descriptor rows/columns may define fields like Exercise, Sets, Reps, Rest, RPE, Notes; use those labels to map values.
- Include rest days as explicit day entries with an empty "exercises" list.
- Preserve original day order, including rest days.
- Convert rest to seconds (2-3 min => 120-180 sec).
- If reps are a single value, set both min and max to that value.
- If sets are missing, default sets to 3.
- Use null for unknown numeric values.
- Keep role as one of: TOP, BACKOFF, WARMUP. Default to TOP.
- Preserve exercise intent; keep names concise.

File name: $fileName
File content:
$clippedText
''';
  }

  _StructuredProgram? _heuristicProgramFromText({
    required String fileText,
    required String fileName,
  }) {
    final lines = fileText
        .split(RegExp(r'[\r\n]+'))
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toList();
    if (lines.isEmpty) return null;

    final days = <_StructuredProgramDay>[];
    var currentDayName = 'Day 1';
    var currentExercises = <_StructuredExercise>[];
    var autoDayIndex = 2;

    void flushDay() {
      if (currentExercises.isEmpty) return;
      days.add(
        _StructuredProgramDay(
          dayName: currentDayName,
          exercises: List<_StructuredExercise>.from(currentExercises),
        ),
      );
      currentExercises = <_StructuredExercise>[];
    }

    for (final line in lines) {
      final dayHeader = _heuristicDayHeader(line);
      if (dayHeader != null) {
        flushDay();
        currentDayName = dayHeader;
        continue;
      }

      final parsed = _heuristicExerciseFromLine(line);
      if (parsed != null) {
        if (currentDayName.trim().isEmpty) {
          currentDayName = 'Day ${autoDayIndex++}';
        }
        currentExercises.add(parsed);
      }
    }
    flushDay();

    if (days.isEmpty) return null;
    final programName = _programNameFromFileName(fileName);
    return _StructuredProgram(programName: programName, days: days);
  }

  String _programNameFromFileName(String fileName) {
    var name = fileName.trim();
    final slash = name.lastIndexOf(RegExp(r'[\\/]'));
    if (slash >= 0 && slash + 1 < name.length) {
      name = name.substring(slash + 1);
    }
    final dot = name.lastIndexOf('.');
    if (dot > 0) {
      name = name.substring(0, dot);
    }
    final compact = name.replaceAll(RegExp(r'[_\-]+'), ' ').trim();
    return compact.isEmpty ? 'Imported Program' : compact;
  }

  String? _heuristicDayHeader(String line) {
    final raw = line.trim();
    if (raw.isEmpty) return null;
    final firstToken = raw
        .split(RegExp(r'[|\t]'))
        .map((token) => token.trim())
        .firstWhere((token) => token.isNotEmpty, orElse: () => raw);
    final candidate = firstToken.trim();
    final lower = candidate.toLowerCase();
    if (lower.startsWith('[sheet]')) return null;

    if (RegExp(r'^day\s*\d+\b').hasMatch(lower)) {
      if (lower.contains('end')) return null;
      return candidate;
    }
    if (lower.contains('rest day') || lower == 'rest') {
      return candidate;
    }

    final keywords = <String>[
      'upper',
      'lower',
      'push',
      'pull',
      'legs',
      'full body',
      'chest',
      'back',
      'shoulders',
      'arms',
      'glutes',
      'hamstrings',
      'quads'
    ];
    if (candidate.length <= 36 &&
        keywords.any((keyword) => lower.contains(keyword)) &&
        !RegExp(r'\d+\s*(x|sets?|reps?)').hasMatch(lower)) {
      return candidate;
    }
    return null;
  }

  _StructuredExercise? _heuristicExerciseFromLine(String line) {
    final raw = line.trim();
    if (raw.isEmpty) return null;
    if (raw.toLowerCase().startsWith('[sheet]')) return null;

    final parts = raw.contains('|')
        ? raw.split('|').map((p) => p.trim()).toList()
        : raw.contains('\t')
            ? raw.split('\t').map((p) => p.trim()).toList()
            : raw.split(',').map((p) => p.trim()).toList();
    final nonEmptyParts =
        parts.where((part) => part.trim().isNotEmpty).toList();
    if (nonEmptyParts.isEmpty) return null;

    final name = nonEmptyParts.first.trim();
    if (name.isEmpty) return null;
    if (_isHeaderToken(name)) return null;
    if (_looksLikeNote(name)) return null;
    if (name.toLowerCase().startsWith('day ')) return null;
    if (RegExp(r'^\d+(\.\d+)?$').hasMatch(name)) return null;

    final sets = _parseInt(
            nonEmptyParts.length > 1 ? nonEmptyParts[1] : null) ??
        _parseLeadingInt(nonEmptyParts.length > 1 ? nonEmptyParts[1] : null) ??
        _parseLeadingInt(raw) ??
        3;
    final reps =
        _parseRange(nonEmptyParts.length > 2 ? nonEmptyParts[2] : null) ??
            _extractRepsRange(raw);
    final rest =
        _parseRestRange(nonEmptyParts.length > 3 ? nonEmptyParts[3] : null) ??
            _extractRestRange(raw);
    final rpe = _parseRange(
          nonEmptyParts.length > 4 ? nonEmptyParts[4] : null,
          allowDecimal: true,
        ) ??
        _extractRpeRange(raw);
    final notes = nonEmptyParts.length > 5
        ? nonEmptyParts.sublist(5).join(' | ').trim()
        : null;
    final role = _inferRoleFromText(notes ?? raw);
    final drop = _parseDropPercent(notes ?? raw);
    final amrap = (notes ?? raw).toLowerCase().contains('amrap');

    return _StructuredExercise(
      name: name,
      setCount: sets.clamp(1, 20).toInt(),
      repsRange: reps,
      restRange: rest,
      rpeRange: rpe,
      dropPercentRange: drop,
      notes: (notes == null || notes.isEmpty) ? null : notes,
      amrapLastSet: amrap,
      role: role,
    );
  }

  _Range? _extractRepsRange(String line) {
    final match =
        RegExp(r'(\d{1,2}\s*-\s*\d{1,2}|\d{1,2})\s*reps?', caseSensitive: false)
            .firstMatch(line);
    if (match == null) return null;
    return _parseRange(match.group(1));
  }

  _Range? _extractRestRange(String line) {
    final match = RegExp(
      r'(\d{1,3}\s*-\s*\d{1,3}|\d{1,3})\s*(sec|secs|seconds|min|mins|minutes)',
      caseSensitive: false,
    ).firstMatch(line);
    if (match == null) return null;
    return _parseRestRange('${match.group(1)} ${match.group(2)}');
  }

  _Range? _extractRpeRange(String line) {
    final match = RegExp(r'rpe\s*(\d(?:\.\d)?(?:\s*-\s*\d(?:\.\d)?)?)',
            caseSensitive: false)
        .firstMatch(line);
    if (match == null) return null;
    return _parseRange(match.group(1), allowDecimal: true);
  }

  String? _extractProgramFileText(File file) {
    final lower = file.path.toLowerCase();
    try {
      if (lower.endsWith('.xlsx')) {
        return _extractXlsxText(file);
      }
      if (lower.endsWith('.csv') || lower.endsWith('.txt')) {
        final text = file.readAsStringSync();
        return text.length > 30000 ? text.substring(0, 30000) : text;
      }
      if (lower.endsWith('.pdf')) {
        return _extractPdfText(file);
      }
      final text = file.readAsStringSync();
      return text.length > 30000 ? text.substring(0, 30000) : text;
    } catch (_) {
      return null;
    }
  }

  String? _extractXlsxText(File file) {
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;
    final buffer = StringBuffer();
    var sheetsWritten = 0;
    for (final entry in excel.tables.entries) {
      if (sheetsWritten >= 6) break;
      final sheet = entry.value;
      buffer.writeln('[Sheet] ${entry.key}');
      var rowCount = 0;
      for (final row in sheet.rows) {
        if (rowCount >= 180) break;
        final values = row
            .take(8)
            .map((cell) => (cell?.value?.toString() ?? '').trim())
            .toList();
        if (values.every((value) => value.isEmpty)) continue;
        buffer.writeln(values.join(' | '));
        rowCount += 1;
      }
      buffer.writeln();
      sheetsWritten += 1;
    }
    final text = buffer.toString().trim();
    if (text.isEmpty) return null;
    return text.length > 30000 ? text.substring(0, 30000) : text;
  }

  String? _extractPdfText(File file) {
    try {
      final bytes = file.readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final endPage = document.pages.count <= 5 ? document.pages.count - 1 : 4;
      final text = extractor.extractText(
        startPageIndex: 0,
        endPageIndex: endPage,
      );
      document.dispose();
      final trimmed = text.trim();
      if (trimmed.isEmpty) return null;
      return trimmed.length > 30000 ? trimmed.substring(0, 30000) : trimmed;
    } catch (_) {
      return null;
    }
  }

  String? _extractOpenAiResponseText(Map<String, dynamic> data) {
    final output = data['output'] as List<dynamic>? ?? const [];
    for (final item in output) {
      final content =
          (item as Map<String, dynamic>)['content'] as List<dynamic>? ??
              const [];
      for (final part in content) {
        final map = part as Map<String, dynamic>;
        final type = map['type']?.toString();
        if (type == 'output_text' || type == 'text') {
          final text = map['text']?.toString();
          if (text != null && text.trim().isNotEmpty) {
            return text;
          }
        }
      }
    }
    return null;
  }

  bool _openAiUsesResponses(String model) {
    return model.trim().toLowerCase().startsWith('gpt-5');
  }

  bool _openAiSupportsTemperature(String model) {
    return !_openAiUsesResponses(model);
  }

  String? _extractJsonObject(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  _Range? _rangeFromMinMax({
    required dynamic min,
    required dynamic max,
  }) {
    final minValue = _parseDouble(min);
    final maxValue = _parseDouble(max);
    if (minValue == null && maxValue == null) return null;
    return _Range(
      min: minValue ?? maxValue!,
      max: maxValue ?? minValue!,
    );
  }

  double? _parseDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    final text = value.toString().trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  int? _parseLeadingInt(String? text) {
    if (text == null) return null;
    final match = RegExp(r'(\d+)').firstMatch(text);
    if (match == null) return null;
    return int.tryParse(match.group(1)!);
  }

  bool? _parseBool(dynamic value) {
    if (value == null) return null;
    if (value is bool) return value;
    final normalized = value.toString().trim().toLowerCase();
    if (normalized == 'true' || normalized == '1' || normalized == 'yes') {
      return true;
    }
    if (normalized == 'false' || normalized == '0' || normalized == 'no') {
      return false;
    }
    return null;
  }

  String _normalizeRole(String? role) {
    final normalized = role?.trim().toUpperCase() ?? '';
    switch (normalized) {
      case 'TOP':
      case 'BACKOFF':
      case 'WARMUP':
        return normalized;
      default:
        return 'TOP';
    }
  }

  String _inferRoleFromText(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('warmup') || lower.contains('warm-up')) {
      return 'WARMUP';
    }
    if (lower.contains('backoff') ||
        lower.contains('back-off') ||
        lower.contains('drop')) {
      return 'BACKOFF';
    }
    return 'TOP';
  }

  Future<ImportResult> _importFromExcel(Excel excel,
      {String? programNameOverride}) async {
    _logImport(
      'importFromExcel begin tables=${excel.tables.length} first_sheet="${excel.tables.keys.isEmpty ? '' : excel.tables.keys.first}"',
    );
    _CanonicalMarkerScan? markers;
    if (excel.tables.isNotEmpty) {
      final firstRows = excel.tables.values.first.rows;
      markers = _scanCanonicalMarkers(firstRows);
      _logImport(
        'canonical_marker_scan start_rows=${markers.startRows} end_rows=${markers.endRows} repeat_row=${markers.repeatRow ?? -1}',
      );
      _logImport(
        'canonical_marker_rows start=${markers.startRowNumbers.join(',')} end=${markers.endRowNumbers.join(',')}',
      );
    }
    final canonical = _parseCanonicalProgramFromExcel(
      excel,
      programNameOverride: programNameOverride,
    );
    if (canonical != null) {
      _logCanonicalParseDebug(canonical);
      final dayMarkerRowsInNotes = canonical.program.days
          .expand((day) => day.exercises)
          .where((exercise) =>
              (exercise.notes ?? '').trim().toUpperCase().startsWith('DAY '))
          .length;
      if (dayMarkerRowsInNotes > 0) {
        _logImport(
          'WARNING: detected_day_markers_in_exercise_notes count=$dayMarkerRowsInNotes',
        );
      }
      final errors = canonical.issues
          .where((issue) => issue.severity == _ValidationSeverity.error)
          .toList();
      if (errors.isNotEmpty) {
        final lines = errors
            .map((issue) => '- [${issue.code}] ${issue.message}')
            .take(8)
            .join('\n');
        throw Exception('Program format validation failed:\n$lines');
      }
      _logImport(
        'importFromExcel parser=canonical days=${canonical.program.days.length} issues=${canonical.issues.length}',
      );
      return _importFromStructuredProgram(canonical.program);
    }
    _logImport('importFromExcel parser=legacy (canonical returned null)');
    if (markers != null && (markers.startRows > 0 || markers.endRows > 0)) {
      _logImport(
        'WARNING: canonical_markers_present_but_canonical_parser_null start_rows=${markers.startRows} end_rows=${markers.endRows}',
      );
      throw Exception(
        'Canonical markers were detected in this workbook, but canonical parsing returned null. Legacy fallback is disabled for this workbook shape to avoid incorrect imports.',
      );
    }

    final sheet = excel.tables.values.first;

    final programRepo = ProgramRepo(_db);
    final exerciseRepo = ExerciseRepo(_db);

    final rawName = programNameOverride?.trim().isNotEmpty == true
        ? programNameOverride!.trim()
        : excel.tables.keys.first;
    final resolvedName = await _uniqueProgramName(
        rawName.isEmpty ? 'Imported Program' : rawName);
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
      var descriptorCols =
          _descriptorColumnsForRow(rows[r]) ?? const _DescriptorColumns();
      final isRestDay = dayName.toLowerCase().contains('rest');
      final dayId = await programRepo.addProgramDay(
        programId: programId,
        dayIndex: dayIndex,
        dayName: dayName,
      );
      dayIndex += 1;

      r += 1;
      while (r < rows.length &&
          !_dayEndRow(rows[r]) &&
          _dayStartName(rows[r]) == null) {
        final row = rows[r];
        final descriptorRow = _descriptorColumnsForRow(row);
        if (!isRestDay) {
          if (descriptorRow != null) {
            descriptorCols = descriptorRow;
            r += 1;
            continue;
          }
          final exerciseName = _exerciseNameForRow(
            row,
            descriptorCols.exercise,
            setsCol: descriptorCols.sets,
          );
          if (exerciseName == null || exerciseName.isEmpty) {
            r += 1;
            continue;
          }
          final exerciseLower = exerciseName.toLowerCase();
          if (exerciseLower.contains('warm up') ||
              exerciseLower.contains('optional warm up')) {
            r += 1;
            continue;
          }
          final setsValue = _cellValue(row, descriptorCols.sets);
          final setsCount = _parseInt(setsValue) ??
              _parseLeadingInt(_cellString(row, descriptorCols.sets));
          if (setsCount == null || setsCount < 1) {
            r += 1;
            continue;
          }

          final repsValue = _cellValue(row, descriptorCols.reps);
          final restValue = _cellValue(row, descriptorCols.rest);
          final rpeValue = _cellValue(row, descriptorCols.rpe);
          final notes = _cellString(row, descriptorCols.notes);
          final repsRange = _parseRange(repsValue);

          final exerciseId = await _resolveExerciseId(
              exerciseRepo, exerciseName,
              createIfMissing: true);
          if (exerciseId == null) {
            missingExercises.add(exerciseName.trim());
            r += 1;
            continue;
          }
          await _maybeFillMuscles(exerciseId, exerciseName);
          final dayExerciseId = await programRepo.addProgramDayExercise(
            programDayId: dayId,
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

          final notesCandidate = _cellString(row, descriptorCols.notes);
          if (notesCandidate != null &&
              _isLikelyExerciseName(notesCandidate) &&
              r + 1 < rows.length &&
              !_dayEndRow(rows[r + 1]) &&
              _dayStartName(rows[r + 1]) == null) {
            final nextRow = rows[r + 1];
            final nextExercise = _exerciseNameForRow(
              nextRow,
              descriptorCols.exercise,
              setsCol: descriptorCols.sets,
            );
            final nextSetsValue = _cellValue(nextRow, descriptorCols.sets);
            final nextSetsCount = _parseInt(nextSetsValue) ??
                _parseLeadingInt(_cellString(nextRow, descriptorCols.sets));
            final nextNotes = _cellString(nextRow, descriptorCols.notes);
            if ((nextExercise == null || _looksLikeNote(nextExercise)) &&
                (nextNotes == null || !_dayEndRow(nextRow)) &&
                nextSetsCount != null &&
                nextSetsCount >= 1) {
              final nextRepsValue = _cellValue(nextRow, descriptorCols.reps);
              final nextRestValue = _cellValue(nextRow, descriptorCols.rest);
              final nextRpeValue = _cellValue(nextRow, descriptorCols.rpe);
              final nextRepsRange = _parseRange(nextRepsValue);
              final shiftedExerciseId = await _resolveExerciseId(
                  exerciseRepo, notesCandidate,
                  createIfMissing: true);
              if (shiftedExerciseId != null) {
                final shiftedDayExerciseId =
                    await programRepo.addProgramDayExercise(
                  programDayId: dayId,
                  exerciseId: shiftedExerciseId,
                  orderIndex: await _nextOrderIndex(programRepo, dayId),
                  notes: nextExercise,
                );
                exerciseCount += 1;

                final shiftedRpeRange =
                    _parseRange(nextRpeValue, allowDecimal: true);
                final shiftedRestRange = _parseRestRange(nextRestValue);
                final shiftedDropPercent =
                    _parseDropPercent(nextExercise ?? '');
                final shiftedBlocks = _buildBlocks(
                  setsCount: nextSetsCount,
                  repsRange: nextRepsRange,
                  restRange: shiftedRestRange,
                  rpeRange: shiftedRpeRange,
                  notes: nextExercise ?? '',
                  dropPercent: shiftedDropPercent,
                );
                await programRepo.replaceSetPlanBlocks(
                    shiftedDayExerciseId, shiftedBlocks);
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

    _logImport(
      'importFromExcel parser=legacy complete day_count=$dayIndex exercise_count=$exerciseCount missing=${missingExercises.length}',
    );
    return ImportResult(
      programId: programId,
      dayCount: dayIndex,
      exerciseCount: exerciseCount,
      missingExercises: missingExercises.toList()..sort(),
    );
  }

  _CanonicalParseResult? _parseCanonicalProgramFromExcel(
    Excel excel, {
    String? programNameOverride,
  }) {
    if (excel.tables.isEmpty) return null;
    final sheet = excel.tables.values.first;
    final rows = sheet.rows;
    if (rows.isEmpty) return null;

    final issues = <_ValidationIssue>[];
    final meta = <String, Object?>{};
    final days = <_StructuredProgramDay>[];
    final debugLines = <String>[];
    final terminatorRow = _findRepeatRow(rows);
    final parseLimit = terminatorRow ?? rows.length;
    debugLines.add(
      'sheet_rows=${rows.length} repeat_row=${terminatorRow ?? 'none'} parse_limit=$parseLimit',
    );
    if (terminatorRow != null) {
      final repeatDisplay = terminatorRow + 1;
      final start = terminatorRow - 2 < 0 ? 0 : terminatorRow - 2;
      final end = terminatorRow + 10 >= rows.length
          ? rows.length - 1
          : terminatorRow + 10;
      debugLines.add('repeat_context around_row=$repeatDisplay');
      for (var i = start; i <= end; i++) {
        debugLines.add(
          'row=${i + 1} preview=${_rowPreviewForLog(rows[i], maxColumns: 12)}',
        );
      }
    }

    var rowIndex = 0;
    var foundCanonicalBlock = false;
    var lastResolvedDayNumber = 0;
    var sawMalformedBoundary = false;
    while (rowIndex < parseLimit) {
      final row = rows[rowIndex];
      final boundary = _parseCanonicalBoundaryRow(row, rowIndex: rowIndex);
      if (boundary == null || boundary.tag != _BoundaryTag.start) {
        final first = _cellString(row, 0)?.trim() ?? '';
        if (first.toLowerCase().startsWith('day')) {
          debugLines.add(
            'row=${rowIndex + 1} ignored_non_start first="$first" preview=${_rowPreviewForLog(row)}',
          );
        }
        _captureCanonicalMetaRow(row, meta);
        rowIndex += 1;
        continue;
      }
      foundCanonicalBlock = true;
      final startDayNumber = boundary.dayNumber > 0
          ? boundary.dayNumber
          : (lastResolvedDayNumber + 1);
      if (boundary.dayNumber <= 0) {
        sawMalformedBoundary = true;
        debugLines.add(
          'row=${boundary.rowIndex + 1} inferred_day_number=$startDayNumber from malformed boundary',
        );
      }
      debugLines.add(
        'row=${boundary.rowIndex + 1} START day=$startDayNumber label="${boundary.label}" preview=${_rowPreviewForLog(row)}',
      );
      final dayPath = 'days[${days.length}]';
      final dayName = 'DAY $startDayNumber (${boundary.label})';
      final isRestDayByLabel = _isRestDayLabel(boundary.label);
      final immediateRowIndex = rowIndex + 1;
      if (immediateRowIndex >= parseLimit) {
        debugLines.add(
          'row=${boundary.rowIndex + 1} missing_immediate_row_for_start day=$startDayNumber',
        );
        issues.add(
          _ValidationIssue(
            severity: _ValidationSeverity.error,
            code: 'missing_end',
            path: dayPath,
            message:
                'Missing END marker for DAY $startDayNumber (${boundary.label}).',
          ),
        );
        days.add(
          _StructuredProgramDay(
            dayName: dayName,
            exercises: const [],
          ),
        );
        lastResolvedDayNumber = startDayNumber;
        break;
      }

      final immediateRow = rows[immediateRowIndex];
      final header = _parseCanonicalHeaderRow(immediateRow);
      debugLines.add(
        'row=${immediateRowIndex + 1} immediate_after_start preview=${_rowPreviewForLog(immediateRow)} header=${header == null ? 'no' : 'yes'}',
      );

      if (header == null) {
        final immediateBoundary = _parseCanonicalBoundaryRow(
          immediateRow,
          rowIndex: immediateRowIndex,
        );
        if (immediateBoundary != null &&
            immediateBoundary.tag == _BoundaryTag.end) {
          final immediateEndDayNumber = immediateBoundary.dayNumber > 0
              ? immediateBoundary.dayNumber
              : startDayNumber;
          if (immediateBoundary.dayNumber <= 0) {
            sawMalformedBoundary = true;
            debugLines.add(
              'row=${immediateRowIndex + 1} inferred_END_day_number=$immediateEndDayNumber from malformed boundary',
            );
          }
          debugLines.add(
            'row=${immediateRowIndex + 1} immediate_END day=$immediateEndDayNumber label="${immediateBoundary.label}"',
          );
          if (immediateEndDayNumber != startDayNumber) {
            issues.add(
              _ValidationIssue(
                severity: _ValidationSeverity.error,
                code: 'mismatched_day_number',
                path: dayPath,
                message:
                    'END day number $immediateEndDayNumber does not match START day $startDayNumber.',
              ),
            );
          }
          if (!_dayLabelsMatch(immediateBoundary.label, boundary.label)) {
            issues.add(
              _ValidationIssue(
                severity: _ValidationSeverity.error,
                code: 'mismatched_day_label',
                path: dayPath,
                message:
                    'END day label "${immediateBoundary.label}" does not match START label "${boundary.label}".',
              ),
            );
          }
          if (!isRestDayByLabel) {
            issues.add(
              _ValidationIssue(
                severity: _ValidationSeverity.error,
                code: 'training_day_missing_header',
                path: dayPath,
                message:
                    'Training day is missing immediate header row after START: Exercises | Sets | Reps | Rest | RPE | Notes.',
              ),
            );
          }
          days.add(
            _StructuredProgramDay(
              dayName: dayName,
              exercises: const [],
            ),
          );
          debugLines.add(
            'day="$dayName" interpreted_as_rest_or_empty exercises=0 next_row=${immediateRowIndex + 2}',
          );
          lastResolvedDayNumber = startDayNumber;
          rowIndex = immediateRowIndex + 1;
          continue;
        }

        debugLines.add(
          'row=${immediateRowIndex + 1} expected_header_or_end_but_found preview=${_rowPreviewForLog(immediateRow)}',
        );
        issues.add(
          _ValidationIssue(
            severity: _ValidationSeverity.error,
            code: isRestDayByLabel
                ? 'rest_day_unexpected_content'
                : 'training_day_missing_header',
            path: dayPath,
            message: isRestDayByLabel
                ? 'Rest day must have END row immediately after START.'
                : 'Training day is missing immediate header row after START: Exercises | Sets | Reps | Rest | RPE | Notes.',
          ),
        );
        days.add(
          _StructuredProgramDay(
            dayName: dayName,
            exercises: const [],
          ),
        );
        final nextStart = _findNextCanonicalStartRow(
          rows,
          startRow: immediateRowIndex + 1,
          parseLimit: parseLimit,
        );
        debugLines.add(
          'day="$dayName" skipping_to_next_start row=${nextStart == null ? 'none' : (nextStart + 1)}',
        );
        lastResolvedDayNumber = startDayNumber;
        rowIndex = nextStart ?? parseLimit;
        continue;
      }
      debugLines.add(
        'day="$dayName" training_header columns exercise=${header.exercise} sets=${header.sets} reps=${header.reps} rest=${header.rest ?? -1} rpe=${header.rpe} notes=${header.notes}',
      );

      final exercises = <_StructuredExercise>[];
      var cursor = immediateRowIndex + 1;
      var consumedUntil = parseLimit;
      var foundEnd = false;
      while (cursor < parseLimit) {
        final boundaryAtCursor =
            _parseCanonicalBoundaryRow(rows[cursor], rowIndex: cursor);
        if (boundaryAtCursor != null) {
          if (boundaryAtCursor.tag == _BoundaryTag.start) {
            final nextStartDayNumber = boundaryAtCursor.dayNumber > 0
                ? boundaryAtCursor.dayNumber
                : (startDayNumber + 1);
            debugLines.add(
              'row=${cursor + 1} encountered_next_START_before_END day=$nextStartDayNumber label="${boundaryAtCursor.label}"',
            );
            issues.add(
              _ValidationIssue(
                severity: _ValidationSeverity.error,
                code: 'missing_end',
                path: dayPath,
                message:
                    'Missing END marker for DAY $startDayNumber (${boundary.label}) before next START.',
              ),
            );
            consumedUntil = cursor;
            foundEnd = true;
            break;
          }

          final resolvedEndDayNumber = boundaryAtCursor.dayNumber > 0
              ? boundaryAtCursor.dayNumber
              : startDayNumber;
          if (boundaryAtCursor.dayNumber <= 0) {
            sawMalformedBoundary = true;
          }
          final dayNumberMatches = resolvedEndDayNumber == startDayNumber;
          final dayLabelMatches =
              _dayLabelsMatch(boundaryAtCursor.label, boundary.label);
          if (!dayNumberMatches || !dayLabelMatches) {
            debugLines.add(
              'row=${cursor + 1} mismatched_END found day=$resolvedEndDayNumber label="${boundaryAtCursor.label}" expected_day=$startDayNumber expected_label="${boundary.label}"',
            );
            if (!dayNumberMatches) {
              issues.add(
                _ValidationIssue(
                  severity: _ValidationSeverity.error,
                  code: 'mismatched_day_number',
                  path: dayPath,
                  message:
                      'END day number $resolvedEndDayNumber does not match START day $startDayNumber.',
                ),
              );
            }
            if (!dayLabelMatches) {
              issues.add(
                _ValidationIssue(
                  severity: _ValidationSeverity.error,
                  code: 'mismatched_day_label',
                  path: dayPath,
                  message:
                      'END day label "${boundaryAtCursor.label}" does not match START label "${boundary.label}".',
                ),
              );
            }
            cursor += 1;
            continue;
          }

          debugLines.add(
            'row=${cursor + 1} matched_END day=$resolvedEndDayNumber label="${boundaryAtCursor.label}"',
          );
          consumedUntil = cursor + 1;
          foundEnd = true;
          break;
        }

        final dataRow = rows[cursor];
        if (!_rowHasAnyContent(dataRow)) {
          cursor += 1;
          continue;
        }
        final exercisePath = '$dayPath.exercises[${exercises.length}]';
        final name = _cellString(dataRow, header.exercise);
        if (name == null || name.trim().isEmpty) {
          issues.add(
            _ValidationIssue(
              severity: _ValidationSeverity.warning,
              code: 'missing_exercise_name',
              path: exercisePath,
              message: 'Skipped row with missing exercise name.',
            ),
          );
          cursor += 1;
          continue;
        }

        final setsRaw = _cellValue(dataRow, header.sets);
        final sets =
            _parseInt(setsRaw) ?? _parseLeadingInt(_rawToString(setsRaw));
        if (sets == null || sets < 1) {
          issues.add(
            _ValidationIssue(
              severity: _ValidationSeverity.warning,
              code: 'missing_sets',
              path: '$exercisePath.sets',
              message:
                  'Skipped exercise "$name" because sets is missing or invalid.',
            ),
          );
          cursor += 1;
          continue;
        }

        final repsRaw = _cellValue(dataRow, header.reps);
        final restRaw =
            header.rest == null ? null : _cellValue(dataRow, header.rest!);
        final rpeRaw = _cellValue(dataRow, header.rpe);
        final notesRaw = _cellString(dataRow, header.notes);
        final notesText = notesRaw?.trim();
        debugLines.add(
          'row=${cursor + 1} exercise_raw name="${name.trim()}" sets="${_rawToString(setsRaw) ?? ''}" reps="${_rawToString(repsRaw) ?? ''}" rest="${_rawToString(restRaw) ?? ''}" rpe="${_rawToString(rpeRaw) ?? ''}"',
        );

        final rowFlags = <String>[];
        final repsRange = _normalizeRangeField(
          rawValue: repsRaw,
          fieldName: 'reps',
          path: '$exercisePath.reps',
          issues: issues,
          flagsOut: rowFlags,
        );
        final restRange = header.rest == null
            ? null
            : _normalizeRestField(
                rawValue: restRaw,
                path: '$exercisePath.rest',
                issues: issues,
              );
        final rpeRange = _normalizeRangeField(
          rawValue: rpeRaw,
          fieldName: 'rpe',
          path: '$exercisePath.rpe',
          issues: issues,
          flagsOut: rowFlags,
          allowDecimal: true,
        );
        final drop = _parseDropPercent(notesText ?? '');
        debugLines.add(
          'row=${cursor + 1} exercise_parsed name="${name.trim()}" reps=${_rangeToLog(repsRange)} rest=${_rangeToLog(restRange)} rpe=${_rangeToLog(rpeRange)} drop=${_rangeToLog(drop)} flags=${rowFlags.isEmpty ? '-' : rowFlags.join('|')} notes="${_truncateForLog(notesText, maxChars: 200)}"',
        );

        exercises.add(
          _StructuredExercise(
            name: name.trim(),
            setCount: sets.clamp(1, 20).toInt(),
            repsRange: repsRange,
            restRange: restRange,
            rpeRange: rpeRange,
            dropPercentRange: drop,
            notes: notesText?.isEmpty == true ? null : notesText,
            amrapLastSet: (notesText ?? '').toLowerCase().contains('amrap'),
            role: _inferRoleFromText(notesText ?? ''),
            rawValues: {
              'sets': _rawToString(setsRaw),
              'reps': _rawToString(repsRaw),
              'rest': _rawToString(restRaw),
              'rpe': _rawToString(rpeRaw),
              'notes': notesText,
            },
            flags: rowFlags,
          ),
        );
        cursor += 1;
      }

      if (!foundEnd) {
        issues.add(
          _ValidationIssue(
            severity: _ValidationSeverity.error,
            code: 'missing_end',
            path: dayPath,
            message:
                'Missing END marker for DAY $startDayNumber (${boundary.label}).',
          ),
        );
      }
      if (exercises.isEmpty) {
        issues.add(
          _ValidationIssue(
            severity: _ValidationSeverity.warning,
            code: 'empty_training_day',
            path: dayPath,
            message: 'Training day has no parsed exercises.',
          ),
        );
      }
      days.add(
        _StructuredProgramDay(
          dayName: dayName,
          exercises: exercises,
        ),
      );
      debugLines.add(
        'day="$dayName" parsed_exercises=${exercises.length} next_row=${consumedUntil + 1}',
      );
      lastResolvedDayNumber = startDayNumber;
      rowIndex = consumedUntil;
    }

    if (!foundCanonicalBlock) return null;
    _appendInferredTrailingRestPlaceholderIfNeeded(
      days: days,
      issues: issues,
      debugLines: debugLines,
      sawMalformedBoundary: sawMalformedBoundary,
    );

    final baseName = programNameOverride?.trim().isNotEmpty == true
        ? programNameOverride!.trim()
        : (excel.tables.keys.first.trim().isEmpty
            ? 'Imported Program'
            : excel.tables.keys.first.trim());
    final program = _StructuredProgram(
      programName: baseName,
      days: days,
      meta: meta,
    );
    debugLines.add(
      'final_summary days=${days.length} issues=${issues.length} meta_keys=${meta.keys.join(',')}',
    );
    return _CanonicalParseResult(
      program: program,
      issues: issues,
      debugLines: debugLines,
    );
  }

  void _logCanonicalParseDebug(_CanonicalParseResult canonical) {
    _logImport('[canonical][debug] BEGIN');
    for (final line in canonical.debugLines) {
      _logImport('[canonical][trace] $line');
    }

    final program = canonical.program;
    _logImport(
      '[canonical][summary] program="${program.programName}" days=${program.days.length} issues=${canonical.issues.length}',
    );
    for (var dayIndex = 0; dayIndex < program.days.length; dayIndex++) {
      final day = program.days[dayIndex];
      _logImport(
        '[canonical][day] index=${dayIndex + 1} name="${day.dayName}" exercises=${day.exercises.length}',
      );
      for (var exerciseIndex = 0;
          exerciseIndex < day.exercises.length;
          exerciseIndex++) {
        final exercise = day.exercises[exerciseIndex];
        _logImport(
          '[canonical][exercise] day=${dayIndex + 1} order=${exerciseIndex + 1} name="${exercise.name}" sets=${exercise.setCount} reps=${_rangeToLog(exercise.repsRange)} rest=${_rangeToLog(exercise.restRange)} rpe=${_rangeToLog(exercise.rpeRange)} drop=${_rangeToLog(exercise.dropPercentRange)} raw_sets="${exercise.rawValues['sets'] ?? ''}" raw_reps="${exercise.rawValues['reps'] ?? ''}" raw_rest="${exercise.rawValues['rest'] ?? ''}" raw_rpe="${exercise.rawValues['rpe'] ?? ''}" raw_notes="${_truncateForLog(exercise.rawValues['notes'], maxChars: 200)}" flags=${exercise.flags.isEmpty ? '-' : exercise.flags.join('|')}',
        );
      }
    }
    if (program.meta.isNotEmpty) {
      _logImport('[canonical][meta] ${jsonEncode(program.meta)}');
    }
    for (final issue in canonical.issues) {
      _logImport(
        '[canonical][issue][${issue.severity.name}][${issue.code}] ${issue.path}: ${issue.message}',
      );
    }
    _logImport('[canonical][debug] END');
  }

  void _logImport(String message) {
    final formatted = '[Import] $message';
    debugPrint(formatted);
    stderr.writeln(formatted);
  }

  String _fingerprintBytes(Uint8List bytes) {
    const fnvOffsetBasis = 0xcbf29ce484222325;
    const fnvPrime = 0x100000001b3;

    var hash = fnvOffsetBasis.toUnsigned(64);
    for (final byte in bytes) {
      hash ^= byte;
      hash = (hash * fnvPrime).toUnsigned(64);
    }

    final headCount = bytes.length < 8 ? bytes.length : 8;
    final tailCount = bytes.length < 8 ? bytes.length : 8;
    final head = headCount == 0
        ? '-'
        : bytes
            .sublist(0, headCount)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    final tail = tailCount == 0
        ? '-'
        : bytes
            .sublist(bytes.length - tailCount)
            .map((b) => b.toRadixString(16).padLeft(2, '0'))
            .join();
    return 'len=${bytes.length} fnv64=0x${hash.toUnsigned(64).toRadixString(16).padLeft(16, '0')} head=$head tail=$tail';
  }

  _CanonicalMarkerScan _scanCanonicalMarkers(List<List<Data?>> rows) {
    var startRows = 0;
    var endRows = 0;
    final repeatRowIndex = _findRepeatRow(rows);
    final repeatRow = repeatRowIndex == null ? null : repeatRowIndex + 1;
    final startRowNumbers = <int>[];
    final endRowNumbers = <int>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      final first = _cellString(row, 0)?.trim().toLowerCase() ?? '';
      final second = _cellString(row, 1)?.trim().toLowerCase() ?? '';
      final third = _cellString(row, 2)?.trim() ?? '';
      final genericBoundaryLike = (second == 'start' || second == 'end') &&
          third.startsWith('(') &&
          third.endsWith(')');
      final repeatBoundaryLike = first == 'repeat' &&
          (second == 'start' || second == 'end') &&
          third.startsWith('(') &&
          third.endsWith(')');
      if (repeatBoundaryLike) {
        if (second == 'start') {
          startRows += 1;
          startRowNumbers.add(i + 1);
        } else {
          endRows += 1;
          endRowNumbers.add(i + 1);
        }
        continue;
      }
      if (genericBoundaryLike &&
          !RegExp(r'^day\s*\d+\s*$', caseSensitive: false).hasMatch(first)) {
        if (second == 'start') {
          startRows += 1;
          startRowNumbers.add(i + 1);
        } else {
          endRows += 1;
          endRowNumbers.add(i + 1);
        }
        continue;
      }
      if (RegExp(r'^day\s*\d+\s*$').hasMatch(first)) {
        if (second == 'start') {
          startRows += 1;
          startRowNumbers.add(i + 1);
        }
        if (second == 'end') {
          endRows += 1;
          endRowNumbers.add(i + 1);
        }
      } else if (RegExp(r'^day\s*\d+\s+end\s*$', caseSensitive: false)
          .hasMatch(first)) {
        endRows += 1;
        endRowNumbers.add(i + 1);
      }
    }
    return _CanonicalMarkerScan(
      startRows: startRows,
      endRows: endRows,
      repeatRow: repeatRow,
      startRowNumbers: startRowNumbers,
      endRowNumbers: endRowNumbers,
    );
  }

  String _rowPreviewForLog(List<Data?> row, {int maxColumns = 8}) {
    final limit = row.length < maxColumns ? row.length : maxColumns;
    final values = <String>[];
    for (var i = 0; i < limit; i++) {
      final text = _cellString(row, i);
      if (text == null || text.trim().isEmpty) continue;
      values.add('c${i + 1}="${_truncateForLog(text, maxChars: 60)}"');
    }
    if (values.isEmpty) return '<empty>';
    return values.join(' | ');
  }

  String _rangeToLog(_Range? range) {
    if (range == null) return 'null';
    return '${range.min}-${range.max}';
  }

  String _truncateForLog(String? value, {int maxChars = 160}) {
    if (value == null) return '';
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.length <= maxChars) return normalized;
    return '${normalized.substring(0, maxChars)}...';
  }

  int? _findRepeatRow(List<List<Data?>> rows) {
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i];
      if (_isTerminatorRepeatRow(row)) {
        return i;
      }
    }
    return null;
  }

  bool _isTerminatorRepeatRow(List<Data?> row) {
    final first = _cellString(row, 0)?.trim().toLowerCase() ?? '';
    if (first != 'repeat') return false;
    if (_isRepeatBoundaryLikeRow(row)) return false;
    for (var i = 1; i < row.length; i++) {
      final token = _cellString(row, i);
      if (token != null && token.trim().isNotEmpty) {
        return false;
      }
    }
    return true;
  }

  bool _isRepeatBoundaryLikeRow(List<Data?> row) {
    final first = _cellString(row, 0)?.trim().toLowerCase() ?? '';
    final second = _cellString(row, 1)?.trim().toLowerCase() ?? '';
    final third = _cellString(row, 2)?.trim() ?? '';
    if (first != 'repeat') return false;
    if (second != 'start' && second != 'end') return false;
    return third.startsWith('(') && third.endsWith(')');
  }

  _CanonicalBoundaryRow? _parseCanonicalBoundaryRow(
    List<Data?> row, {
    required int rowIndex,
  }) {
    if (row.isEmpty) return null;
    final first = _cellString(row, 0)?.trim() ?? '';
    final second = _cellString(row, 1)?.trim() ?? '';
    final third = _cellString(row, 2)?.trim() ?? '';

    final splitDayRegex = RegExp(r'^day\s*(\d+)\s*$', caseSensitive: false);
    final splitTagRegex = RegExp(r'^(start|end)$', caseSensitive: false);

    final splitMatch = splitDayRegex.firstMatch(first);
    if (splitMatch != null &&
        splitTagRegex.hasMatch(second) &&
        third.startsWith('(') &&
        third.endsWith(')')) {
      final dayNumber = int.tryParse(splitMatch.group(1) ?? '');
      if (dayNumber == null) return null;
      final tag = second.toUpperCase();
      final label = third.substring(1, third.length - 1).trim();
      return _CanonicalBoundaryRow(
        dayNumber: dayNumber,
        label: _normalizeDayLabel(label),
        tag: tag == 'START' ? _BoundaryTag.start : _BoundaryTag.end,
        rowIndex: rowIndex,
      );
    }

    if (_isRepeatBoundaryLikeRow(row)) {
      final tag = second.toUpperCase();
      final label = third.substring(1, third.length - 1).trim();
      return _CanonicalBoundaryRow(
        dayNumber: -1,
        label: _normalizeDayLabel(label),
        tag: tag == 'START' ? _BoundaryTag.start : _BoundaryTag.end,
        rowIndex: rowIndex,
      );
    }

    // Some sheets decode corrupted shared-string values in column A but still
    // preserve canonical boundary shape in columns B/C: "<token>" | START/END | "(LABEL)".
    if (splitTagRegex.hasMatch(second) &&
        third.startsWith('(') &&
        third.endsWith(')')) {
      final tag = second.toUpperCase();
      final label = third.substring(1, third.length - 1).trim();
      return _CanonicalBoundaryRow(
        dayNumber: -1,
        label: _normalizeDayLabel(label),
        tag: tag == 'START' ? _BoundaryTag.start : _BoundaryTag.end,
        rowIndex: rowIndex,
      );
    }

    final compactStartRegex =
        RegExp(r'^day\s*(\d+)\s*\(([^)]*)\)\s*$', caseSensitive: false);
    final compactEndRegex =
        RegExp(r'^day\s*(\d+)\s+end\s*$', caseSensitive: false);
    final compactStart = compactStartRegex.firstMatch(first);
    if (compactStart != null) {
      final dayNumber = int.tryParse(compactStart.group(1) ?? '');
      if (dayNumber == null) return null;
      return _CanonicalBoundaryRow(
        dayNumber: dayNumber,
        label: _normalizeDayLabel(compactStart.group(2)),
        tag: _BoundaryTag.start,
        rowIndex: rowIndex,
      );
    }
    final compactEnd = compactEndRegex.firstMatch(first);
    if (compactEnd != null) {
      final dayNumber = int.tryParse(compactEnd.group(1) ?? '');
      if (dayNumber == null) return null;
      return _CanonicalBoundaryRow(
        dayNumber: dayNumber,
        label: 'UNLABELED',
        tag: _BoundaryTag.end,
        rowIndex: rowIndex,
      );
    }

    return null;
  }

  String _normalizeDayLabel(String? label) {
    if (label == null || label.trim().isEmpty) return 'UNLABELED';
    var normalized = label.trim();
    if (normalized.startsWith('(') &&
        normalized.endsWith(')') &&
        normalized.length > 2) {
      normalized = normalized.substring(1, normalized.length - 1).trim();
    }
    return normalized.isEmpty ? 'UNLABELED' : normalized;
  }

  bool _isRestDayLabel(String label) {
    final normalized = label.toLowerCase().trim();
    return normalized == 'rest' || normalized.contains('rest');
  }

  bool _dayLabelsMatch(String a, String b) {
    return _normalizeDayLabel(a).toLowerCase().trim() ==
        _normalizeDayLabel(b).toLowerCase().trim();
  }

  void _appendInferredTrailingRestPlaceholderIfNeeded({
    required List<_StructuredProgramDay> days,
    required List<_ValidationIssue> issues,
    required List<String> debugLines,
    required bool sawMalformedBoundary,
  }) {
    if (!sawMalformedBoundary || days.isEmpty) return;
    final dayByNumber = <int, _StructuredProgramDay>{};
    for (final day in days) {
      final number = _dayNumberFromDayName(day.dayName);
      if (number != null) {
        dayByNumber[number] = day;
      }
    }
    if (dayByNumber.isEmpty) return;

    final ordered = dayByNumber.keys.toList()..sort();
    final maxParsed = ordered.last;
    final nextDay = maxParsed + 1;
    if (dayByNumber.containsKey(nextDay)) return;

    final labelByModulo = <int, String>{};
    for (final number in ordered) {
      final label = _dayLabelFromDayName(dayByNumber[number]!.dayName);
      if (label == null || label.isEmpty) continue;
      labelByModulo[number % 4] ??= label;
    }
    if (!labelByModulo.containsKey(0) ||
        !labelByModulo.containsKey(1) ||
        !labelByModulo.containsKey(2) ||
        !labelByModulo.containsKey(3)) {
      return;
    }
    final restLabel = labelByModulo[0]!;
    if (!_isRestDayLabel(restLabel)) return;
    if (maxParsed % 4 != 3) return;

    final inferredLabel = labelByModulo[nextDay % 4] ?? restLabel;
    if (!_isRestDayLabel(inferredLabel)) return;

    final inferredDayName = 'DAY $nextDay ($inferredLabel)';
    days.add(
      _StructuredProgramDay(
        dayName: inferredDayName,
        exercises: const [],
      ),
    );
    final inferredIndex = days.length - 1;
    issues.add(
      _ValidationIssue(
        severity: _ValidationSeverity.warning,
        code: 'inferred_rest_placeholder',
        path: 'days[$inferredIndex]',
        message:
            'Added missing trailing rest placeholder "$inferredDayName" because canonical boundaries were malformed.',
      ),
    );
    debugLines.add(
      'inferred_trailing_rest day=$nextDay label="$inferredLabel" reason=malformed_boundary_and_cycle',
    );

    days.sort((a, b) {
      final aNumber = _dayNumberFromDayName(a.dayName) ?? 1 << 30;
      final bNumber = _dayNumberFromDayName(b.dayName) ?? 1 << 30;
      return aNumber.compareTo(bNumber);
    });
  }

  int? _dayNumberFromDayName(String dayName) {
    final match =
        RegExp(r'^day\s+(\d+)\s*(?:\(|$)', caseSensitive: false).firstMatch(
      dayName.trim(),
    );
    if (match == null) return null;
    return int.tryParse(match.group(1) ?? '');
  }

  String? _dayLabelFromDayName(String dayName) {
    final match = RegExp(r'^day\s+\d+\s*\(([^)]*)\)\s*$', caseSensitive: false)
        .firstMatch(dayName.trim());
    if (match == null) return null;
    return _normalizeDayLabel(match.group(1));
  }

  int? _findNextCanonicalStartRow(
    List<List<Data?>> rows, {
    required int startRow,
    required int parseLimit,
  }) {
    for (var i = startRow; i < parseLimit; i++) {
      final boundary = _parseCanonicalBoundaryRow(rows[i], rowIndex: i);
      if (boundary != null && boundary.tag == _BoundaryTag.start) {
        return i;
      }
    }
    return null;
  }

  bool _rowHasAnyContent(List<Data?> row) {
    for (final cell in row) {
      final value = cell?.value;
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return true;
    }
    return false;
  }

  void _captureCanonicalMetaRow(List<Data?> row, Map<String, Object?> meta) {
    final maxScan = row.length < 8 ? row.length : 8;
    for (var i = 0; i < maxScan; i++) {
      final text = _cellString(row, i);
      if (text == null || text.trim().isEmpty) continue;
      final token = text.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
      if (token == 'progressiontype') {
        for (var j = i + 1; j < row.length; j++) {
          final value = _cellString(row, j);
          if (value == null || value.trim().isEmpty) continue;
          meta['progression_type'] = value.trim();
          return;
        }
      }
    }
  }

  _CanonicalHeaderColumns? _parseCanonicalHeaderRow(List<Data?> row) {
    if (row.isEmpty) return null;
    final tokens = <MapEntry<int, String>>[];
    for (var i = 0; i < row.length; i++) {
      final normalized = _normalizeHeaderToken(_cellString(row, i) ?? '');
      if (normalized == null) continue;
      tokens.add(MapEntry(i, normalized));
    }
    if (tokens.length < 5) return null;

    final matchedIndices = <String, int>{};
    var cursor = 0;

    int? consume(String wanted) {
      while (cursor < tokens.length) {
        final token = tokens[cursor];
        cursor += 1;
        if (token.value == wanted) return token.key;
      }
      return null;
    }

    final exercise = consume('exercise');
    final sets = consume('sets');
    final reps = consume('reps');
    if (exercise == null || sets == null || reps == null) {
      return null;
    }
    matchedIndices['exercise'] = exercise;
    matchedIndices['sets'] = sets;
    matchedIndices['reps'] = reps;

    int? rest;
    if (cursor < tokens.length && tokens[cursor].value == 'rest') {
      rest = tokens[cursor].key;
      cursor += 1;
    }

    final rpe = consume('rpe');
    final notes = consume('notes');
    if (rpe == null || notes == null) return null;
    matchedIndices['rpe'] = rpe;
    matchedIndices['notes'] = notes;

    return _CanonicalHeaderColumns(
      exercise: matchedIndices['exercise']!,
      sets: matchedIndices['sets']!,
      reps: matchedIndices['reps']!,
      rest: rest,
      rpe: matchedIndices['rpe']!,
      notes: matchedIndices['notes']!,
    );
  }

  _Range? _normalizeRangeField({
    required dynamic rawValue,
    required String fieldName,
    required String path,
    required List<_ValidationIssue> issues,
    required List<String> flagsOut,
    bool allowDecimal = false,
  }) {
    if (rawValue == null) return null;
    final rawString = _rawToString(rawValue);
    if (rawString == null || rawString.trim().isEmpty) return null;

    _Range? range;
    final dateStringPattern = RegExp(r'^\d{4}-\d{2}-\d{2}(?:[T ][0-9:.+-]+)?$');
    if (rawValue is DateTime) {
      range = _Range(
        min: rawValue.month.toDouble(),
        max: rawValue.day.toDouble(),
      );
      flagsOut.add('excel_date_coercion_recovered');
      issues.add(
        _ValidationIssue(
          severity: _ValidationSeverity.warning,
          code: 'excel_date_coercion_recovered',
          path: path,
          message:
              'Recovered ${fieldName.toUpperCase()} range ${range.minInt}-${range.maxInt} from date-like value "$rawString".',
        ),
      );
    } else {
      range = _parseRange(rawValue, allowDecimal: allowDecimal);
      if (range != null && dateStringPattern.hasMatch(rawString.trim())) {
        flagsOut.add('excel_date_coercion_recovered');
        issues.add(
          _ValidationIssue(
            severity: _ValidationSeverity.warning,
            code: 'excel_date_coercion_recovered',
            path: path,
            message:
                'Recovered ${fieldName.toUpperCase()} range ${range.minInt}-${range.maxInt} from date-like value "$rawString".',
          ),
        );
      }
    }

    if (range == null) {
      issues.add(
        _ValidationIssue(
          severity: _ValidationSeverity.warning,
          code:
              fieldName == 'rpe' ? 'unparsed_rpe_value' : 'unparsed_reps_value',
          path: path,
          message: 'Could not parse $fieldName from raw value "$rawString".',
        ),
      );
      return null;
    }
    if (range.min > range.max) {
      issues.add(
        _ValidationIssue(
          severity: _ValidationSeverity.warning,
          code: 'invalid_range_order',
          path: path,
          message:
              'Range min (${range.min}) is greater than max (${range.max}); values were swapped.',
        ),
      );
      return _Range(min: range.max, max: range.min);
    }
    return range;
  }

  _Range? _normalizeRestField({
    required dynamic rawValue,
    required String path,
    required List<_ValidationIssue> issues,
  }) {
    if (rawValue == null) return null;
    final rawString = _rawToString(rawValue);
    if (rawString == null || rawString.trim().isEmpty) return null;
    final range = _parseRestRange(rawValue);
    if (range == null) {
      issues.add(
        _ValidationIssue(
          severity: _ValidationSeverity.warning,
          code: 'unparsed_rest_value',
          path: path,
          message: 'Could not parse rest from raw value "$rawString".',
        ),
      );
      return null;
    }
    if (range.min > range.max) {
      issues.add(
        _ValidationIssue(
          severity: _ValidationSeverity.warning,
          code: 'invalid_range_order',
          path: path,
          message:
              'Rest range min (${range.min}) is greater than max (${range.max}); values were swapped.',
        ),
      );
      return _Range(min: range.max, max: range.min);
    }
    return range;
  }

  String? _rawToString(dynamic rawValue) {
    if (rawValue == null) return null;
    if (rawValue is DateTime) return rawValue.toIso8601String();
    return rawValue.toString();
  }

  Future<ExerciseScanResult> _scanFromExcel(Excel excel) async {
    final canonical = _parseCanonicalProgramFromExcel(excel);
    if (canonical != null) {
      final exerciseRepo = ExerciseRepo(_db);
      final missing = <String>{};
      final seen = <String>{};
      var total = 0;

      for (final day in canonical.program.days) {
        for (final exercise in day.exercises) {
          final key = exercise.name.toLowerCase().trim();
          if (key.isEmpty || seen.contains(key)) continue;
          seen.add(key);
          total += 1;
          final exists = await _exerciseExists(exerciseRepo, exercise.name);
          if (!exists) {
            missing.add(exercise.name.trim());
          } else {
            final id = await _resolveExerciseId(
              exerciseRepo,
              exercise.name,
              createIfMissing: false,
            );
            if (id != null) {
              await _maybeFillMuscles(id, exercise.name);
            }
          }
        }
      }

      return ExerciseScanResult(
        totalExercises: total,
        missingExercises: missing.toList()..sort(),
      );
    }

    final sheet = excel.tables.values.first;

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
      var descriptorCols =
          _descriptorColumnsForRow(rows[r]) ?? const _DescriptorColumns();
      final isRestDay = dayName.toLowerCase().contains('rest');
      r += 1;
      while (r < rows.length &&
          !_dayEndRow(rows[r]) &&
          _dayStartName(rows[r]) == null) {
        final row = rows[r];
        final descriptorRow = _descriptorColumnsForRow(row);
        if (!isRestDay) {
          if (descriptorRow != null) {
            descriptorCols = descriptorRow;
            r += 1;
            continue;
          }
          final exerciseName = _exerciseNameForRow(
            row,
            descriptorCols.exercise,
            setsCol: descriptorCols.sets,
          );
          if (exerciseName == null || exerciseName.isEmpty) {
            r += 1;
            continue;
          }
          final exerciseLower = exerciseName.toLowerCase();
          if (exerciseLower.contains('warm up') ||
              exerciseLower.contains('optional warm up')) {
            r += 1;
            continue;
          }
          final setsValue = _cellValue(row, descriptorCols.sets);
          final setsCount = _parseInt(setsValue) ??
              _parseLeadingInt(_cellString(row, descriptorCols.sets));
          if (setsCount == null || setsCount < 1) {
            r += 1;
            continue;
          }
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
            final byId = await _resolveExerciseId(exerciseRepo, exerciseName,
                createIfMissing: false);
            if (byId != null) {
              await _maybeFillMuscles(byId, exerciseName);
            }
          }

          final notesCandidate = _cellString(row, descriptorCols.notes);
          if (notesCandidate != null &&
              _isLikelyExerciseName(notesCandidate) &&
              r + 1 < rows.length &&
              !_dayEndRow(rows[r + 1]) &&
              _dayStartName(rows[r + 1]) == null) {
            final nextRow = rows[r + 1];
            final nextExercise = _exerciseNameForRow(
              nextRow,
              descriptorCols.exercise,
              setsCol: descriptorCols.sets,
            );
            final nextSetsValue = _cellValue(nextRow, descriptorCols.sets);
            final nextSetsCount = _parseInt(nextSetsValue) ??
                _parseLeadingInt(_cellString(nextRow, descriptorCols.sets));
            final nextNotes = _cellString(nextRow, descriptorCols.notes);
            if ((nextExercise == null || _looksLikeNote(nextExercise)) &&
                (nextNotes == null || !_dayEndRow(nextRow)) &&
                nextSetsCount != null &&
                nextSetsCount >= 1) {
              final shiftedKey = notesCandidate.toLowerCase().trim();
              if (!seen.contains(shiftedKey)) {
                seen.add(shiftedKey);
                total += 1;
                final existsShifted =
                    await _exerciseExists(exerciseRepo, notesCandidate);
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
    final token = _findDayTokenInRow(row);
    if (token == null) return null;
    final compact = token.replaceAll(RegExp(r'\s+'), ' ').trim();
    final upper = compact.toUpperCase();
    if (!upper.startsWith('DAY')) return null;
    if (upper.contains('END')) return null;
    final match = RegExp(
      r'^DAY\s*(\d+)(?:\s*\(([^)]*)\))?',
      caseSensitive: false,
    ).firstMatch(compact);
    if (match == null) return null;
    final dayNumber = match.group(1);
    final label = match.group(2)?.trim();
    if (dayNumber == null || dayNumber.isEmpty) return null;
    if (label == null || label.isEmpty) {
      return 'DAY $dayNumber';
    }
    return 'DAY $dayNumber ($label)';
  }

  bool _dayEndRow(List<Data?> row) {
    final token = _findDayTokenInRow(row);
    if (token == null) return false;
    final compact = token.replaceAll(RegExp(r'\s+'), ' ').trim().toUpperCase();
    return compact.startsWith('DAY') && compact.contains('END');
  }

  String? _findDayTokenInRow(List<Data?> row) {
    if (row.isEmpty) return null;
    final maxScan = row.length < 8 ? row.length : 8;
    for (var i = 0; i < maxScan; i++) {
      final text = _cellString(row, i);
      if (text == null || text.trim().isEmpty) continue;
      final compact = text.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (compact.toUpperCase().startsWith('DAY')) {
        return compact;
      }
    }
    return null;
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

  String? _exerciseNameForRow(
    List<Data?> row,
    int exerciseCol, {
    int? setsCol,
  }) {
    String? direct = _cellString(row, exerciseCol);
    if (direct == null || direct.isEmpty) {
      final upperBound = setsCol == null ? row.length : setsCol;
      for (var i = 0; i < upperBound && i < row.length; i++) {
        final candidate = _cellString(row, i);
        if (candidate == null || candidate.isEmpty) continue;
        direct = candidate;
        break;
      }
    }
    if (direct == null || direct.isEmpty) return null;
    if (_isHeaderToken(direct)) return null;
    if (_looksLikeNote(direct)) return null;
    if (_isDayMarker(direct)) return null;
    return direct;
  }

  _DescriptorColumns? _descriptorColumnsForRow(List<Data?> row) {
    int? exercise;
    int? sets;
    int? reps;
    int? rest;
    int? rpe;
    int? notes;

    for (var i = 0; i < row.length; i++) {
      final text = _cellString(row, i);
      if (text == null || text.trim().isEmpty) continue;
      final token = _normalizeHeaderToken(text);
      switch (token) {
        case 'exercise':
          exercise ??= i;
          break;
        case 'sets':
          sets ??= i;
          break;
        case 'reps':
          reps ??= i;
          break;
        case 'rest':
          rest ??= i;
          break;
        case 'rpe':
          rpe ??= i;
          break;
        case 'notes':
          notes ??= i;
          break;
      }
    }

    if (exercise == null &&
        sets == null &&
        reps == null &&
        rest == null &&
        rpe == null &&
        notes == null) {
      return null;
    }

    exercise ??= 0;
    sets ??= reps != null ? reps - 1 : exercise + 1;
    reps ??= sets + 1;
    rest ??= rpe != null ? rpe - 1 : reps + 1;
    rpe ??= rest + 1;
    notes ??= rpe + 1;

    final normalizedExercise = exercise < 0 ? 0 : exercise;
    final normalizedSets = sets < 0 ? normalizedExercise + 1 : sets;
    final normalizedReps = reps < 0 ? normalizedSets + 1 : reps;
    final normalizedRest = rest < 0 ? normalizedReps + 1 : rest;
    final normalizedRpe = rpe < 0 ? normalizedRest + 1 : rpe;
    final normalizedNotes = notes < 0 ? normalizedRpe + 1 : notes;

    return _DescriptorColumns(
      exercise: normalizedExercise,
      sets: normalizedSets,
      reps: normalizedReps,
      rest: normalizedRest,
      rpe: normalizedRpe,
      notes: normalizedNotes,
    );
  }

  bool _isHeaderToken(String text) {
    return _normalizeHeaderToken(text) != null;
  }

  String? _normalizeHeaderToken(String text) {
    final lower = text.trim().toLowerCase();
    if (lower.isEmpty) return null;
    final compact = lower.replaceAll(RegExp(r'[^a-z0-9]'), '');
    if (compact.isEmpty) return null;
    if (compact == 'exercise' ||
        compact == 'exercises' ||
        compact == 'exercisename' ||
        compact == 'movement' ||
        compact == 'movements') {
      return 'exercise';
    }
    if (compact == 'set' || compact == 'sets') return 'sets';
    if (compact == 'rep' || compact == 'reps') return 'reps';
    if (compact == 'rest' || compact == 'resttime') return 'rest';
    if (compact == 'rpe' || compact == 'rir') return 'rpe';
    if (compact == 'note' || compact == 'notes') return 'notes';
    return null;
  }

  bool _isDayMarker(String text) {
    final lower = text.trim().toLowerCase();
    if (!lower.startsWith('day')) return false;
    return RegExp(r'^day\s*\d+').hasMatch(lower);
  }

  bool _looksLikeNote(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('top set') ||
        lower.contains('back-off') ||
        lower.contains('drop')) return true;
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
    if (lower.startsWith('progression') ||
        lower.startsWith('weekly direct volume')) return true;
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
      final dateMatch = RegExp(r'^(\d{4})-(\d{2})-(\d{2})').firstMatch(cleaned);
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
    final numbers = RegExp(r'(\d+)')
        .allMatches(cleaned)
        .map((m) => int.parse(m.group(1)!))
        .toList();
    if (numbers.isEmpty) return null;
    final isMin = cleaned.contains('min');
    final factor = isMin ? 60 : 1;
    if (numbers.length == 1) {
      return _Range(
          min: numbers[0] * factor.toDouble(),
          max: numbers[0] * factor.toDouble());
    }
    return _Range(
        min: numbers[0] * factor.toDouble(),
        max: numbers[1] * factor.toDouble());
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
    bool amrapLastSet = false,
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
      'amrap_last_set': amrapLastSet ? 1 : 0,
      'partials_target_min': null,
      'partials_target_max': null,
      'notes': null,
    };
  }

  Future<int?> _resolveExerciseId(ExerciseRepo repo, String name,
      {required bool createIfMissing}) async {
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
    final model = await settings.getCloudModelForTask(
      CloudModelTask.exerciseEnrichment,
    );
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

class _StructuredProgram {
  _StructuredProgram({
    required this.programName,
    required this.days,
    Map<String, Object?>? meta,
  }) : meta = meta ?? const {};

  final String programName;
  final List<_StructuredProgramDay> days;
  final Map<String, Object?> meta;
}

class _StructuredProgramDay {
  _StructuredProgramDay({
    required this.dayName,
    required this.exercises,
  });

  final String dayName;
  final List<_StructuredExercise> exercises;
}

class _StructuredExercise {
  _StructuredExercise({
    required this.name,
    required this.setCount,
    required this.repsRange,
    required this.restRange,
    required this.rpeRange,
    required this.dropPercentRange,
    required this.notes,
    required this.amrapLastSet,
    required this.role,
    Map<String, String?>? rawValues,
    List<String>? flags,
  })  : rawValues = rawValues ?? const {},
        flags = flags ?? const [];

  final String name;
  final int setCount;
  final _Range? repsRange;
  final _Range? restRange;
  final _Range? rpeRange;
  final _Range? dropPercentRange;
  final String? notes;
  final bool amrapLastSet;
  final String role;
  final Map<String, String?> rawValues;
  final List<String> flags;
}

class _Range {
  _Range({required this.min, required this.max});

  final double min;
  final double max;

  int? get minInt => min.isNaN ? null : min.round();
  int? get maxInt => max.isNaN ? null : max.round();
}

enum _ValidationSeverity { warning, error }

class _ValidationIssue {
  const _ValidationIssue({
    required this.severity,
    required this.code,
    required this.path,
    required this.message,
  });

  final _ValidationSeverity severity;
  final String code;
  final String path;
  final String message;
}

class _CanonicalParseResult {
  const _CanonicalParseResult({
    required this.program,
    required this.issues,
    this.debugLines = const [],
  });

  final _StructuredProgram program;
  final List<_ValidationIssue> issues;
  final List<String> debugLines;
}

class _CanonicalMarkerScan {
  const _CanonicalMarkerScan({
    required this.startRows,
    required this.endRows,
    this.repeatRow,
    this.startRowNumbers = const [],
    this.endRowNumbers = const [],
  });

  final int startRows;
  final int endRows;
  final int? repeatRow;
  final List<int> startRowNumbers;
  final List<int> endRowNumbers;
}

enum _BoundaryTag { start, end }

class _CanonicalBoundaryRow {
  const _CanonicalBoundaryRow({
    required this.dayNumber,
    required this.label,
    required this.tag,
    required this.rowIndex,
  });

  final int dayNumber;
  final String label;
  final _BoundaryTag tag;
  final int rowIndex;
}

class _CanonicalHeaderColumns {
  const _CanonicalHeaderColumns({
    required this.exercise,
    required this.sets,
    required this.reps,
    required this.rest,
    required this.rpe,
    required this.notes,
  });

  final int exercise;
  final int sets;
  final int reps;
  final int? rest;
  final int rpe;
  final int notes;
}

class _DescriptorColumns {
  const _DescriptorColumns({
    this.exercise = 0,
    this.sets = 1,
    this.reps = 2,
    this.rest = 3,
    this.rpe = 4,
    this.notes = 5,
  });

  final int exercise;
  final int sets;
  final int reps;
  final int rest;
  final int rpe;
  final int notes;
}
