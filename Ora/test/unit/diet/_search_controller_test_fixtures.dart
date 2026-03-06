import 'package:ora/data/db/db.dart';
import 'package:ora/data/food/food_repository.dart';
import 'package:ora/data/repositories/diet_repo.dart';
import 'package:ora/domain/models/food_models.dart';

typedef SearchFoodsCallback = Future<List<FoodSearchResult>> Function(
  String query,
  int page,
  int pageSize,
  FoodSearchFilters filters,
);

typedef LookupBarcodeCallback = Future<FoodItem?> Function(String barcode);

class TestFoodSearchRepository extends FoodRepository {
  TestFoodSearchRepository({
    this.searchFoodsCallback,
    this.lookupBarcodeCallback,
  }) : super(
          db: AppDatabase.instance,
          dietRepo: DietRepo(AppDatabase.instance),
        );

  final SearchFoodsCallback? searchFoodsCallback;
  final LookupBarcodeCallback? lookupBarcodeCallback;

  @override
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    int pageSize = 20,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) {
    if (searchFoodsCallback == null) {
      return Future.value(const []);
    }
    return searchFoodsCallback!(query, page, pageSize, filters);
  }

  @override
  Future<FoodItem?> lookupBarcode(String barcode) {
    if (lookupBarcodeCallback == null) {
      return Future.value(null);
    }
    return lookupBarcodeCallback!(barcode);
  }
}
