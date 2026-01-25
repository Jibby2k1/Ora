import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'voice_models.dart';
import '../cloud/gemini_queue.dart';

class GeminiParser {
  GeminiParser();

  String? lastError;
  String? lastRawOutput;
  String? lastPrompt;

  Future<NluCommand?> parse({
    required String transcript,
    required String apiKey,
    required String model,
    List<String>? currentDayExercises,
    List<String>? otherDayExercises,
    List<String>? catalogExercises,
  }) async {
    lastError = null;
    lastRawOutput = null;
    final prompt = _buildPrompt(
      transcript,
      currentDayExercises: currentDayExercises,
      otherDayExercises: otherDayExercises,
      catalogExercises: catalogExercises,
    );
    lastPrompt = prompt;

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

    http.Response response;
    try {
      response = await GeminiQueue.instance.run(
        () => http
            .post(
              uri,
              headers: {'Content-Type': 'application/json'},
              body: jsonEncode(payload),
            )
            .timeout(const Duration(seconds: 10)),
        label: 'voice-parse',
      );
    } catch (e) {
      lastError = 'Gemini request failed: $e';
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      final body = _trimGeminiBody(response.body);
      lastError = 'Gemini HTTP ${response.statusCode}: $body';
      debugPrint('[Gemini][voice] ${response.statusCode} $body');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) {
        lastError = 'Gemini returned no candidates.';
        return null;
      }
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) {
        lastError = 'Gemini returned empty content.';
        return null;
      }
      final text = parts.first['text']?.toString() ?? '';
      lastRawOutput = text;
      final jsonText = _extractJson(text);
      if (jsonText == null) {
        lastError = 'Gemini output did not contain JSON.';
        return null;
      }
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _commandFromJson(map);
    } catch (e) {
      lastError = 'Gemini parse error: $e';
      return null;
    }
  }

  String _buildPrompt(
    String input, {
    List<String>? currentDayExercises,
    List<String>? otherDayExercises,
    List<String>? catalogExercises,
  }) {
    final currentList = _formatList(currentDayExercises);
    final otherList = _formatList(otherDayExercises);
    final catalogList = _formatList(catalogExercises);
    return '''
You are a strict JSON command parser for a workout app.
Return ONLY a single JSON object. No markdown. No extra text.
Schema:
{
  "intent": "log_set|switch|show_stats|undo|redo",
  "exercise_ref": string|null,
  "weight": number|null,
  "weight_unit": "lb"|"kg"|null,
  "reps": number|null,
  "partials": number|null,
  "rpe": number|null,
  "rir": number|null
}
Rules:
- If intent is "log_set", ALWAYS include exercise_ref, reps, weight, and weight_unit when they are present.
- If the user says "same as last set" or "repeat last", set reps and weight to null and set exercise_ref if mentioned.
- If no exercise is mentioned, set exercise_ref to null.
- Use lb or kg only; otherwise null.
- Output integers for reps/partials.
- Exercise selection priority:
  1) Current day exercises (highest)
  2) Other days in the same program
  3) Full catalog (lowest)
- If the exercise is not in any list, set exercise_ref to null.

Current day exercises:
$currentList

Other day exercises:
$otherList

Catalog exercises:
$catalogList

Input: "$input"
JSON:
''';
  }

  String _trimGeminiBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 400) return trimmed;
    return '${trimmed.substring(0, 400)}...';
  }

  String _formatList(List<String>? values) {
    if (values == null || values.isEmpty) return '-';
    return values.map((e) => '- $e').join('\n');
  }

  NluCommand? _commandFromJson(Map<String, dynamic> json) {
    final intent = json['intent']?.toString();
    if (intent == null || intent.isEmpty) return null;
    switch (intent) {
      case 'undo':
      case 'redo':
        return NluCommand(type: intent);
      case 'switch':
      case 'show_stats':
        return NluCommand(
          type: intent == 'switch' ? 'switch' : 'show_stats',
          exerciseRef: json['exercise_ref']?.toString(),
        );
      case 'log_set':
        return NluCommand(
          type: 'log_set',
          exerciseRef: json['exercise_ref']?.toString(),
          weight: _asDouble(json['weight']),
          weightUnit: _normalizeUnit(json['weight_unit']),
          reps: _asInt(json['reps']),
          partials: _asInt(json['partials']),
          rpe: _asDouble(json['rpe']),
          rir: _asDouble(json['rir']),
        );
      default:
        return null;
    }
  }

  int? _asInt(dynamic value) {
    if (value == null) return null;
    if (value is int) return value;
    if (value is double) return value.round();
    return int.tryParse(value.toString());
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String? _normalizeUnit(dynamic raw) {
    final text = raw?.toString().toLowerCase();
    if (text == null || text.isEmpty) return null;
    if (text.startsWith('lb') || text.startsWith('pound')) return 'lb';
    if (text.startsWith('kg') || text.startsWith('kilo')) return 'kg';
    return null;
  }

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }
}
