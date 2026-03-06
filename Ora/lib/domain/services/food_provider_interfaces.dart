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
    implements
        FoodSearchProvider,
        FoodDetailProvider,
        FoodBarcodeProvider {
  FoodSource get source;
}
