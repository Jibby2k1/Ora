import '../models/food_models.dart';
import 'food_provider_interfaces.dart';

/// Placeholder for licensed datasets (e.g., NCCDB, CNF licensed feeds).
///
/// IMPORTANT:
/// - Do not ingest proprietary nutrition datasets without a valid license.
/// - Implementors should provide authenticated APIs or data feeds approved by
///   the dataset owner before wiring into the repository.
abstract class LicensedFoodProvider implements FoodProvider {
  bool get isLicensed;

  @override
  FoodSource get source;

  @override
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    required int pageSize,
    FoodSearchFilters filters = const FoodSearchFilters(),
  });

  @override
  Future<FoodItem?> fetchFoodDetailById(String id);

  @override
  Future<FoodItem?> lookupByBarcode(String barcode);
}
