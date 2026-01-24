import 'dart:async';

import 'package:flutter/foundation.dart';

class GeminiQueue {
  GeminiQueue._();

  static final GeminiQueue instance = GeminiQueue._();

  Future<void> _tail = Future.value();
  int _queued = 0;
  int _inFlight = 0;

  Future<T> run<T>(Future<T> Function() action, {String? label}) {
    final completer = Completer<T>();
    final tag = label ?? 'gemini';
    _queued += 1;
    debugPrint('[GeminiQueue] queued=$_queued inFlight=$_inFlight ($tag)');
    _tail = _tail.then((_) async {
      _queued -= 1;
      _inFlight += 1;
      debugPrint('[GeminiQueue] start queued=$_queued inFlight=$_inFlight ($tag)');
      try {
        final result = await action();
        completer.complete(result);
      } catch (e, st) {
        debugPrint('[GeminiQueue] error ($tag) $e');
        completer.completeError(e, st);
      } finally {
        _inFlight -= 1;
        debugPrint('[GeminiQueue] done queued=$_queued inFlight=$_inFlight ($tag)');
      }
    });
    return completer.future;
  }
}
