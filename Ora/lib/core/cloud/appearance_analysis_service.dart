import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../domain/models/appearance_care.dart';
import 'gemini_queue.dart';

class AppearanceAnalysisService {
  Future<AppearanceAssessmentResult?> analyzeStructuredAssessment({
    required File file,
    required AppearanceQuestionnaire questionnaire,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    if (provider == 'openai') {
      return _openAiAnalyzeStructured(
        file: file,
        questionnaire: questionnaire,
        apiKey: apiKey,
        model: model,
      );
    }
    if (provider != 'gemini') {
      return null;
    }
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _structuredAssessmentPrompt(questionnaire);
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
        'maxOutputTokens': 1200,
      },
    };
    final response = await GeminiQueue.instance.run(
      () => http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ),
      label: 'appearance-structured-analysis',
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[Gemini][appearance-structured-analysis] '
        '${response.statusCode} ${_trimBody(response.body)}',
      );
      return null;
    }
    final text = _extractGeminiText(response.body);
    if (text == null) return null;
    return _parseStructuredAssessment(text);
  }

  Future<AppearanceAnalysisResult?> analyzeImage({
    required File file,
    required String provider,
    required String apiKey,
    required String model,
  }) async {
    final result = await analyzeStructuredAssessment(
      file: file,
      questionnaire: const AppearanceQuestionnaire(),
      provider: provider,
      apiKey: apiKey,
      model: model,
    );
    if (result == null) {
      return null;
    }
    final primaryDomain = result.orderedConcerns.isNotEmpty
        ? result.orderedConcerns.first.domain
        : 'skin';
    final feedback = result.directVerdict.trim().isNotEmpty
        ? result.directVerdict
        : result.overallSummary;
    return AppearanceAnalysisResult(
      category: _legacyCategoryFromDomain(primaryDomain),
      feedback: feedback,
    );
  }

  Future<String?> classifyImage({
    required File file,
    required String provider,
    required String apiKey,
    required String model,
    String? summary,
  }) async {
    if (provider == 'openai') {
      return _openAiClassifyImage(
        file: file,
        apiKey: apiKey,
        model: model,
        summary: summary,
      );
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
      debugPrint(
        '[Gemini][appearance-category] '
        '${response.statusCode} ${_trimBody(response.body)}',
      );
      return null;
    }
    final text = _extractGeminiText(response.body);
    if (text == null) return null;
    return _parseCategory(text);
  }

  Future<AppearanceAssessmentResult?> _openAiAnalyzeStructured({
    required File file,
    required AppearanceQuestionnaire questionnaire,
    required String apiKey,
    required String model,
  }) async {
    final bytes = await file.readAsBytes();
    final base64Image = base64Encode(bytes);
    final prompt = _structuredAssessmentPrompt(questionnaire);
    final dataUrl =
        'data:${_guessMimeTypeForImage(file.path)};base64,$base64Image';
    if (_openAiUsesResponses(model)) {
      final uri = Uri.https('api.openai.com', '/v1/responses');
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
        debugPrint(
          '[OpenAI][appearance-structured-analysis] '
          '${response.statusCode} ${_trimBody(response.body)}',
        );
        return null;
      }
      final text = _extractResponseText(response.body);
      if (text == null) return null;
      return _parseStructuredAssessment(text);
    }

    final uri = Uri.https('api.openai.com', '/v1/chat/completions');
    final payload = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        }
      ],
      'temperature': _openAiSupportsTemperature(model) ? 0.2 : null,
    }..removeWhere((key, value) => value == null);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[OpenAI][appearance-structured-analysis] '
        '${response.statusCode} ${_trimBody(response.body)}',
      );
      return null;
    }
    final text = _extractChatContent(response.body);
    if (text == null) return null;
    return _parseStructuredAssessment(text);
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
    final dataUrl =
        'data:${_guessMimeTypeForImage(file.path)};base64,$base64Image';
    if (_openAiUsesResponses(model)) {
      final uri = Uri.https('api.openai.com', '/v1/responses');
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
        debugPrint(
          '[OpenAI][appearance-category] '
          '${response.statusCode} ${_trimBody(response.body)}',
        );
        return null;
      }
      final text = _extractResponseText(response.body);
      if (text == null) return null;
      return _parseCategory(text);
    }

    final uri = Uri.https('api.openai.com', '/v1/chat/completions');
    final payload = {
      'model': model,
      'messages': [
        {
          'role': 'user',
          'content': [
            {'type': 'text', 'text': prompt},
            {
              'type': 'image_url',
              'image_url': {'url': dataUrl},
            },
          ],
        }
      ],
      'temperature': _openAiSupportsTemperature(model) ? 0.0 : null,
    }..removeWhere((key, value) => value == null);
    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(payload),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      debugPrint(
        '[OpenAI][appearance-category] '
        '${response.statusCode} ${_trimBody(response.body)}',
      );
      return null;
    }
    final text = _extractChatContent(response.body);
    if (text == null) return null;
    return _parseCategory(text);
  }

  String _structuredAssessmentPrompt(AppearanceQuestionnaire questionnaire) {
    final questionnaireJson = jsonEncode(questionnaire.toJson());
    return '''
You are a direct but constructive appearance optimization reviewer.
You are reviewing ONE appearance photo plus a structured questionnaire.
Use ONLY the supported concern taxonomy below. Do not invent extra concern keys.

Supported domains: ${AppearanceProtocolLibrary.supportedDomains.join(', ')}
Supported concerns:
${AppearanceProtocolLibrary.taxonomyPrompt()}

Questionnaire JSON:
$questionnaireJson

Return ONLY one JSON object with this schema:
{
  "direct_verdict": "short direct verdict",
  "overall_summary": "2-4 sentence summary",
  "candidate_concerns": [
    {
      "key": "supported concern key only",
      "confidence": 0.0,
      "severity": "low|moderate|high",
      "evidence_summary": "why this concern was chosen from the visible appearance and questionnaire",
      "direct_feedback": "short direct but constructive critique",
      "red_flag": false
    }
  ]
}

Rules:
- Be direct, sharp, and optimization-focused, but never insulting or degrading.
- Never claim a medical diagnosis with certainty from appearance alone.
- Use red_flag=true when the concern should be routed to clinician review rather than handled as a normal self-managed cycle.
- Do not give drug dosing, self-prescription, or procedure instructions.
- If a domain is not visible or not supported by the questionnaire, omit it instead of guessing.
- Choose at most 4 concerns total.
''';
  }

  String _categoryPrompt(String? summary) {
    final summaryText = summary == null || summary.trim().isEmpty
        ? ''
        : '\nSummary: ${summary.trim()}';
    return '''
Classify the appearance photo into exactly ONE category: skin, physique, or style.
Return ONLY a single JSON object like {"category":"skin"} with no extra text.
Choose the most visually dominant category if ambiguous.$summaryText
''';
  }

  AppearanceAssessmentResult? _parseStructuredAssessment(String text) {
    final jsonText = _extractJsonFromText(text);
    if (jsonText == null) {
      return null;
    }
    try {
      final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
      final overallSummary = _readText(
        decoded,
        ['overall_summary', 'summary'],
      );
      final directVerdict = _readText(
        decoded,
        ['direct_verdict', 'verdict'],
      );
      if (overallSummary == null || directVerdict == null) {
        return null;
      }
      final rawConcerns = decoded['candidate_concerns'];
      if (rawConcerns is! List) {
        return null;
      }
      final concerns = <AppearanceCandidateConcern>[];
      final seen = <String>{};
      for (final item in rawConcerns) {
        if (item is! Map) continue;
        final map = <String, dynamic>{};
        item.forEach((key, value) {
          map[key.toString()] = value;
        });
        final key = _readText(map, ['key', 'concern_key', 'id']);
        if (key == null) continue;
        final template = AppearanceProtocolLibrary.templateForKey(key);
        if (template == null) continue;
        if (!seen.add(template.key)) continue;
        final evidenceSummary = _readText(
              map,
              ['evidence_summary', 'evidence', 'summary'],
            ) ??
            'Visible pattern and questionnaire context suggest this concern is worth tracking.';
        final directFeedback = _readText(
              map,
              ['direct_feedback', 'feedback', 'critique'],
            ) ??
            evidenceSummary;
        concerns.add(
          template.buildConcern(
            confidence: _readDouble(map['confidence']) ?? 0.55,
            severity: _normalizeSeverity(
              _readText(map, ['severity']) ?? 'moderate',
            ),
            evidenceSummary: evidenceSummary,
            directFeedback: directFeedback,
            redFlag: _readBool(map['red_flag']) ?? false,
          ),
        );
      }
      if (concerns.isEmpty) {
        return null;
      }
      return AppearanceProtocolLibrary.applyTemplates(
        generatedAt: DateTime.now(),
        overallSummary: overallSummary,
        directVerdict: directVerdict,
        concerns: concerns,
      );
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

  String _legacyCategoryFromDomain(String domain) {
    switch (domain.trim().toLowerCase()) {
      case 'physique':
        return 'physique';
      case 'style':
        return 'style';
      case 'hair':
        return 'style';
      case 'skin':
      default:
        return 'skin';
    }
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
        final content =
            (item as Map<String, dynamic>)['content'] as List<dynamic>? ?? [];
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

  String? _extractChatContent(String body) {
    try {
      final data = jsonDecode(body) as Map<String, dynamic>;
      final choices = data['choices'];
      if (choices is! List || choices.isEmpty) return null;
      final first = choices.first;
      if (first is! Map) return null;
      final message = first['message'];
      if (message is! Map) return null;
      return message['content']?.toString();
    } catch (_) {
      return null;
    }
  }

  String? _extractJsonFromText(String text) {
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start == -1 || end == -1 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  bool _openAiSupportsTemperature(String model) {
    final lower = model.toLowerCase();
    return !lower.startsWith('gpt-5');
  }

  bool _openAiUsesResponses(String model) {
    final lower = model.toLowerCase();
    return lower.startsWith('gpt-5');
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

  String? _readText(Map<String, dynamic> map, List<String> keys) {
    for (final key in keys) {
      final value = map[key];
      if (value == null) continue;
      final text = value.toString().trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }

  double? _readDouble(Object? raw) {
    if (raw is double) return raw;
    if (raw is int) return raw.toDouble();
    return double.tryParse(raw?.toString() ?? '');
  }

  bool? _readBool(Object? raw) {
    if (raw is bool) return raw;
    if (raw is int) return raw != 0;
    final text = raw?.toString().trim().toLowerCase();
    if (text == 'true' || text == '1' || text == 'yes') return true;
    if (text == 'false' || text == '0' || text == 'no') return false;
    return null;
  }

  String _normalizeSeverity(String raw) {
    switch (raw.trim().toLowerCase()) {
      case 'high':
        return 'high';
      case 'low':
        return 'low';
      case 'moderate':
      default:
        return 'moderate';
    }
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
