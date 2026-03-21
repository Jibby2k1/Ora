import '../models/food_models.dart';

abstract class FoodSearchProvider {
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    required int pageSize,
    FoodSearchFilters filters = const FoodSearchFilters(),
  });
}

abstract class FoodDetailProvider {
  Future<FoodItem?> fetchFoodDetailById(String id);
}

abstract class FoodBarcodeProvider {
  Future<FoodItem?> lookupByBarcode(String barcode);
}

abstract class FoodProvider
    implements FoodSearchProvider, FoodDetailProvider, FoodBarcodeProvider {
  FoodSource get source;
}

/// Generic/common food source adapter.
///
/// USDA is the default implementation in-app today. Licensed datasets
/// (for example NCCDB) can be plugged in later by implementing this interface.
abstract class CommonFoodProvider implements FoodDetailProvider {
  String get providerName;

  bool get isEnabled;

  Future<List<FoodSearchResult>> searchCommonFoods({
    required String query,
    required int page,
    required int pageSize,
  });
}

abstract class BrandedFoodProvider
    implements FoodDetailProvider, FoodBarcodeProvider {
  String get providerName;

  bool get isEnabled;

  Future<List<FoodSearchResult>> searchBrandedFoods({
    required String query,
    required int page,
    required int pageSize,
  });
}

abstract class LocalFoodProvider
    implements FoodDetailProvider, FoodBarcodeProvider {
  String get providerName;

  Future<List<FoodSearchResult>> searchLocalFoods({
    required String query,
    required int page,
    required int pageSize,
  });
}
