import '../repositories/diet_repo.dart';
import '../../domain/models/diet_entry.dart';
import '../../domain/models/food_models.dart';
import '../../domain/services/food_provider_interfaces.dart';

class CustomFoodProvider implements FoodProvider {
  CustomFoodProvider(this._dietRepo);

  final DietRepo _dietRepo;

  @override
  FoodSource get source => FoodSource.custom;

  @override
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    required int pageSize,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) async {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) return const [];

    final recent = await _dietRepo.getRecentEntries(limit: 500);
    final seen = <String>{};
    final filtered = <FoodSearchResult>[];

    for (final entry in recent) {
      final key = entry.mealName.trim().toLowerCase();
      if (key.isEmpty || seen.contains(key)) continue;
      if (!key.contains(trimmed)) continue;
      seen.add(key);
      filtered.add(
        FoodSearchResult(
          id: _entryId(entry.id),
          source: FoodSource.custom,
          name: entry.mealName,
          subtitle: 'From your diary',
          barcode: _extractBarcode(entry.notes),
          isBranded: false,
          hasRichNutrientPanel: true,
        ),
      );
    }

    final start = ((page - 1) * pageSize).clamp(0, filtered.length);
    final end = (start + pageSize).clamp(0, filtered.length);
    return filtered.sublist(start, end);
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) async {
    final entryId = _parseEntryId(id);
    if (entryId == null) return null;

    final entries = await _dietRepo.getRecentEntries(limit: 500);
    final match = entries.where((entry) => entry.id == entryId).toList();
    if (match.isEmpty) return null;
    return _mapEntry(match.first);
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    final entries = await _dietRepo.getRecentEntries(limit: 500);
    for (final entry in entries) {
      if (_extractBarcode(entry.notes) == trimmed) {
        return _mapEntry(entry);
      }
    }
    return null;
  }

  FoodItem _mapEntry(DietEntry entry) {
    final nutrients = <NutrientKey, NutrientValue>{};

    void add({
      required NutrientKey key,
      required double? value,
      required String unit,
    }) {
      if (value == null) return;
      nutrients[key] = NutrientValue(key: key, amount: value, unit: unit);
    }

    add(key: NutrientKey.calories, value: entry.calories, unit: 'kcal');
    add(key: NutrientKey.protein, value: entry.proteinG, unit: 'g');
    add(key: NutrientKey.carbs, value: entry.carbsG, unit: 'g');
    add(key: NutrientKey.fatTotal, value: entry.fatG, unit: 'g');
    add(key: NutrientKey.fiber, value: entry.fiberG, unit: 'g');
    add(key: NutrientKey.sodium, value: entry.sodiumMg, unit: 'mg');

    final micros = entry.micros ?? const <String, double>{};
    micros.forEach((key, value) {
      final mapped = _microKeyMap[key.toLowerCase().trim()];
      if (mapped == null) return;
      nutrients[mapped] = NutrientValue(
        key: mapped,
        amount: value,
        unit: mapped.defaultUnit,
      );
    });

    return FoodItem(
      id: _entryId(entry.id),
      source: FoodSource.custom,
      name: entry.mealName,
      barcode: _extractBarcode(entry.notes),
      ingredientsText: null,
      servingOptions: const [
        ServingOption(
          id: 'serving',
          label: '1 serving',
          amount: 1,
          unit: 'serving',
          isDefault: true,
        ),
      ],
      nutrients: nutrients,
      nutrientsPer100g: false,
      lastUpdated: entry.loggedAt,
      sourceDescription: 'Custom diary item',
    );
  }

  String _entryId(int entryId) => 'diet_entry:$entryId';

  int? _parseEntryId(String value) {
    if (!value.startsWith('diet_entry:')) return null;
    return int.tryParse(value.split(':').last);
  }

  String? _extractBarcode(String? notes) {
    if (notes == null) return null;
    final match = RegExp(r'\[barcode:([^\]]+)\]').firstMatch(notes);
    if (match == null) return null;
    return match.group(1)?.trim();
  }

  static const Map<String, NutrientKey> _microKeyMap = {
    'potassium': NutrientKey.potassium,
    'calcium': NutrientKey.calcium,
    'iron': NutrientKey.iron,
    'magnesium': NutrientKey.magnesium,
    'zinc': NutrientKey.zinc,
    'vitamin_a': NutrientKey.vitaminA,
    'vitamin_c': NutrientKey.vitaminC,
    'vitamin_d': NutrientKey.vitaminD,
    'vitamin_e': NutrientKey.vitaminE,
    'vitamin_k': NutrientKey.vitaminK,
    'vitamin_b6': NutrientKey.vitaminB6,
    'vitamin_b12': NutrientKey.vitaminB12,
    'folate': NutrientKey.folate,
    'selenium': NutrientKey.selenium,
    'manganese': NutrientKey.manganese,
    'copper': NutrientKey.copper,
    'phosphorus': NutrientKey.phosphorus,
    'cholesterol': NutrientKey.cholesterol,
    'sat_fat': NutrientKey.satFat,
    'sugar': NutrientKey.sugar,
  };
}
