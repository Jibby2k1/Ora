import 'package:flutter_test/flutter_test.dart';

import 'package:ares_tracker/domain/services/pr_service.dart';

void main() {
  test('dominance PR detects new best', () {
    final service = PrService();
    final prior = [
      {'weight_value': 100.0, 'reps': 5},
      {'weight_value': 90.0, 'reps': 8},
    ];

    expect(service.isDominancePr(weight: 105, reps: 5, priorSets: prior), isTrue);
    expect(service.isDominancePr(weight: 100, reps: 5, priorSets: prior), isFalse);
    expect(service.isDominancePr(weight: 90, reps: 8, priorSets: prior), isFalse);
    expect(service.isDominancePr(weight: 95, reps: 9, priorSets: prior), isTrue);
  });

  test('non PR when missing weight or reps', () {
    final service = PrService();
    expect(service.isDominancePr(weight: null, reps: 5, priorSets: []), isFalse);
    expect(service.isDominancePr(weight: 100, reps: null, priorSets: []), isFalse);
  });
}
