import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'gemini_queue.dart';

class AppearanceAnalysisService {
  Future<AppearanceAnalysisResult?> analyzeImage({
    required File file,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    if (provider == 'openai') {
      return _openAiAnalyzeImage(file: file, apiKey: apiKey, model: model);
    }
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
                'mimeType': _guessMimeTypeForImage(file.path),
                'data': base64Image,
              }
            },
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.2,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 256,
      },
    };
    final response = await GeminiQueue.instance.run(
      () => http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
      label: 'appearance-analysis',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[Gemini][appearance-analysis] ${response.statusCode} ${_trimBody(response.body)}');
      return null;
    }
    final text = _extractGeminiText(response.body);
    if (text == null) return null;
    return _parseAnalysis(text);
  }

  Future<String?> classifyImage({
    required File file,
    required String provider,
    required String apiKey,
    required String model,
    String? summary,
  }) async {
    if (provider == 'openai') {
      return _openAiClassifyImage(file: file, apiKey: apiKey, model: model, summary: summary);
    }
    if (provider != 'gemini') {
      return null;
    }
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _categoryPrompt(summary);
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
                'mimeType': _guessMimeTypeForImage(file.path),
                'data': base64Image,
              }
            },
          ],
        }
      ],
      'generationConfig': {
        'temperature': 0.0,
        'topP': 0.9,
        'topK': 40,
        'maxOutputTokens': 64,
      },
    };
    final response = await GeminiQueue.instance.run(
      () => http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
      label: 'appearance-category',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint('[Gemini][appearance-category] ${response.statusCode} ${_trimBody(response.body)}');
      return null;
    }
    final text = _extractGeminiText(response.body);
    if (text == null) return null;
    return _parseCategory(text);
  }

  Future<AppearanceAnalysisResult?> _openAiAnalyzeImage({
    required File file,
    required String apiKey,
    required String model,
  }) async {
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _analysisPrompt();
    final uri = Uri.https('api.openai.com', '/v1/responses');
    final dataUrl = 'data:${_guessMimeTypeForImage(file.path)};base64,$base64Image';
    final payload = {
      'model': model,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': dataUrl},
          ],
        }
      ],
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
      debugPrint('[OpenAI][appearance-analysis] ${response.statusCode} ${_trimBody(response.body)}');
      return null;
    }
    final text = _extractResponseText(response.body);
    if (text == null) return null;
    return _parseAnalysis(text);
  }

  Future<String?> _openAiClassifyImage({
    required File file,
    required String apiKey,
    required String model,
    String? summary,
  }) async {
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _categoryPrompt(summary);
    final uri = Uri.https('api.openai.com', '/v1/responses');
    final dataUrl = 'data:${_guessMimeTypeForImage(file.path)};base64,$base64Image';
    final payload = {
      'model': model,
      'input': [
        {
          'role': 'user',
          'content': [
            {'type': 'input_text', 'text': prompt},
            {'type': 'input_image', 'image_url': dataUrl},
          ],
        }
      ],
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
      debugPrint('[OpenAI][appearance-category] ${response.statusCode} ${_trimBody(response.body)}');
      return null;
    }
    final text = _extractResponseText(response.body);
    if (text == null) return null;
    return _parseCategory(text);
  }

  String _categoryPrompt(String? summary) {
    final summaryText = summary == null || summary.trim().isEmpty ? '' : '\nSummary: ${summary.trim()}';
    return '''
Classify the appearance photo into exactly ONE category: skin, physique, or style.
Return ONLY a single JSON object like {"category":"skin"} with no extra text.
Choose the most visually dominant category if ambiguous.$summaryText
''';
  }

  String _analysisPrompt() {
    return '''
Analyze the appearance photo and return ONLY a single JSON object (no markdown, no extra text).
Schema:
{
  "category": "skin" | "physique" | "style",
  "feedback": string
}
Rules:
- Choose exactly one category based on the most visually dominant aspect.
- feedback should be a short, direct sentence.
''';
  }

  AppearanceAnalysisResult? _parseAnalysis(String text) {
    final jsonText = _extractJsonFromText(text);
    if (jsonText == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      final rawCategory = decoded['category']?.toString().toLowerCase();
      final category = _normalizeCategory(rawCategory) ?? _normalizeCategory(text.toLowerCase());
      final feedback = decoded['feedback']?.toString().trim();
      if (category == null || feedback == null || feedback.isEmpty) return null;
      return AppearanceAnalysisResult(category: category, feedback: feedback);
    } catch (_) {
      return null;
    }
  }

  String? _parseCategory(String text) {
    final lower = text.toLowerCase();
    try {
      final jsonText = _extractJsonFromText(text);
      if (jsonText != null) {
        final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
        final raw = decoded['category']?.toString().toLowerCase();
        final parsed = _normalizeCategory(raw);
        if (parsed != null) return parsed;
      }
    } catch (_) {}
    return _normalizeCategory(lower);
  }

  String? _normalizeCategory(String? raw) {
    if (raw == null) return null;
    if (raw.contains('skin')) return 'skin';
    if (raw.contains('physique')) return 'physique';
    if (raw.contains('style')) return 'style';
    return null;
  }

  String? _extractGeminiText(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final candidates = data['candidates'] as List<dynamic>? ?? [];
      if (candidates.isEmpty) return null;
      final content = candidates.first['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? [];
      if (parts.isEmpty) return null;
      return parts.first['text']?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _extractResponseText(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
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
    } catch (_) {}
    return null;
  }

  String? _extractJsonFromText(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  String _guessMimeTypeForImage(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return 'image/jpeg';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'application/octet-stream';
  }

  String _trimBody(String body) {
    final trimmed = body.trim();
    if (trimmed.length <= 400) return trimmed;
    return '${trimmed.substring(0, 400)}...';
  }
}

class AppearanceAnalysisResult {
  const AppearanceAnalysisResult({
    required this.category,
    required this.feedback,
  });

  final String category;
  final String feedback;
}
