import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:llama_cpp_dart/llama_cpp_dart.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

import 'voice_models.dart';

class LlmParser {
  LlmParser();

  static const _modelAsset =
      'assets/models/llm/qwen2.5-0.5b-instruct-q4_k_m.gguf';

  LlamaParent? _parent;
  bool _initialized = false;
  bool _initializing = false;
  String? lastError;
  String? lastRawOutput;
  String? lastPrompt;

  bool get isReady => _initialized;

  Future<void> initialize() async {
    if (_initialized || _initializing) return;
    _initializing = true;
    if (!(Platform.isAndroid || Platform.isIOS || Platform.isLinux)) {
      lastError = 'LLM parsing not supported on this platform.';
      _initializing = false;
      return;
    }

    try {
      final modelPath = await _ensureModelFile();
      if (modelPath == null) {
        _initializing = false;
        return;
      }

      if (Platform.isAndroid || Platform.isLinux) {
        Llama.libraryPath = 'libllama.so';
      }

      final modelParams = ModelParams()..nGpuLayers = 0;
      final contextParams = ContextParams()
        ..nCtx = 1024
        ..nPredict = 128
        ..nBatch = 256
        ..nThreads = 4
        ..nThreadsBatch = 4;
      final samplerParams = SamplerParams()
        ..temp = 0.1
        ..topP = 0.9
        ..topK = 40;

      final load = LlamaLoad(
        path: modelPath,
        modelParams: modelParams,
        contextParams: contextParams,
        samplingParams: samplerParams,
        format: ChatMLFormat(),
      );
      _parent = LlamaParent(load, ChatMLFormat());
      await _parent!.init();
      _initialized = true;
    } catch (e) {
      lastError = e.toString();
    } finally {
      _initializing = false;
    }
  }

  Future<NluCommand?> parse(String input) async {
    await initialize();
    if (!_initialized || _parent == null) {
      return null;
    }

    final prompt = _buildPrompt(input);
    lastPrompt = prompt;
    final scope = _parent!.getScope() as LlamaScope;
    final buffer = StringBuffer();
    StreamSubscription<String>? sub;
    try {
      sub = scope.stream.listen(buffer.write);
      final promptId = await scope.sendPrompt(prompt);
      final completion = await scope.completions
          .firstWhere((event) => event.promptId == promptId)
          .timeout(const Duration(seconds: 8));
      if (!completion.success) {
        lastError = completion.errorDetails ?? 'LLM completion failed.';
        return null;
      }
    } catch (e) {
      lastError = e.toString();
      return null;
    } finally {
      await sub?.cancel();
      await scope.dispose();
    }

    lastRawOutput = buffer.toString();
    final jsonText = _extractJson(lastRawOutput ?? '');
    if (jsonText == null) {
      lastError = 'LLM output did not contain JSON.';
      return null;
    }

    try {
      final map = jsonDecode(jsonText) as Map<String, dynamic>;
      return _commandFromJson(map);
    } catch (e) {
      lastError = 'Failed to parse LLM JSON: $e';
      return null;
    }
  }

  Future<String?> _ensureModelFile() async {
    final supportDir = await getApplicationSupportDirectory();
    final modelDir = Directory(path.join(supportDir.path, 'llm'));
    if (!await modelDir.exists()) {
      await modelDir.create(recursive: true);
    }
    final modelPath = path.join(modelDir.path, path.basename(_modelAsset));
    final file = File(modelPath);
    if (await file.exists()) {
      return modelPath;
    }

    try {
      final data = await rootBundle.load(_modelAsset);
      await file.writeAsBytes(
        data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        flush: true,
      );
      return modelPath;
    } catch (e) {
      lastError =
          'Bundled model not found. Download it via tool/fetch_llm_model.py.';
      return null;
    }
  }

  String _buildPrompt(String input) {
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
  "rir": number|null,
  "rest_seconds": number|null
}
Rules:
- If intent is "log_set", ALWAYS include exercise_ref, reps, weight, and weight_unit when they are present.
- If the user says "same as last set" or "repeat last", set reps and weight to null and set exercise_ref if mentioned.
- If no exercise is mentioned, set exercise_ref to null.
- Use lb or kg only; otherwise null.
- Output integers for reps/partials.

Input: "$input"
JSON:
''';
  }

  NluCommand? _commandFromJson(Map<String, dynamic> json) {
    final intent = json['intent']?.toString();
    if (intent == null || intent.isEmpty) return null;

    switch (intent) {
      case 'undo':
      case 'redo':
        return NluCommand(type: intent);
      case 'rest':
        return NluCommand(
          type: 'rest',
          restSeconds: _asInt(json['rest_seconds']),
        );
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
