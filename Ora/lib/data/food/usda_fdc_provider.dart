import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/food_models.dart';
import '../../domain/services/food_nutrient_mapper.dart';
import '../../domain/services/food_provider_interfaces.dart';

class UsdaFdcProvider implements FoodProvider {
  UsdaFdcProvider({
    required String apiKey,
    http.Client? client,
    FoodNutrientMapper? mapper,
  })  : _apiKey = apiKey,
        _client = client ?? http.Client(),
        _mapper = mapper ?? const FoodNutrientMapper();

  static const String _host = 'api.nal.usda.gov';

  final String _apiKey;
  final http.Client _client;
  final FoodNutrientMapper _mapper;

  @override
  FoodSource get source => FoodSource.usdaFdc;

  bool get isEnabled => _apiKey.trim().isNotEmpty;

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
      '/fdc/v1/foods/search',
      {'api_key': _apiKey},
    );
    final body = <String, dynamic>{
      'query': query.trim(),
      'pageNumber': page,
      'pageSize': pageSize,
      'dataType': _dataTypesForCategory(filters.category),
    };

    final response = await _client.post(
      uri,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final foods = decoded['foods'];
    if (foods is! List) return const [];

    final results = <FoodSearchResult>[];
    for (final item in foods) {
      if (item is! Map) continue;
      final food = Map<String, dynamic>.from(item);
      final fdcId = food['fdcId']?.toString();
      final name = food['description']?.toString().trim();
      if (fdcId == null || fdcId.isEmpty || name == null || name.isEmpty) {
        continue;
      }
      final dataType = food['dataType']?.toString() ?? '';
      final brand = (food['brandOwner'] ?? food['brandName'])?.toString();
      final servingSize = _formatServing(food['servingSize'], food['servingSizeUnit']);
      final subtitle = [dataType, servingSize]
          .where((value) => value != null && value.trim().isNotEmpty)
          .join(' • ');

      results.add(
        FoodSearchResult(
          id: fdcId,
        source: FoodSource.usdaFdc,
        name: name,
        brand: brand,
        subtitle: subtitle.isEmpty ? null : subtitle,
        barcode: food['gtinUpc']?.toString(),
        isBranded: dataType.toLowerCase() == 'branded',
        dataType: dataType,
        hasRichNutrientPanel: true,
      ),
    );
    }
    return results;
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) async {
    if (!isEnabled || id.trim().isEmpty) return null;
    final uri = Uri.https(
      _host,
      '/fdc/v1/food/${id.trim()}',
      {'api_key': _apiKey},
    );

    final response = await _client.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return null;

    final dataType = decoded['dataType']?.toString() ?? '';
    final isBranded = dataType.toLowerCase() == 'branded';

    final labelNutrients = decoded['labelNutrients'];
    final hasLabelNutrients = labelNutrients is Map && labelNutrients.isNotEmpty;

    final List<ServingOption> servingOptions = [];
    final defaultServing = _resolveDefaultServing(decoded, isBranded: isBranded);
    servingOptions.add(defaultServing);
    servingOptions.addAll(
      _resolveAdditionalServings(decoded, defaultServing: defaultServing),
    );

    Map<NutrientKey, NutrientValue> nutrients;
    var nutrientsPer100g = true;
    if (isBranded && hasLabelNutrients) {
      nutrients = _mapLabelNutrients(Map<String, dynamic>.from(labelNutrients));
      nutrientsPer100g = false;
    } else {
      final nutrientsRaw = decoded['foodNutrients'];
      final nutrientList = nutrientsRaw is List ? nutrientsRaw : const <dynamic>[];
      nutrients = _mapper.fromUsdaFoodNutrients(nutrientList);
      nutrientsPer100g = true;
    }

    if (nutrients.isEmpty) return null;

    final fdcId = decoded['fdcId']?.toString() ?? id;
    final name = decoded['description']?.toString().trim();
    if (name == null || name.isEmpty) return null;

    return FoodItem(
      id: fdcId,
      source: FoodSource.usdaFdc,
      name: name,
      brand: (decoded['brandOwner'] ?? decoded['brandName'])?.toString(),
      barcode: decoded['gtinUpc']?.toString(),
      ingredientsText: decoded['ingredients']?.toString(),
      servingOptions: _dedupeServings(servingOptions),
      nutrients: nutrients,
      nutrientsPer100g: nutrientsPer100g,
      lastUpdated: DateTime.now(),
      sourceDescription: dataType.isEmpty ? 'USDA FoodData Central' : 'USDA $dataType',
    );
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) async {
    if (!isEnabled || barcode.trim().isEmpty) return null;
    final results = await searchFoods(
      query: barcode.trim(),
      page: 1,
      pageSize: 20,
      filters: const FoodSearchFilters(category: FoodSearchCategory.branded),
    );
    final exact = results.where((item) => item.barcode == barcode.trim()).toList();
    if (exact.isEmpty) return null;
    return fetchFoodDetailById(exact.first.id);
  }

  List<String> _dataTypesForCategory(FoodSearchCategory category) {
    switch (category) {
      case FoodSearchCategory.commonFoods:
        return const ['Foundation', 'SR Legacy'];
      case FoodSearchCategory.branded:
        return const ['Branded'];
      case FoodSearchCategory.custom:
        return const ['Foundation', 'SR Legacy', 'Branded'];
    }
  }

  ServingOption _resolveDefaultServing(
    Map<String, dynamic> food, {
    required bool isBranded,
  }) {
    if (!isBranded) {
      return const ServingOption(
        id: '100g',
        label: '100 g',
        amount: 100,
        unit: 'g',
        gramWeight: 100,
        isDefault: true,
      );
    }

    final servingSize = _parseDouble(food['servingSize']);
    final servingUnit = food['servingSizeUnit']?.toString();
    final parsedGramWeight = _gramsFromServing(
      amount: servingSize,
      unit: servingUnit,
    );

    final householdServing = food['householdServingFullText']?.toString();
    final householdGramWeight = _extractGramsFromText(householdServing);

    final gramWeight = parsedGramWeight ?? householdGramWeight;
    final amount = servingSize ?? 1;
    final unit = servingUnit ?? 'serving';
    return ServingOption(
      id: 'serving',
      label: householdServing?.trim().isNotEmpty == true
          ? householdServing!.trim()
          : '$amount $unit',
      amount: amount,
      unit: unit,
      gramWeight: gramWeight,
      isDefault: true,
    );
  }

  List<ServingOption> _resolveAdditionalServings(
    Map<String, dynamic> food, {
    required ServingOption defaultServing,
  }) {
    final options = <ServingOption>[];

    if (defaultServing.gramWeight != null) {
      options.add(
        const ServingOption(
          id: '100g',
          label: '100 g',
          amount: 100,
          unit: 'g',
          gramWeight: 100,
          isDefault: false,
        ),
      );
    }

    final portions = food['foodPortions'];
    if (portions is List) {
      for (var i = 0; i < portions.length; i++) {
        final raw = portions[i];
        if (raw is! Map) continue;
        final portion = Map<String, dynamic>.from(raw);
        final gramWeight = _parseDouble(portion['gramWeight']);
        if (gramWeight == null || gramWeight <= 0) continue;
        final amount = _parseDouble(portion['amount']) ?? 1;
        final modifier = portion['modifier']?.toString();
        final measureUnit = portion['measureUnit'];
        String label;
        if (modifier != null && modifier.trim().isNotEmpty) {
          label = modifier.trim();
        } else if (measureUnit is Map) {
          final unitName = measureUnit['name']?.toString() ??
              measureUnit['abbreviation']?.toString() ??
              'serving';
          label = '$amount $unitName';
        } else {
          label = '$amount serving';
        }

        options.add(
          ServingOption(
            id: 'portion_$i',
            label: '$label (${gramWeight.toStringAsFixed(0)} g)',
            amount: amount,
            unit: measureUnit is Map ? measureUnit['name']?.toString() : 'serving',
            gramWeight: gramWeight,
          ),
        );
      }
    }

    return options;
  }

  Map<NutrientKey, NutrientValue> _mapLabelNutrients(
    Map<String, dynamic> labelNutrients,
  ) {
    final nutrients = <NutrientKey, NutrientValue>{};

    void add({
      required NutrientKey key,
      required String field,
      String unit = '',
    }) {
      final raw = labelNutrients[field];
      if (raw is! Map) return;
      final value = _parseDouble(raw['value']);
      if (value == null) return;
      final normalized = _mapper.normalizeToDefaultUnit(
        key: key,
        amount: value,
        unit: unit,
      );
      nutrients[key] = NutrientValue(
        key: key,
        amount: normalized.amount,
        unit: normalized.unit,
      );
    }

    add(key: NutrientKey.calories, field: 'calories', unit: 'kcal');
    add(key: NutrientKey.protein, field: 'protein', unit: 'g');
    add(key: NutrientKey.carbs, field: 'carbohydrates', unit: 'g');
    add(key: NutrientKey.fatTotal, field: 'fat', unit: 'g');
    add(key: NutrientKey.satFat, field: 'saturatedFat', unit: 'g');
    add(key: NutrientKey.transFat, field: 'transFat', unit: 'g');
    add(key: NutrientKey.sugar, field: 'sugars', unit: 'g');
    add(key: NutrientKey.fiber, field: 'fiber', unit: 'g');
    add(key: NutrientKey.sodium, field: 'sodium', unit: 'mg');

    return nutrients;
  }

  List<ServingOption> _dedupeServings(List<ServingOption> input) {
    final seen = <String>{};
    final result = <ServingOption>[];
    for (final option in input) {
      final key = '${option.label}|${option.gramWeight ?? -1}|${option.isDefault}';
      if (seen.add(key)) {
        result.add(option);
      }
    }
    if (result.isEmpty) {
      result.add(
        const ServingOption(
          id: '100g',
          label: '100 g',
          amount: 100,
          unit: 'g',
          gramWeight: 100,
          isDefault: true,
        ),
      );
    }
    return result;
  }

  String? _formatServing(Object? size, Object? unit) {
    final servingSize = _parseDouble(size);
    if (servingSize == null) return null;
    final servingUnit = unit?.toString().trim();
    if (servingUnit == null || servingUnit.isEmpty) return null;
    return '${_formatNumber(servingSize)} $servingUnit';
  }

  double? _gramsFromServing({
    required double? amount,
    required String? unit,
  }) {
    if (amount == null || amount <= 0) return null;
    final normalized = unit?.trim().toLowerCase();
    if (normalized == null || normalized.isEmpty) return null;
    if (normalized == 'g' || normalized == 'gram' || normalized == 'grams') {
      return amount;
    }
    if (normalized == 'oz' || normalized == 'ounce' || normalized == 'ounces') {
      return amount * 28.3495;
    }
    return null;
  }

  double? _extractGramsFromText(String? text) {
    if (text == null) return null;
    final match = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*g\b', caseSensitive: false)
        .firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1) ?? '');
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
