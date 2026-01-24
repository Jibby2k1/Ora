import 'package:flutter_test/flutter_test.dart';

import 'package:ares_tracker/domain/services/set_plan_service.dart';

void main() {
  test('selects next role and amrap last set', () {
    final service = SetPlanService();
    final blocks = [
      SetPlanBlock(id: 1, orderIndex: 0, role: 'WARMUP', setCount: 2, amrapLastSet: false),
      SetPlanBlock(id: 2, orderIndex: 1, role: 'TOP', setCount: 1, amrapLastSet: true),
      SetPlanBlock(id: 3, orderIndex: 2, role: 'BACKOFF', setCount: 2, amrapLastSet: false),
    ];

    var result = service.nextExpected(blocks: blocks, existingSets: []);
    expect(result!.nextRole, 'WARMUP');
    expect(result.isAmrap, isFalse);

    result = service.nextExpected(blocks: blocks, existingSets: [
      {'set_role': 'WARMUP'}
    ]);
    expect(result!.nextRole, 'WARMUP');

    result = service.nextExpected(blocks: blocks, existingSets: [
      {'set_role': 'WARMUP'},
      {'set_role': 'WARMUP'}
    ]);
    expect(result!.nextRole, 'TOP');
    expect(result.isAmrap, isTrue);

    result = service.nextExpected(blocks: blocks, existingSets: [
      {'set_role': 'WARMUP'},
      {'set_role': 'WARMUP'},
      {'set_role': 'TOP'}
    ]);
    expect(result!.nextRole, 'BACKOFF');
  });
}
