import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/food_models.dart';
import '../../domain/services/food_nutrient_mapper.dart';
import '../../domain/services/food_provider_interfaces.dart';

class NutritionixProvider implements FoodProvider {
  NutritionixProvider({
    required String appId,
    required String apiKey,
    http.Client? client,
    FoodNutrientMapper? mapper,
  })  : _appId = appId,
        _apiKey = apiKey,
        _client = client ?? http.Client(),
        _mapper = mapper ?? const FoodNutrientMapper();

  static const String _host = 'trackapi.nutritionix.com';

  final String _appId;
  final String _apiKey;
  final http.Client _client;
  final FoodNutrientMapper _mapper;

  @override
  FoodSource get source => FoodSource.nutritionix;

  bool get isEnabled =>
      _appId.trim().isNotEmpty && _apiKey.trim().isNotEmpty;

  Map<String, String> get _headers => {
        'x-app-id': _appId,
        'x-app-key': _apiKey,
        'x-remote-user-id': '0',
      };

  @override
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    required int pageSize,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) async {
    if (!isEnabled || query.trim().isEmpty) return const [];

    final uri = Uri.https(
      _host,
      '/v2/search/instant',
      {
        'query': query.trim(),
        'branded': filters.category == FoodSearchCategory.commonFoods ? 'false' : 'true',
        'common': filters.category == FoodSearchCategory.branded ? 'false' : 'true',
      },
    );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];

    final results = <FoodSearchResult>[];

    final common = decoded['common'];
    if (common is List && filters.category != FoodSearchCategory.branded) {
      for (final item in common) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['tag_id']?.toString() ?? map['food_name']?.toString();
        final name = map['food_name']?.toString();
        if (id == null || name == null || name.trim().isEmpty) continue;
        results.add(
          FoodSearchResult(
            id: id,
            source: FoodSource.nutritionix,
            name: _titleCase(name),
            subtitle: 'Nutritionix common',
            isBranded: false,
            hasRichNutrientPanel: true,
          ),
        );
      }
    }

    final branded = decoded['branded'];
    if (branded is List && filters.category != FoodSearchCategory.commonFoods) {
      for (final item in branded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final id = map['nix_item_id']?.toString();
        final name = map['food_name']?.toString();
        if (id == null || name == null || name.trim().isEmpty) continue;
        results.add(
          FoodSearchResult(
            id: id,
            source: FoodSource.nutritionix,
            name: _titleCase(name),
            brand: map['brand_name']?.toString(),
            barcode: map['upc']?.toString(),
            subtitle: map['serving_unit']?.toString(),
            isBranded: true,
            hasRichNutrientPanel: true,
          ),
        );
      }
    }

    final start = ((page - 1) * pageSize).clamp(0, results.length);
    final end = (start + pageSize).clamp(0, results.length);
    return results.sublist(start, end);
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) async {
    if (!isEnabled || id.trim().isEmpty) return null;
    final uri = Uri.https(
      _host,
      '/v2/search/item',
      {'nix_item_id': id.trim()},
    );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final foods = decoded['foods'];
    if (foods is! List || foods.isEmpty || foods.first is! Map) return null;
    return _mapFoodItem(Map<String, dynamic>.from(foods.first as Map));
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) async {
    if (!isEnabled || barcode.trim().isEmpty) return null;
    final uri = Uri.https(
      _host,
      '/v2/search/item',
      {'upc': barcode.trim()},
    );

    final response = await _client.get(uri, headers: _headers);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;
    final foods = decoded['foods'];
    if (foods is! List || foods.isEmpty || foods.first is! Map) return null;
    return _mapFoodItem(Map<String, dynamic>.from(foods.first as Map));
  }

  FoodItem _mapFoodItem(Map<String, dynamic> food) {
    final nutrients = <NutrientKey, NutrientValue>{};

    void add({
      required NutrientKey key,
      required String field,
      required String unit,
    }) {
      final raw = _parseDouble(food[field]);
      if (raw == null) return;
      final normalized = _mapper.normalizeToDefaultUnit(
        key: key,
        amount: raw,
        unit: unit,
      );
      nutrients[key] = NutrientValue(
        key: key,
        amount: normalized.amount,
        unit: normalized.unit,
      );
    }

    add(key: NutrientKey.calories, field: 'nf_calories', unit: 'kcal');
    add(key: NutrientKey.protein, field: 'nf_protein', unit: 'g');
    add(key: NutrientKey.carbs, field: 'nf_total_carbohydrate', unit: 'g');
    add(key: NutrientKey.fatTotal, field: 'nf_total_fat', unit: 'g');
    add(key: NutrientKey.satFat, field: 'nf_saturated_fat', unit: 'g');
    add(key: NutrientKey.transFat, field: 'nf_trans_fatty_acid', unit: 'g');
    add(key: NutrientKey.fiber, field: 'nf_dietary_fiber', unit: 'g');
    add(key: NutrientKey.sugar, field: 'nf_sugars', unit: 'g');
    add(key: NutrientKey.cholesterol, field: 'nf_cholesterol', unit: 'mg');
    add(key: NutrientKey.sodium, field: 'nf_sodium', unit: 'mg');
    add(key: NutrientKey.potassium, field: 'nf_potassium', unit: 'mg');

    final servingWeight = _parseDouble(food['serving_weight_grams']);
    final servingQty = _parseDouble(food['serving_qty']) ?? 1;
    final servingUnit = food['serving_unit']?.toString();

    return FoodItem(
      id: (food['nix_item_id'] ?? food['food_name']).toString(),
      source: FoodSource.nutritionix,
      name: _titleCase(food['food_name']?.toString() ?? 'Food item'),
      brand: food['brand_name']?.toString(),
      barcode: food['upc']?.toString(),
      ingredientsText: null,
      servingOptions: [
        ServingOption(
          id: 'serving',
          label: '${_formatNumber(servingQty)} ${servingUnit ?? 'serving'}',
          amount: servingQty,
          unit: servingUnit,
          gramWeight: servingWeight,
          isDefault: true,
        ),
        if (servingWeight != null && servingWeight > 0)
          const ServingOption(
            id: '100g',
            label: '100 g',
            amount: 100,
            unit: 'g',
            gramWeight: 100,
          ),
      ],
      nutrients: nutrients,
      nutrientsPer100g: false,
      lastUpdated: DateTime.now(),
      sourceDescription: 'Nutritionix',
    );
  }

  String _titleCase(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty) return value;
    return normalized
        .split(RegExp(r'\s+'))
        .map((segment) {
          if (segment.isEmpty) return segment;
          return segment[0].toUpperCase() + segment.substring(1).toLowerCase();
        })
        .join(' ');
  }

  String _formatNumber(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }
}

double? _parseDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
