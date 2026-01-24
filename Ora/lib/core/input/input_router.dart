import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:excel/excel.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

import '../../app.dart';
import '../../data/db/db.dart';
import '../../data/repositories/settings_repo.dart';
import '../../domain/services/import_service.dart';
import '../../ui/screens/shell/app_shell_controller.dart';

enum InputSource { mic, text, camera, upload }

enum InputIntent {
  trainingLog,
  dietLog,
  appearanceLog,
  programImport,
  leaderboard,
  settings,
  unknown,
}

class InputEvent {
  InputEvent({
    required this.source,
    this.text,
    this.file,
    this.fileName,
    this.mimeType,
  });

  final InputSource source;
  final String? text;
  final File? file;
  final String? fileName;
  final String? mimeType;
}

class InputRouteResult {
  InputRouteResult({
    required this.intent,
    required this.confidence,
    required this.reason,
    this.entity,
  });

  final InputIntent intent;
  final double confidence;
  final String reason;
  final String? entity;
}

class InputDispatch {
  InputDispatch({
    required this.intent,
    required this.event,
    required this.confidence,
    required this.reason,
    this.entity,
  });

  final InputIntent intent;
  final InputEvent event;
  final double confidence;
  final String reason;
  final String? entity;
}

class InputRouter {
  InputRouter(this._db);

  final AppDatabase _db;
  List<int>? _pendingImageBytes;
  String? _pendingImageMime;

  Future<InputRouteResult?> classify(InputEvent event) async {
    final settings = SettingsRepo(_db);
    final provider = await settings.getCloudProvider();
    final model = await settings.getCloudModel();
    final apiKey = await settings.getCloudApiKey();
    if (apiKey == null || apiKey.trim().isEmpty) {
      _showSnack('Cloud API key required.');
      return null;
    }

    final prompt = _buildPrompt(event);
    InputRouteResult? result;
    if (provider == 'openai') {
      if (event.file != null && _isImage(event.file!)) {
        result = await _classifyOpenAiWithImage(prompt, apiKey, model);
      } else {
        result = await _classifyOpenAi(prompt, apiKey, model);
      }
    } else {
      result = await _classifyGemini(prompt, apiKey, model);
    }

    if (result == null && event.file != null && _isSpreadsheet(event.file!)) {
      return InputRouteResult(
        intent: InputIntent.programImport,
        confidence: 0.35,
        reason: 'Spreadsheet file fallback',
        entity: event.fileName,
      );
    }
    return result;
  }

  Future<void> routeAndHandle(BuildContext context, InputEvent event) async {
    final result = await classify(event);
    if (result == null) return;

    _selectTab(result.intent);
    _showSnack('Routed to ${_labelFor(result.intent)}');
    if (result.intent == InputIntent.programImport && event.file != null) {
      await _handleProgramImport(context, event.file!);
      return;
    }
    AppShellController.instance.setPendingInput(
      InputDispatch(
        intent: result.intent,
        event: event,
        confidence: result.confidence,
        reason: result.reason,
        entity: result.entity,
      ),
    );
  }

  Future<void> _handleProgramImport(BuildContext context, File file) async {
    final service = ImportService(_db);
    try {
      final result = await service.importFromXlsxPath(file.path);
      final missingCount = result.missingExercises.length;
      final snack = missingCount == 0
          ? 'Imported ${result.dayCount} days, ${result.exerciseCount} exercises.'
          : 'Imported ${result.dayCount} days, ${result.exerciseCount} exercises. Missing $missingCount exercises.';
      _showSnack(snack);
      if (missingCount > 0) {
        if (!context.mounted) return;
        await showDialog<void>(
          context: context,
          builder: (context) {
            return AlertDialog(
              title: const Text('Missing exercises'),
              content: SizedBox(
                width: double.maxFinite,
                child: ListView(
                  shrinkWrap: true,
                  children: result.missingExercises.map((e) => Text('• $e')).toList(),
                ),
              ),
              actions: [
                TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK')),
              ],
            );
          },
        );
      }
    } catch (e) {
      _showSnack('Import failed: $e');
    }
  }

  Future<InputRouteResult?> _classifyOpenAi(String prompt, String apiKey, String model) async {
    final uri = Uri.https('api.openai.com', '/v1/chat/completions');
    final payload = {
      'model': model,
      'temperature': 0.1,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': 'Classify this input.'},
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
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _showSnack('OpenAI error: ${response.statusCode}');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = data['choices'] as List<dynamic>? ?? [];
      if (choices.isEmpty) return null;
      final message = choices.first['message'] as Map<String, dynamic>?;
      final content = message?['content']?.toString() ?? '';
      final jsonText = _extractJson(content);
      if (jsonText == null) return null;
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return _resultFromJson(parsed);
    } catch (_) {
      return null;
    }
  }

  Future<InputRouteResult?> _classifyOpenAiWithImage(
    String prompt,
    String apiKey,
    String model,
  ) async {
    final bytes = _pendingImageBytes;
    final mime = _pendingImageMime;
    if (bytes == null || mime == null) return null;
    final uri = Uri.https('api.openai.com', '/v1/responses');
    final dataUrl = 'data:$mime;base64,${base64Encode(bytes)}';
    final payload = {
      'model': model,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': dataUrl},
          ],
        },
      ],
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
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _showSnack('OpenAI error: ${response.statusCode}');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final text = _extractResponseText(data);
      if (text == null) return null;
      final jsonText = _extractJson(text);
      if (jsonText == null) return null;
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return _resultFromJson(parsed);
    } catch (_) {
      return null;
    } finally {
      _pendingImageBytes = null;
      _pendingImageMime = null;
    }
  }

  String? _extractResponseText(Map<String, dynamic> data) {
    final output = data['output'] as List<dynamic>? ?? [];
    for (final item in output) {
      final content = (item as Map<String, dynamic>)['content'] as List<dynamic>? ?? [];
      for (final part in content) {
        final map = part as Map<String, dynamic>;
        final type = map['type']?.toString();
        if (type == 'output_text' || type == 'text') {
          return map['text']?.toString();
        }
      }
    }
    return null;
  }

  Future<InputRouteResult?> _classifyGemini(String prompt, String apiKey, String model) async {
    if (_pendingImageBytes != null && _pendingImageMime != null) {
      return _classifyGeminiWithImage(prompt, apiKey, model);
    }
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
            {'text': prompt}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 256,
      },
    };

    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _showSnack('Gemini error: ${response.statusCode}');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) return null;
      final text = parts.first['text']?.toString() ?? '';
      final jsonText = _extractJson(text);
      if (jsonText == null) return null;
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return _resultFromJson(parsed);
    } catch (_) {
      return null;
    }
  }

  Future<InputRouteResult?> _classifyGeminiWithImage(
    String prompt,
    String apiKey,
    String model,
  ) async {
    final bytes = _pendingImageBytes;
    final mime = _pendingImageMime;
    if (bytes == null || mime == null) return null;
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
            {
              'inlineData': {
                'mimeType': mime,
                'data': base64Encode(bytes),
              }
            },
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 256,
      },
    };
    final response = await http
        .post(
          uri,
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode(payload),
        )
        .timeout(const Duration(seconds: 12));

    if (response.statusCode < 200 || response.statusCode >= 300) {
      _showSnack('Gemini error: ${response.statusCode}');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) return null;
      final text = parts.first['text']?.toString() ?? '';
      final jsonText = _extractJson(text);
      if (jsonText == null) return null;
      final parsed = jsonDecode(jsonText) as Map<String, dynamic>;
      return _resultFromJson(parsed);
    } catch (_) {
      return null;
    } finally {
      _pendingImageBytes = null;
      _pendingImageMime = null;
    }
  }

  String _buildPrompt(InputEvent event) {
    _pendingImageBytes = null;
    _pendingImageMime = null;
    final buffer = StringBuffer();
    buffer.writeln('You are a classifier for a fitness app.');
    buffer.writeln('Return ONLY a JSON object.');
    buffer.writeln('Schema: {"intent": "training_log|diet_log|appearance_log|program_import|leaderboard|settings|unknown", "confidence": number, "reason": string, "entity": string|null}');
    buffer.writeln('Input source: ${event.source.name}');
    if (event.text != null && event.text!.trim().isNotEmpty) {
      buffer.writeln('User text: "${event.text!.trim()}"');
    }
    if (event.file != null) {
      buffer.writeln('File name: ${event.fileName ?? event.file!.uri.pathSegments.last}');
      buffer.writeln('MIME: ${event.mimeType ?? 'unknown'}');
      final preview = _filePreview(event.file!);
      if (preview != null && preview.trim().isNotEmpty) {
        buffer.writeln('File preview:');
        buffer.writeln(preview);
      } else if (_isImage(event.file!)) {
        _pendingImageBytes = event.file!.readAsBytesSync();
        _pendingImageMime = event.mimeType ?? _guessMimeType(event.file!.path);
        buffer.writeln('Image attached. Use visual content to classify.');
      }
    }
    buffer.writeln('Hints:');
    buffer.writeln('- Workout terms -> training_log');
    buffer.writeln('- Meal/macro/nutrition terms -> diet_log');
    buffer.writeln('- Style/physique/progress/photo terms -> appearance_log');
    buffer.writeln('- Spreadsheet files (.xlsx/.csv) with program or exercise keywords -> program_import');
    buffer.writeln('- For training_log, set entity to the exercise name if present.');
    buffer.writeln('- For diet_log, set entity to the meal or food if present.');
    buffer.writeln('Return JSON only.');
    return buffer.toString();
  }

  String? _filePreview(File file) {
    try {
      final path = file.path.toLowerCase();
      if (path.endsWith('.csv') || path.endsWith('.txt')) {
        return _readTextPreview(file);
      }
      if (path.endsWith('.xlsx')) {
        return _xlsxPreview(file);
      }
      if (path.endsWith('.pdf')) {
        return _pdfPreview(file);
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  String _readTextPreview(File file) {
    final text = file.readAsStringSync();
    final lines = text.split('\n').take(12).join('\n');
    return lines.length > 1200 ? lines.substring(0, 1200) : lines;
  }

  String? _xlsxPreview(File file) {
    final bytes = file.readAsBytesSync();
    final excel = Excel.decodeBytes(bytes);
    if (excel.tables.isEmpty) return null;
    final sheetName = excel.tables.keys.first;
    final sheet = excel.tables[sheetName];
    if (sheet == null) return null;
    final buffer = StringBuffer();
    buffer.writeln('Sheet: $sheetName');
    for (var r = 0; r < sheet.rows.length && r < 10; r++) {
      final row = sheet.rows[r];
      final values = row.take(4).map((cell) => cell?.value?.toString() ?? '').join(' | ');
      if (values.trim().isNotEmpty) buffer.writeln(values);
    }
    final output = buffer.toString().trim();
    return output.isEmpty ? null : output;
  }

  String? _pdfPreview(File file) {
    try {
      final bytes = file.readAsBytesSync();
      final document = PdfDocument(inputBytes: bytes);
      final extractor = PdfTextExtractor(document);
      final text = extractor.extractText(startPageIndex: 0, endPageIndex: 0);
      document.dispose();
      if (text.trim().isEmpty) return null;
      final clipped = text.length > 1200 ? text.substring(0, 1200) : text;
      return clipped;
    } catch (_) {
      return null;
    }
  }

  bool _isImage(File file) {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.png') ||
        lower.endsWith('.jpg') ||
        lower.endsWith('.jpeg') ||
        lower.endsWith('.heic');
  }

  bool _isSpreadsheet(File file) {
    final lower = file.path.toLowerCase();
    return lower.endsWith('.xlsx') || lower.endsWith('.csv');
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.heic')) return 'image/heic';
    if (lower.endsWith('.pdf')) return 'application/pdf';
    if (lower.endsWith('.csv')) return 'text/csv';
    if (lower.endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  InputRouteResult? _resultFromJson(Map<String, dynamic> json) {
    final rawIntent = json['intent']?.toString() ?? 'unknown';
    final confidence = (json['confidence'] as num?)?.toDouble() ?? 0.0;
    final reason = json['reason']?.toString() ?? '';
    final entity = json['entity']?.toString();
    return InputRouteResult(
      intent: _intentFromString(rawIntent),
      confidence: confidence,
      reason: reason,
      entity: entity?.trim().isEmpty == true ? null : entity,
    );
  }

  InputIntent _intentFromString(String value) {
    switch (value) {
      case 'training_log':
        return InputIntent.trainingLog;
      case 'diet_log':
        return InputIntent.dietLog;
      case 'appearance_log':
        return InputIntent.appearanceLog;
      case 'program_import':
        return InputIntent.programImport;
      case 'leaderboard':
        return InputIntent.leaderboard;
      case 'settings':
        return InputIntent.settings;
      default:
        return InputIntent.unknown;
    }
  }

  void _selectTab(InputIntent intent) {
    final appearanceEnabled = AppShellController.instance.appearanceEnabled.value;
    final index = switch (intent) {
      InputIntent.trainingLog => 0,
      InputIntent.dietLog => 1,
      InputIntent.appearanceLog => appearanceEnabled ? 2 : 0,
      InputIntent.leaderboard => appearanceEnabled ? 3 : 2,
      InputIntent.settings => appearanceEnabled ? 4 : 3,
      InputIntent.programImport => 0,
      InputIntent.unknown => 0,
    };
    AppShellController.instance.selectTab(index);
  }

  void _showSnack(String message) {
    OraApp.messengerKey.currentState?.showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  String _labelFor(InputIntent intent) {
    switch (intent) {
      case InputIntent.trainingLog:
        return 'Training';
      case InputIntent.dietLog:
        return 'Diet';
      case InputIntent.appearanceLog:
        return 'Appearance';
      case InputIntent.programImport:
        return 'Program Import';
      case InputIntent.leaderboard:
        return 'Leaderboard';
      case InputIntent.settings:
        return 'Settings';
      case InputIntent.unknown:
        return 'Training';
    }
  }

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
