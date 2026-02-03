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
  static final Map<String, String> _muscleLookup = {
    for (final muscle in _muscles) muscle.toLowerCase(): muscle,
  };

  Future<MuscleInfo?> enrich({
    required String exerciseName,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    final normalizedProvider = provider.trim().toLowerCase();
    if (normalizedProvider == 'openai') {
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
      debugPrint('[Gemini][muscle] ${response.statusCode} ${_trimBody(response.body)}');
      return null;
    }

    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) return null;
      final text = _joinGeminiParts(parts);
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
      debugPrint('[OpenAI][muscle] ${response.statusCode} ${_trimBody(response.body)}');
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
    final primaryRaw = map['primary']?.toString().trim();
    if (primaryRaw == null || primaryRaw.isEmpty) return null;
    final primary = _normalizeMuscle(primaryRaw) ?? primaryRaw;
    final secondaryRaw = map['secondary'];
    final secondary = <String>[];
    final seen = <String>{primary.toLowerCase()};
    void addSecondary(String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) return;
      final normalized = _normalizeMuscle(trimmed) ?? trimmed;
      final key = normalized.toLowerCase();
      if (!seen.add(key)) return;
      secondary.add(normalized);
    }
    if (secondaryRaw is List) {
      for (final item in secondaryRaw) {
        if (item == null) continue;
        addSecondary(item.toString());
      }
    } else if (secondaryRaw is String) {
      for (final part in secondaryRaw.split(RegExp(r'[,;/]'))) {
        addSecondary(part);
      }
    } else if (secondaryRaw != null) {
      addSecondary(secondaryRaw.toString());
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
    final output = data['output'];
    if (output is! List) return null;
    for (final item in output) {
      if (item is! Map) continue;
      final content = item['content'];
      if (content is! List) continue;
      for (final part in content) {
        if (part is! Map) continue;
        final type = part['type']?.toString();
        if (type == 'output_text' || type == 'text') {
          final text = part['text']?.toString();
          if (text != null && text.isNotEmpty) return text;
        }
      }
    }
    return null;
  }

  String? _extractJson(String text) {
    var depth = 0;
    var start = -1;
    var inString = false;
    var escaped = false;
    for (var i = 0; i < text.length; i++) {
      final char = text[i];
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (char == r'\') {
          escaped = true;
          continue;
        }
        if (char == '"') inString = false;
        continue;
      }
      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{') {
        if (depth == 0) start = i;
        depth++;
        continue;
      }
      if (char == '}' && depth > 0) {
        depth--;
        if (depth == 0 && start != -1) {
          return text.substring(start, i + 1);
        }
      }
    }
    return null;
  }

  String _trimBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 400) return trimmed;
    return '${trimmed.substring(0, 400)}...';
  }

  String? _normalizeMuscle(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return _muscleLookup[trimmed.toLowerCase()];
  }

  String _joinGeminiParts(List<dynamic> parts) {
    final buffer = StringBuffer();
    var wrote = false;
    for (final part in parts) {
      if (part is! Map) continue;
      final text = part['text']?.toString();
      if (text == null || text.isEmpty) continue;
      if (wrote) buffer.writeln();
      buffer.write(text);
      wrote = true;
    }
    return buffer.toString();
  }
}
