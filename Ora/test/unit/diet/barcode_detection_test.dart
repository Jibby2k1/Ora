import 'package:flutter_test/flutter_test.dart';
import 'package:ora/ui/screens/diet/food_search_controller.dart';

import '_search_controller_test_fixtures.dart';

void main() {
  test('numeric 8-14 digit query uses barcode lookup instead of text search', () async {
    var lookupCalls = 0;
    var searchCalls = 0;
    final controller = FoodSearchController(
      repository: TestFoodSearchRepository(
        searchFoodsCallback: (query, page, pageSize, filters) {
          searchCalls++;
          return Future.value(const []);
        },
        lookupBarcodeCallback: (_) {
          lookupCalls++;
          return Future.value(null);
        },
      ),
      debounceDuration: const Duration(milliseconds: 350),
    );

    controller.onQueryChanged('12345678');
    await Future<void>.delayed(const Duration(milliseconds: 380));
    expect(lookupCalls, equals(1));
    expect(searchCalls, equals(0));
  });

  test('short numeric query falls back to text search path', () async {
    var searchCalls = 0;
    final controller = FoodSearchController(
      repository: TestFoodSearchRepository(
        searchFoodsCallback: (query, page, pageSize, filters) {
          searchCalls++;
          return Future.value(const []);
        },
      ),
      debounceDuration: const Duration(milliseconds: 350),
    );

    controller.onQueryChanged('1234');
    await Future<void>.delayed(const Duration(milliseconds: 380));
    expect(searchCalls, equals(1));
  });
}
