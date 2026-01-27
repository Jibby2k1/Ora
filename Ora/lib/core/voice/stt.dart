import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:record/record.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:vosk_flutter/vosk_flutter.dart';

class SpeechToTextEngine {
  SpeechToTextEngine._();

  static final SpeechToTextEngine instance = SpeechToTextEngine._();

  VoskFlutterPlugin? _vosk;
  SpeechService? _speechService;
  Recognizer? _recognizer;
  Model? _model;
  bool _initialized = false;
  String? lastError;
  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _recordSub;
  bool _useRecord = false;
  bool _useARecord = false;
  Process? _linuxProcess;
  StreamSubscription<List<int>>? _linuxSub;
  StreamSubscription<List<int>>? _linuxErrSub;
  bool _hasResult = false;
  void Function(String)? _onResult;
  void Function(String)? _onPartial;
  void Function(Object error)? _onError;
  stt.SpeechToText? _iosSpeech;

  bool get isAvailable {
    if (kIsWeb) return false;
    if (Platform.isIOS) return true;
    return Platform.isAndroid || Platform.isLinux || Platform.isWindows;
  }

  Future<void> initialize() async {
    if (_initialized) return;
    if (!isAvailable) {
      lastError = 'STT not available on this platform.';
      return;
    }

    try {
      if (Platform.isIOS) {
        _iosSpeech = stt.SpeechToText();
        final ok = await _iosSpeech!.initialize(
          onError: (error) {
            lastError = error.errorMsg;
            _onError?.call(error.errorMsg);
          },
        );
        if (!ok) {
          final hasPermission = await _iosSpeech!.hasPermission;
          lastError = hasPermission
              ? 'Speech recognition unavailable.'
              : 'Microphone permission denied';
          return;
        }
        _initialized = true;
        return;
      }
      _vosk = VoskFlutterPlugin.instance();
      final loader = ModelLoader();
      var modelPath = await loader.loadFromAssets('assets/vosk/vosk-model-small-en-us-0.15.zip');
      if (!_isModelValid(modelPath)) {
        await _deleteModelFolder(modelPath);
        modelPath = await loader.loadFromAssets(
          'assets/vosk/vosk-model-small-en-us-0.15.zip',
          forceReload: true,
        );
      }
      _model = await _vosk!.createModel(modelPath);
      _recognizer = await _vosk!.createRecognizer(model: _model!, sampleRate: 16000);

      if (Platform.isAndroid) {
        _speechService = await _vosk!.initSpeechService(_recognizer!);
        _useRecord = false;
        _useARecord = false;
      } else if (Platform.isLinux) {
        final check = await Process.run('which', ['arecord']);
        if (check.exitCode != 0) {
          lastError = 'arecord not found. Install alsa-utils for Linux mic.';
          return;
        }
        _useARecord = true;
        _useRecord = false;
      } else {
        _useRecord = true;
        _useARecord = false;
      }
      _initialized = true;
    } catch (e) {
      lastError = e.toString();
    }
  }

  bool _isModelValid(String modelPath) {
    try {
      final conf = File('${modelPath}/conf/mfcc.conf');
      final model = File('${modelPath}/am/final.mdl');
      return conf.existsSync() && model.existsSync();
    } catch (_) {
      return false;
    }
  }

  Future<void> _deleteModelFolder(String modelPath) async {
    try {
      final dir = Directory(modelPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    } catch (_) {
      // ignore cleanup failures
    }
  }

  Future<String?> listenOnce({Duration timeout = const Duration(seconds: 8)}) async {
    await initialize();
    if (!_initialized) {
      return null;
    }
    if (Platform.isIOS) {
      final speech = _iosSpeech;
      if (speech == null) return null;
      final completer = Completer<String?>();
      Timer? timer;
      timer = Timer(timeout, () async {
        if (completer.isCompleted) return;
        await speech.stop();
        completer.complete(null);
      });
      await speech.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        onResult: (result) async {
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;
          if (result.finalResult) {
            timer?.cancel();
            await speech.stop();
            if (!completer.isCompleted) {
              completer.complete(text);
            }
          } else {
            _onPartial?.call(text);
          }
        },
      );
      return completer.future;
    }
    if (_speechService == null) {
      return null;
    }

    final completer = Completer<String?>();
    late StreamSubscription<String> sub;

    sub = _speechService!.onResult().listen((result) async {
      final text = _extractText(result);
      if (text.isEmpty) return;
      await _speechService!.stop();
      if (!completer.isCompleted) {
        completer.complete(text);
      }
      await sub.cancel();
    });

    await _speechService!.start();

    Future.delayed(timeout, () async {
      if (completer.isCompleted) return;
      await _speechService!.stop();
      await sub.cancel();
      completer.complete(null);
    });

    return completer.future;
  }

  Future<void> startListening({
    required void Function(String) onResult,
    void Function(String)? onPartial,
    void Function(Object error)? onError,
  }) async {
    _onResult = onResult;
    _onPartial = onPartial;
    _onError = onError;
    _hasResult = false;
    await initialize();
    if (!_initialized) {
      throw Exception(lastError ?? 'STT not initialized');
    }

    if (Platform.isIOS) {
      final speech = _iosSpeech;
      if (speech == null) {
        throw Exception(lastError ?? 'Speech recognition unavailable');
      }
      await speech.listen(
        listenMode: stt.ListenMode.dictation,
        partialResults: true,
        cancelOnError: true,
        onResult: (result) async {
          final text = result.recognizedWords.trim();
          if (text.isEmpty) return;
          if (result.finalResult) {
            await _emitResult(text);
          } else {
            _onPartial?.call(text);
          }
        },
      );
      return;
    }
    if (_recognizer == null) {
      throw Exception(lastError ?? 'STT not initialized');
    }

    if (_useARecord) {
      await _startLinuxARecord();
      return;
    }

    if (_useRecord) {
      final hasPermission = await _recorder.hasPermission();
      if (!hasPermission) {
        throw Exception('Microphone permission denied');
      }
      final stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 16000,
          numChannels: 1,
        ),
      );
      _recordSub?.cancel();
      _recordSub = stream.listen((data) async {
        if (_recognizer == null) return;
        final isFinal = await _recognizer!.acceptWaveformBytes(data);
        if (isFinal) {
          final result = await _recognizer!.getResult();
          final text = _extractText(result);
          if (text.isNotEmpty) {
            await _emitResult(text);
          }
        } else {
          final partial = await _recognizer!.getPartialResult();
          final text = _extractText(partial);
          if (text.isNotEmpty) {
            _onPartial?.call(text);
          }
        }
      }, onError: (error) {
        _onError?.call(error);
      });
      return;
    }

    _speechService!.onPartial().listen((partial) {
      final text = _extractText(partial);
      if (text.isNotEmpty) {
        onPartial?.call(text);
      }
    });

    _speechService!.onResult().listen((result) async {
      final text = _extractText(result);
      if (text.isEmpty) return;
      await _emitResult(text);
    }, onError: onError);

    await _speechService!.start();
  }

  Future<void> stopListening() async {
    if (Platform.isIOS) {
      await _iosSpeech?.stop();
      return;
    }
    if (_useARecord) {
      await _linuxSub?.cancel();
      _linuxSub = null;
      await _linuxErrSub?.cancel();
      _linuxErrSub = null;
      if (_linuxProcess != null) {
        _linuxProcess!.kill(ProcessSignal.sigint);
        _linuxProcess = null;
      }
      if (_recognizer != null && !_hasResult) {
        final finalResult = await _recognizer!.getFinalResult();
        final text = _extractText(finalResult);
        if (text.isNotEmpty) {
          await _emitResult(text);
        }
      }
      return;
    }

    if (_useRecord) {
      await _recordSub?.cancel();
      _recordSub = null;
      await _recorder.stop();
      if (_recognizer != null && !_hasResult) {
        final finalResult = await _recognizer!.getFinalResult();
        final text = _extractText(finalResult);
        if (text.isNotEmpty) {
          await _emitResult(text);
        }
      }
      return;
    }
    if (_speechService == null) return;
    await _speechService!.stop();
  }

  Future<void> _emitResult(String text) async {
    if (_hasResult) return;
    _hasResult = true;
    _onResult?.call(text);
  }

  Future<void> _startLinuxARecord() async {
    if (_linuxProcess != null) return;
    if (_recognizer == null) {
      throw Exception('Recognizer not initialized');
    }

    try {
      _linuxProcess = await Process.start(
        'arecord',
        const ['-q', '-f', 'S16_LE', '-r', '16000', '-c', '1', '-t', 'raw'],
      );
    } catch (e) {
      throw Exception('Failed to start arecord. Install alsa-utils. $e');
    }

    _linuxErrSub = _linuxProcess!.stderr.listen((_) {});
    _linuxSub = _linuxProcess!.stdout.listen((data) async {
      if (_recognizer == null) return;
      final isFinal = await _recognizer!.acceptWaveformBytes(
        Uint8List.fromList(data),
      );
      if (isFinal) {
        final result = await _recognizer!.getResult();
        final text = _extractText(result);
        if (text.isNotEmpty) {
          await _emitResult(text);
        }
      } else {
        final partial = await _recognizer!.getPartialResult();
        final text = _extractText(partial);
        if (text.isNotEmpty) {
          _onPartial?.call(text);
        }
      }
    }, onError: (error) {
      _onError?.call(error);
    });
  }

  String _extractText(String raw) {
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final text = decoded['text'] as String?;
      return text?.trim() ?? '';
    } catch (_) {
      return raw.trim();
    }
  }
}
