import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../domain/models/food_models.dart';
import '../../domain/services/food_nutrient_mapper.dart';
import '../../domain/services/food_provider_interfaces.dart';

class OpenFoodFactsProvider implements FoodProvider {
  OpenFoodFactsProvider({
    http.Client? client,
    FoodNutrientMapper? mapper,
  })  : _client = client ?? http.Client(),
        _mapper = mapper ?? const FoodNutrientMapper();

  static const List<String> _searchHosts = <String>[
    'us.openfoodfacts.net',
    'world.openfoodfacts.net',
  ];
  static const List<String> _detailHosts = <String>[
    'us.openfoodfacts.net',
    'world.openfoodfacts.org',
    'world.openfoodfacts.net',
  ];
  static const Duration _searchTimeout = Duration(milliseconds: 3000);
  static const Duration _detailTimeout = Duration(seconds: 4);

  final http.Client _client;
  final FoodNutrientMapper _mapper;
  static const Map<String, String> _headers = <String, String>{
    'User-Agent': 'Ora/1.0',
  };

  @override
  FoodSource get source => FoodSource.openFoodFacts;

  @override
  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    required int pageSize,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return const [];
    for (final host in _searchHosts) {
      try {
        final legacyResults = await _searchLegacy(
          host: host,
          query: trimmedQuery,
          page: page,
          pageSize: pageSize,
          category: filters.category,
        );
        if (legacyResults.isNotEmpty) {
          return legacyResults;
        }
      } on TimeoutException {
        continue;
      } catch (_) {
        continue;
      }
    }
    return const [];
  }

  Future<List<FoodSearchResult>> _searchLegacy({
    required String host,
    required String query,
    required int page,
    required int pageSize,
    required FoodSearchCategory category,
  }) async {
    final queryTokens = _tokenizeQuery(query);
    final uri = Uri.https(
      host,
      '/cgi/search.pl',
      {
        'search_terms': query.trim(),
        'search_simple': '1',
        'action': 'process',
        'json': '1',
        'page': page.toString(),
        'page_size': pageSize.toString(),
        'fields': [
          'code',
          'id',
          'product_name',
          'product_name_en',
          'generic_name',
          'generic_name_en',
          'brands',
          'serving_size',
          'serving_quantity',
          'energy-kcal_100g',
          'energy_100g',
          'protein_100g',
          'carbohydrates_100g',
          'fat_100g',
          'sugars_100g',
          'fiber_100g',
        ].join(','),
      },
    );

    final response =
        await _client.get(uri, headers: _headers).timeout(_searchTimeout);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return const [];
    }

    final decoded = jsonDecode(response.body);
    if (decoded is! Map<String, dynamic>) return const [];
    final products = decoded['products'];
    if (products is! List) return const [];

    return _mapSearchResults(
      products: products,
      category: category,
      queryTokens: queryTokens,
    );
  }

  List<FoodSearchResult> _mapSearchResults({
    required List<dynamic> products,
    required FoodSearchCategory category,
    required List<String> queryTokens,
  }) {
    final results = <FoodSearchResult>[];
    for (final raw in products) {
      if (raw is! Map) continue;
      final product = Map<String, dynamic>.from(raw);
      final name = _firstNonEmptyValue([
        product['product_name_en']?.toString(),
        product['product_name']?.toString(),
        product['generic_name_en']?.toString(),
        product['generic_name']?.toString(),
        product['product_name_fr']?.toString(),
      ]);
      if (name == null) continue;

      final nutriments = product['nutriments'] is Map
          ? Map<String, dynamic>.from(product['nutriments'])
          : <String, dynamic>{};

      if (!_matchesQueryTokens(product: product, queryTokens: queryTokens)) {
        continue;
      }

      final hasNutrients =
          _hasAnyNutrientData(product: product, nutriments: nutriments);

      final id = _firstNonEmpty(product['code']?.toString()) ??
          _firstNonEmpty(product['id']?.toString()) ??
          '';
      if (id.isEmpty) continue;

      final brand = _firstNonEmpty(product['brands']?.toString());
      final serving = _firstNonEmpty(product['serving_size']?.toString());
      final isBranded = brand != null && brand.isNotEmpty;
      if (category == FoodSearchCategory.commonFoods && isBranded) {
        continue;
      }
      if (category == FoodSearchCategory.branded && !isBranded) {
        continue;
      }

      results.add(
        FoodSearchResult(
          id: id,
          source: FoodSource.openFoodFacts,
          name: name,
          brand: brand,
          barcode: _firstNonEmpty(product['code']?.toString()),
          subtitle: serving,
          dataType: 'open_food_facts',
          isBranded: isBranded,
          hasRichNutrientPanel: hasNutrients,
        ),
      );
    }

    return results;
  }

  bool _matchesQueryTokens({
    required Map<String, dynamic> product,
    required List<String> queryTokens,
  }) {
    if (queryTokens.isEmpty) return true;
    final searchable = [
      product['product_name_en']?.toString(),
      product['product_name']?.toString(),
      product['generic_name_en']?.toString(),
      product['generic_name']?.toString(),
      product['brands']?.toString(),
    ]
        .whereType<String>()
        .join(' ')
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    if (searchable.isEmpty) return false;

    if (queryTokens.length == 1) {
      return searchable.contains(queryTokens.first);
    }
    return queryTokens.every(searchable.contains);
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return lookupByBarcode(id);
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    Map<String, dynamic>? product;
    for (final host in _detailHosts) {
      final uri = Uri.https(
        host,
        '/api/v2/product/$trimmed',
        {
          'fields': [
            'code',
            'product_name',
            'product_name_en',
            'brands',
            'ingredients_text',
            'serving_size',
            'serving_quantity',
            'product_quantity',
            'nutriments',
          ].join(','),
        },
      );

      try {
        final response =
            await _client.get(uri, headers: _headers).timeout(_detailTimeout);
        if (response.statusCode < 200 || response.statusCode >= 300) {
          continue;
        }
        final decoded = jsonDecode(response.body);
        if (decoded is! Map<String, dynamic>) {
          continue;
        }
        final status = decoded['status'];
        if (status is num && status != 1) {
          continue;
        }
        final productRaw = decoded['product'];
        if (productRaw is! Map) {
          continue;
        }
        product = Map<String, dynamic>.from(productRaw);
        break;
      } catch (_) {
        continue;
      }
    }
    if (product == null) {
      return null;
    }

    final name = _firstNonEmpty(
      product['product_name_en']?.toString(),
      product['product_name']?.toString(),
    );
    if (name == null) return null;

    final nutrimentsRaw = product['nutriments'];
    final nutriments = nutrimentsRaw is Map
        ? Map<String, dynamic>.from(nutrimentsRaw)
        : <String, dynamic>{};

    var nutrients = _mapper.fromOpenFoodFactsNutriments(
      nutriments,
      perServing: false,
    );
    var nutrientsPer100g = true;
    if (nutrients.isEmpty) {
      nutrients = _mapper.fromOpenFoodFactsNutriments(
        nutriments,
        perServing: true,
      );
      nutrientsPer100g = false;
    }
    if (nutrients.isEmpty) return null;

    final servingOptions =
        _buildServingOptions(product, nutrientsPer100g: nutrientsPer100g);

    return FoodItem(
      id: trimmed,
      source: FoodSource.openFoodFacts,
      name: name,
      brand: _firstNonEmpty(product['brands']?.toString()),
      barcode: trimmed,
      ingredientsText: _firstNonEmpty(product['ingredients_text']?.toString()),
      servingOptions: servingOptions,
      nutrients: nutrients,
      nutrientsPer100g: nutrientsPer100g,
      lastUpdated: DateTime.now(),
      sourceDescription: 'Open Food Facts',
    );
  }

  List<ServingOption> _buildServingOptions(
    Map<String, dynamic> product, {
    required bool nutrientsPer100g,
  }) {
    final options = <ServingOption>[];

    final servingSize = _firstNonEmpty(product['serving_size']?.toString());
    final servingQuantity = _parseDouble(product['serving_quantity']);
    final servingGrams = _extractGramsFromText(servingSize) ??
        _extractGramsFromText(product['product_quantity']?.toString());

    if (nutrientsPer100g) {
      options.add(
        const ServingOption(
          id: '100g',
          label: '100 g',
          amount: 100,
          unit: 'g',
          gramWeight: 100,
          isDefault: true,
        ),
      );

      if (servingSize != null) {
        options.add(
          ServingOption(
            id: 'serving',
            label: servingSize,
            amount: servingQuantity ?? 1,
            unit: null,
            gramWeight: servingGrams,
          ),
        );
      }
    } else {
      options.add(
        ServingOption(
          id: 'serving',
          label: servingSize ?? '1 serving',
          amount: servingQuantity ?? 1,
          unit: null,
          gramWeight: servingGrams,
          isDefault: true,
        ),
      );

      if (servingGrams != null && servingGrams > 0) {
        options.add(
          const ServingOption(
            id: '100g',
            label: '100 g',
            amount: 100,
            unit: 'g',
            gramWeight: 100,
          ),
        );
      }
    }

    return options;
  }

  String? _firstNonEmpty(String? first, [String? second]) {
    final values = [first, second];
    for (final value in values) {
      if (value == null) continue;
      final trimmed = value.trim();
      if (trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }

  String? _firstNonEmptyValue(Iterable<String?> values) {
    for (final value in values) {
      final normalized = _firstNonEmpty(value);
      if (normalized != null && normalized.isNotEmpty) {
        return normalized;
      }
    }
    return null;
  }

  bool _hasAnyNutrientData({
    required Map<String, dynamic> product,
    required Map<String, dynamic> nutriments,
  }) {
    const productFields = <String>[
      'energy-kcal_100g',
      'energy_100g',
      'protein_100g',
      'fat_100g',
      'carbohydrates_100g',
      'sugars_100g',
      'fiber_100g',
    ];
    for (final field in productFields) {
      if (_parseDouble(product[field]) != null) return true;
      if (_parseDouble(nutriments[field]) != null) return true;
    }
    return false;
  }

  double? _extractGramsFromText(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    final gramMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*g\b').firstMatch(lower);
    if (gramMatch != null) {
      return double.tryParse(gramMatch.group(1) ?? '');
    }

    final mlMatch = RegExp(r'([0-9]+(?:\.[0-9]+)?)\s*ml\b').firstMatch(lower);
    if (mlMatch != null) {
      return double.tryParse(mlMatch.group(1) ?? '');
    }

    return null;
  }

  List<String> _tokenizeQuery(String query) {
    return query
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty)
        .toList(growable: false);
  }
}

double? _parseDouble(Object? value) {
  if (value == null) return null;
  if (value is num) return value.toDouble();
  return double.tryParse(value.toString());
}
