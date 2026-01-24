import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:ares_tracker/core/voice/nlu_parser.dart';

void main() {
  test('parses golden voice cases', () async {
    final file = File('test/golden_voice_cases.json');
    final data = jsonDecode(await file.readAsString()) as List<dynamic>;
    final parser = NluParser();

    for (final entry in data) {
      final map = entry as Map<String, dynamic>;
      final input = map['input'] as String;
      final expected = map['expected'] as Map<String, dynamic>;

      final result = parser.parse(input);
      expect(result, isNotNull, reason: 'No parse for "$input"');
      expect(result!.type, expected['type']);
      if (expected.containsKey('exerciseRef')) {
        expect(result.exerciseRef, expected['exerciseRef']);
      }
      if (expected.containsKey('weight')) {
        expect(result.weight, (expected['weight'] as num).toDouble());
      }
      if (expected.containsKey('reps')) {
        expect(result.reps, expected['reps']);
      }
      if (expected.containsKey('restSeconds')) {
        expect(result.restSeconds, expected['restSeconds']);
      }
    }
  });
}
