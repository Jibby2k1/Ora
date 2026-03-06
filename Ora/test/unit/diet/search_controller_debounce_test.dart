import 'package:flutter_test/flutter_test.dart';
import 'package:ora/ui/screens/diet/food_search_controller.dart';

import '_search_controller_test_fixtures.dart';

void main() {
  test('search is debounced and fires only once after rapid typing', () async {
    final searchedQueries = <String>[];
    final controller = FoodSearchController(
      repository: TestFoodSearchRepository(
        searchFoodsCallback: (query, page, pageSize, filters) {
          searchedQueries.add(query);
          return Future.value(const []);
        },
      ),
      debounceDuration: const Duration(milliseconds: 350),
      requestTimeout: const Duration(seconds: 9),
    );

    controller.onQueryChanged('c');
    await Future<void>.delayed(const Duration(milliseconds: 500));
    expect(searchedQueries, isEmpty);

    controller.onQueryChanged('ap');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.onQueryChanged('app');
    await Future<void>.delayed(const Duration(milliseconds: 120));
    controller.onQueryChanged('apple');

    await Future<void>.delayed(const Duration(milliseconds: 340));
    expect(searchedQueries, isEmpty);

    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(searchedQueries, equals(['apple']));
  });
}
