import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

class DietEstimate {
  DietEstimate({
    required this.mealName,
    this.calories,
    this.proteinG,
    this.carbsG,
    this.fatG,
    this.fiberG,
    this.sodiumMg,
    this.micros,
    this.notes,
  });

  final String mealName;
  final double? calories;
  final double? proteinG;
  final double? carbsG;
  final double? fatG;
  final double? fiberG;
  final double? sodiumMg;
  final Map<String, double>? micros;
  final String? notes;
}

class DietAnalysisService {
  Future<DietEstimate?> analyzeImage({
    required File file,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    if (provider != 'gemini') {
      return null;
    }
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _analysisPrompt();
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
                'mimeType': _guessMimeType(file.path),
                'data': base64Image,
              }
            },
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.1,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 512,
      },
    };
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return _parseGemini(response.body);
  }

  Future<DietEstimate?> refineEstimate({
    required DietEstimate current,
    required String userText,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    if (provider == 'openai') {
      return _openAiRefine(current, userText, apiKey, model);
    }
    return _geminiRefine(current, userText, apiKey, model);
  }

  Future<DietEstimate?> _geminiRefine(
    DietEstimate current,
    String userText,
    String apiKey,
    String model,
  ) async {
    final uri = Uri.https(
      'generativelanguage.googleapis.com',
      '/v1beta/models/$model:generateContent',
      {'key': apiKey},
    );
    final prompt = _refinePrompt(current);
    final payload = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt},
            {'text': userText}
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 256,
      },
    };
    final response = await http.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    return _parseGemini(response.body);
  }

  Future<DietEstimate?> _openAiRefine(
    DietEstimate current,
    String userText,
    String apiKey,
    String model,
  ) async {
    final uri = Uri.https('api.openai.com', '/v1/chat/completions');
    final prompt = _refinePrompt(current);
    final payload = {
      'model': model,
      'temperature': 0.0,
      'messages': [
        {'role': 'system', 'content': prompt},
        {'role': 'user', 'content': userText},
      ],
      'response_format': {'type': 'json_object'},
    };
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
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
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _fromMap(map);
    } catch (_) {
      return null;
    }
  }

  DietEstimate? _parseGemini(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) return null;
      final text = parts.first['text']?.toString() ?? '';
      final jsonText = _extractJson(text);
      if (jsonText == null) return null;
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _fromMap(map);
    } catch (_) {
      return null;
    }
  }

  DietEstimate? _fromMap(Map<String, dynamic> map) {
    final name = map['meal_name']?.toString().trim();
    if (name == null || name.isEmpty) return null;
    return DietEstimate(
      mealName: name,
      calories: _asDouble(map['calories']),
      proteinG: _asDouble(map['protein_g']),
      carbsG: _asDouble(map['carbs_g']),
      fatG: _asDouble(map['fat_g']),
      fiberG: _asDouble(map['fiber_g']),
      sodiumMg: _asDouble(map['sodium_mg']),
      micros: _asMicros(map['micros']),
      notes: map['notes']?.toString().trim().isEmpty == true ? null : map['notes']?.toString(),
    );
  }

  double? _asDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  Map<String, double>? _asMicros(dynamic value) {
    if (value is Map<String, dynamic>) {
      final result = <String, double>{};
      value.forEach((key, v) {
        final parsed = _asDouble(v);
        if (parsed != null) {
          result[key.toString()] = parsed;
        }
      });
      return result.isEmpty ? null : result;
    }
    return null;
  }

  String _analysisPrompt() {
    return '''
You are estimating nutrition from a food photo.
Return ONLY a single JSON object (no markdown, no extra text).
Schema:
{
  "meal_name": string,
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "fiber_g": number,
  "sodium_mg": number,
  "micros": { "name": number },
  "notes": string
}
Rules:
- Provide a short, descriptive meal_name.
- micros should include a few key micronutrients if you can infer (e.g., potassium_mg, iron_mg, vitamin_c_mg).
- Use numbers only; omit fields if unknown.
''';
  }

  String _refinePrompt(DietEstimate current) {
    final currentJson = jsonEncode({
      'meal_name': current.mealName,
      'calories': current.calories,
      'protein_g': current.proteinG,
      'carbs_g': current.carbsG,
      'fat_g': current.fatG,
      'fiber_g': current.fiberG,
      'sodium_mg': current.sodiumMg,
      'micros': current.micros ?? {},
    });
    return '''
You refine nutrition estimates based on user corrections.
Return ONLY a single JSON object (no markdown).
Schema:
{
  "meal_name": string,
  "calories": number,
  "protein_g": number,
  "carbs_g": number,
  "fat_g": number,
  "fiber_g": number,
  "sodium_mg": number,
  "micros": { "name": number },
  "notes": string
}
Current estimate:
$currentJson
Apply user corrections and return the updated estimate.
''';
  }

  String? _extractJson(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  String _guessMimeType(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }
}
