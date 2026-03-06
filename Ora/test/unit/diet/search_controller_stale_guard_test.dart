import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:ora/domain/models/food_models.dart';
import 'package:ora/ui/screens/diet/food_search_controller.dart';

import '_search_controller_test_fixtures.dart';

void main() {
  test('older search responses are ignored when query changes again', () async {
    final pending = <String, Completer<List<FoodSearchResult>>>{};

    final controller = FoodSearchController(
      repository: TestFoodSearchRepository(
        searchFoodsCallback: (query, page, pageSize, filters) {
          final completer = Completer<List<FoodSearchResult>>();
          pending[query] = completer;
          return completer.future;
        },
      ),
      debounceDuration: const Duration(milliseconds: 350),
    );

    controller.onQueryChanged('apple');
    await Future<void>.delayed(const Duration(milliseconds: 380));

    final staleRequest = pending['apple']!;
    expect(staleRequest.isCompleted, isFalse);

    controller.onQueryChanged('banana');
    await Future<void>.delayed(const Duration(milliseconds: 380));
    final freshRequest = pending['banana']!;

    freshRequest.complete([
      const FoodSearchResult(
        id: '2',
        source: FoodSource.usdaFdc,
        name: 'banana',
      ),
    ]);

    staleRequest.complete([
      const FoodSearchResult(
        id: '1',
        source: FoodSource.usdaFdc,
        name: 'apple',
      ),
    ]);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(controller.results, hasLength(1));
    expect(controller.results.single.id, '2');
  });
}
