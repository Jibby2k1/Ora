import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

class DiagnosticsErrorEvent {
  DiagnosticsErrorEvent({
    required this.timestamp,
    required this.context,
    required this.error,
    required this.stackTrace,
    this.details,
  });

  final DateTime timestamp;
  final String context;
  final Object error;
  final StackTrace stackTrace;
  final String? details;

  String get summary => '$context: $error';

  String get fingerprint => [
        context,
        error.toString(),
        stackTrace.toString(),
        details ?? '',
      ].join('\n');

  String get report {
    final buffer = StringBuffer()
      ..writeln('Timestamp: ${timestamp.toIso8601String()}')
      ..writeln('Context: $context')
      ..writeln('Error: $error');
    final detailText = details?.trim();
    if (detailText != null && detailText.isNotEmpty) {
      buffer
        ..writeln('Details:')
        ..writeln(detailText);
    }
    buffer
      ..writeln('Stack trace:')
      ..write(stackTrace);
    return buffer.toString();
  }
}

class DiagnosticsLog {
  DiagnosticsLog._();

  static final DiagnosticsLog instance = DiagnosticsLog._();

  static const String _fileName = 'ora_diagnostics.log';
  static const int _maxLines = 2000;
  static const int _bufferLimit = 200;

  final List<String> _pendingLines = <String>[];
  final StreamController<DiagnosticsErrorEvent> _errorController =
      StreamController<DiagnosticsErrorEvent>.broadcast();

  File? _logFile;
  Future<void> _writeQueue = Future<void>.value();
  bool _initialized = false;
  DiagnosticsErrorEvent? _latestError;

  bool get isInitialized => _initialized;
  Stream<DiagnosticsErrorEvent> get errors => _errorController.stream;
  DiagnosticsErrorEvent? get latestError => _latestError;

  Future<void> initialize() async {
    if (_initialized) return;
    try {
      final directory = await getApplicationDocumentsDirectory();
      final file = File('${directory.path}/$_fileName');
      if (!await file.exists()) {
        await file.create(recursive: true);
      }
      _logFile = file;
      _initialized = true;
      if (_pendingLines.isNotEmpty) {
        final pending = List<String>.from(_pendingLines);
        _pendingLines.clear();
        for (final line in pending) {
          _enqueueWrite(line);
        }
      }
      record('Diagnostics logger initialized at ${file.path}');
    } catch (error, stackTrace) {
      _fallbackPrint(
          'Failed to initialize diagnostics log: $error\n$stackTrace');
    }
  }

  Future<String?> get logFilePath async {
    await initialize();
    return _logFile?.path;
  }

  String buildErrorReport(
    Object error,
    StackTrace stackTrace, {
    String context = 'Unhandled error',
    String? details,
    DateTime? timestamp,
  }) {
    return DiagnosticsErrorEvent(
      timestamp: timestamp ?? DateTime.now(),
      context: context,
      error: error,
      stackTrace: stackTrace,
      details: details,
    ).report;
  }

  void record(
    String message, {
    String level = 'INFO',
  }) {
    final line = '${DateTime.now().toIso8601String()} [$level] $message';
    _fallbackPrint(line);
    if (!_initialized || _logFile == null) {
      _pendingLines.add(line);
      if (_pendingLines.length > _bufferLimit) {
        _pendingLines.removeRange(0, _pendingLines.length - _bufferLimit);
      }
      return;
    }
    _enqueueWrite(line);
  }

  void recordError(
    Object error,
    StackTrace stackTrace, {
    String context = 'Unhandled error',
    String? details,
  }) {
    final event = DiagnosticsErrorEvent(
      timestamp: DateTime.now(),
      context: context,
      error: error,
      stackTrace: stackTrace,
      details: details,
    );
    _latestError = event;
    record(event.report, level: 'ERROR');
    _errorController.add(event);
  }

  void recordFlutterError(FlutterErrorDetails details) {
    FlutterError.presentError(details);
    final stackTrace = details.stack ?? StackTrace.current;
    final detailLines = <String>[];
    final library = details.library?.trim();
    if (library != null && library.isNotEmpty) {
      detailLines.add('Library: $library');
    }
    final information = details.informationCollector?.call();
    if (information != null) {
      for (final node in information) {
        final description = node.toDescription().trim();
        if (description.isNotEmpty) {
          detailLines.add(description);
        }
      }
    }
    recordError(
      details.exception,
      stackTrace,
      context: details.context?.toDescription() ?? 'Flutter framework error',
      details: detailLines.isEmpty ? null : detailLines.join('\n'),
    );
  }

  Future<List<String>> readTailLines({
    int maxLines = 200,
  }) async {
    await initialize();
    final file = _logFile;
    if (file == null || !await file.exists()) {
      return const <String>[];
    }
    try {
      final contents = await file.readAsString();
      final lines = contents
          .split('\n')
          .where((line) => line.trim().isNotEmpty)
          .toList(growable: false);
      if (lines.length <= maxLines) {
        return lines;
      }
      return lines.sublist(lines.length - maxLines);
    } catch (error, stackTrace) {
      recordError(
        error,
        stackTrace,
        context: 'Failed reading diagnostics log',
      );
      return const <String>[];
    }
  }

  Future<String> readTailText({
    int maxLines = 200,
  }) async {
    final lines = await readTailLines(maxLines: maxLines);
    return lines.join('\n');
  }

  void _enqueueWrite(String line) {
    _writeQueue = _writeQueue.then((_) async {
      final file = _logFile;
      if (file == null) return;
      try {
        await file.writeAsString('$line\n', mode: FileMode.append, flush: true);
        await _trimIfNeeded(file);
      } catch (error, stackTrace) {
        _fallbackPrint('Diagnostics log write failed: $error\n$stackTrace');
      }
    });
  }

  Future<void> _trimIfNeeded(File file) async {
    try {
      final contents = await file.readAsString();
      final lines =
          contents.split('\n').where((line) => line.trim().isNotEmpty).toList();
      if (lines.length <= _maxLines) {
        return;
      }
      final trimmed = lines.sublist(lines.length - _maxLines).join('\n');
      await file.writeAsString('$trimmed\n', flush: true);
    } catch (error, stackTrace) {
      _fallbackPrint('Diagnostics log trim failed: $error\n$stackTrace');
    }
  }

  void _fallbackPrint(String message) {
    // Use print() deliberately so logs appear in release console output too.
    // ignore: avoid_print
    print(message);
  }
}
