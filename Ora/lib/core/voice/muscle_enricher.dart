import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../cloud/gemini_queue.dart';
class MuscleInfo {
  MuscleInfo({required this.primary, required this.secondary});

  final String primary;
  final List<String> secondary;
}

class MuscleEnricher {
  static const _muscles = [
    'Chest',
    'Back',
    'Lats',
    'Upper Back',
    'Traps',
    'Shoulders',
    'Front Delts',
    'Side Delts',
    'Rear Delts',
    'Biceps',
    'Triceps',
    'Forearms',
    'Abs',
    'Obliques',
    'Quads',
    'Hamstrings',
    'Glutes',
    'Calves',
    'Adductors',
    'Abductors',
    'Hip Flexors',
  ];

  Future<MuscleInfo?> enrich({
    required String exerciseName,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    if (provider == 'openai') {
      return _openAi(exerciseName, apiKey, model);
    }
    return _gemini(exerciseName, apiKey, model);
  }

  Future<MuscleInfo?> _gemini(String exerciseName, String apiKey, String model) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      {'key': apiKey},
    );
    final prompt = _prompt(exerciseName);
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
        'temperature': 0.0,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 128,
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
        label: 'muscle-enrich',
      );
    } catch (_) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[Gemini][muscle] ${response.statusCode} ${_trimGeminiBody(response.body)}');
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
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _parseInfo(map);
    } catch (_) {
      return null;
    }
  }

  Future<MuscleInfo?> _openAi(String exerciseName, String apiKey, String model) async {
    final useResponses = _openAiUsesResponses(model);
    final uri = Uri.https(
      'api.openai.com',
      useResponses ? '/v1/responses' : '/v1/chat/completions',
    );
    final prompt = _prompt(exerciseName);
    final payload = useResponses
        ? {
            'model': model,
            'input': [
              {
                'role': 'system',
                'content': [
                  {'type': 'input_text', 'text': prompt},
                ],
              },
              {
                'role': 'user',
                'content': [
                  {'type': 'input_text', 'text': exerciseName},
                ],
              },
            ],
          }
        : {
            'model': model,
            'temperature': 0.0,
            'messages': [
              {
                'role': 'system',
                'content': prompt,
              },
              {
                'role': 'user',
                'content': exerciseName,
              }
            ],
            'response_format': {'type': 'json_object'},
          };

    http.Response response;
    try {
      response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 12));
    } catch (_) {
      return null;
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final content =
          useResponses ? (_extractResponseText(data) ?? '') : _extractChatContent(data);
      if (content.trim().isEmpty) return null;
      final jsonText = _extractJson(content);
      if (jsonText == null) return null;
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _parseInfo(map);
    } catch (_) {
      return null;
    }
  }

  String _prompt(String exerciseName) {
    final options = _muscles.map((m) => '- $m').join('\n');
    return '''
You label exercises with muscle groups.
Return ONLY a single JSON object. No markdown. No extra text.
Schema:
{
  "primary": string,
  "secondary": [string]
}
Rules:
- Choose primary from this list:
$options
- Secondary must also come from the list.
- Keep secondary list small (0-3).
- If unsure, choose the closest primary and leave secondary empty.
- For "$exerciseName", respond with JSON only.
''';
  }

  MuscleInfo? _parseInfo(Map<String, dynamic> map) {
    final primary = map['primary']?.toString().trim();
    if (primary == null || primary.isEmpty) return null;
    final secondaryRaw = map['secondary'];
    final secondary = <String>[];
    if (secondaryRaw is List) {
      for (final item in secondaryRaw) {
        final text = item?.toString().trim();
        if (text == null || text.isEmpty) continue;
        if (text.toLowerCase() == primary.toLowerCase()) continue;
        secondary.add(text);
      }
    }
    return MuscleInfo(primary: primary, secondary: secondary);
  }

  bool _openAiUsesResponses(String model) {
    final lower = model.toLowerCase();
    return lower.startsWith('gpt-5');
  }

  String _extractChatContent(Map<String, dynamic> data) {
    final choices = data['choices'];
    if (choices is! List || choices.isEmpty) return '';
    final first = choices.first;
    if (first is! Map) return '';
    final message = first['message'];
    if (message is! Map) return '';
    final content = message['content'];
    return content?.toString() ?? '';
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

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  String _trimGeminiBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 400) return trimmed;
    return '${trimmed.substring(0, 400)}...';
  }
}
