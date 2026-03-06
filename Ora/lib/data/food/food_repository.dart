import 'dart:async';
import 'dart:math';

import '../../core/config/food_api_config.dart';
import '../../data/db/db.dart';
import '../../domain/models/food_models.dart';
import 'custom_food_provider.dart';
import 'food_cache_store.dart';
import 'nutritionix_provider.dart';
import 'open_food_facts_provider.dart';
import 'usda_fdc_provider.dart';
import 'search_ranker.dart';
import '../repositories/diet_repo.dart';

class FoodRepository {
  FoodRepository({
    required AppDatabase db,
    required DietRepo dietRepo,
    UsdaFdcProvider? usdaProvider,
    OpenFoodFactsProvider? openFoodFactsProvider,
    NutritionixProvider? nutritionixProvider,
    CustomFoodProvider? customProvider,
    Duration searchCacheTtl = const Duration(hours: 24),
    Duration detailCacheTtl = const Duration(days: 7),
  })  : _cache = FoodCacheStore(db),
        _usdaProvider = usdaProvider ??
            UsdaFdcProvider(apiKey: FoodApiConfig.usdaFdcApiKey),
        _openFoodFactsProvider =
            openFoodFactsProvider ?? OpenFoodFactsProvider(),
        _nutritionixProvider = nutritionixProvider ??
            NutritionixProvider(
              appId: FoodApiConfig.nutritionixAppId,
              apiKey: FoodApiConfig.nutritionixApiKey,
            ),
        _customProvider = customProvider ?? CustomFoodProvider(dietRepo),
        _dietRepo = dietRepo,
        _searchCacheTtl = searchCacheTtl,
        _detailCacheTtl = detailCacheTtl;

  static const int _cacheSchemaVersion = 3;
  static const Set<String> _searchStopWords = {'a', 'an', 'and', 'the', 'of'};

  final FoodCacheStore _cache;
  final UsdaFdcProvider _usdaProvider;
  final OpenFoodFactsProvider _openFoodFactsProvider;
  final NutritionixProvider _nutritionixProvider;
  final CustomFoodProvider _customProvider;
  final DietRepo _dietRepo;
  final Duration _searchCacheTtl;
  final Duration _detailCacheTtl;
  final FoodSearchRanker _searchRanker = const FoodSearchRanker();
  DateTime? _recentNameCacheAt;
  Set<String> _recentNameCache = const {};

  bool get isNutritionixEnabled => _nutritionixProvider.isEnabled;
  bool get isUsdaEnabled => _usdaProvider.isEnabled;

  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    int pageSize = 20,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) async {
    final rawQuery = query.trim();
    final normalizedQuery = _normalizeQuery(rawQuery);
    final effectiveQuery =
        normalizedQuery.isNotEmpty ? normalizedQuery : rawQuery.toLowerCase();
    if (effectiveQuery.isEmpty) return const [];

    final pageIndex = max(1, page);
    final normalizedPageSize = pageSize <= 0 ? 20 : pageSize;
    final usdaSearchQueries = _dedupeQueries(
      normalizedQuery.isEmpty
          ? <String>[effectiveQuery]
          : _buildQueryVariants(
              normalizedQuery,
              mode: _SearchQueryStrategy.usda,
            )
        ..insert(0, effectiveQuery),
    );
    final fallbackSearchQueries = _dedupeQueries(
      normalizedQuery.isEmpty
          ? <String>[effectiveQuery]
          : _buildQueryVariants(
              normalizedQuery,
              mode: _SearchQueryStrategy.fallback,
            )
        ..insert(0, effectiveQuery),
    );

    if (_isBarcodeQuery(normalizedQuery) &&
        filters.category != FoodSearchCategory.custom) {
      final barcodeFood = await lookupBarcode(normalizedQuery);
      if (barcodeFood == null) return const [];
      return [
        FoodSearchResult(
          id: barcodeFood.id,
          source: barcodeFood.source,
          name: barcodeFood.name,
          brand: barcodeFood.brand,
          barcode: barcodeFood.barcode,
          subtitle: barcodeFood.sourceDescription,
          isBranded: barcodeFood.barcode != null,
          hasRichNutrientPanel: barcodeFood.nutrients.isNotEmpty,
        ),
      ];
    }

    final cacheKey = _searchCacheKey(
      query: effectiveQuery,
      page: pageIndex,
      pageSize: normalizedPageSize,
      filters: filters,
    );
    final cached = await _cache.getJson(
      cacheKey,
      expectedSchemaVersion: _cacheSchemaVersion,
    );
    if (cached != null) {
      final list = cached['results'];
      if (list is List) {
        final cachedResults = _decodeSearchResults(list);
        if (cachedResults.isNotEmpty) {
          return cachedResults;
        }
        await _cache.delete(cacheKey);
      }
    }

    final results = <FoodSearchResult>[];
    switch (filters.category) {
      case FoodSearchCategory.commonFoods:
        if (isUsdaEnabled) {
          results.addAll(await _searchWithFallbackQueries(
            queries: usdaSearchQueries,
            maxAttempts: 2,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => _usdaProvider.searchFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: normalizedPageSize,
                filters: filters,
              ),
            ),
          ));
        }
        if (isNutritionixEnabled && results.isEmpty) {
          results.addAll(await _safeSearchFoods(
            () => _nutritionixProvider.searchFoods(
              query: effectiveQuery,
              page: pageIndex,
              pageSize: normalizedPageSize,
              filters: const FoodSearchFilters(
                  category: FoodSearchCategory.commonFoods),
            ),
          ));
        }
        if (results.isEmpty) {
          results.addAll(await _searchWithFallbackQueries(
            queries: fallbackSearchQueries,
            maxAttempts: 1,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => _openFoodFactsProvider.searchFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: normalizedPageSize,
                filters: filters,
              ),
            ),
          ));
        }
        break;
      case FoodSearchCategory.branded:
        if (isUsdaEnabled) {
          results.addAll(await _searchWithFallbackQueries(
            queries: usdaSearchQueries,
            maxAttempts: 2,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => _usdaProvider.searchFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: normalizedPageSize,
                filters: filters,
              ),
            ),
          ));
        }
        if (isNutritionixEnabled) {
          results.addAll(await _safeSearchFoods(
            () => _nutritionixProvider.searchFoods(
              query: effectiveQuery,
              page: pageIndex,
              pageSize: normalizedPageSize,
              filters: filters,
            ),
          ));
        }
        if (results.isEmpty) {
          results.addAll(await _searchWithFallbackQueries(
            queries: fallbackSearchQueries,
            maxAttempts: 1,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => _openFoodFactsProvider.searchFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: normalizedPageSize,
                filters: filters,
              ),
            ),
          ));
        }
        break;
      case FoodSearchCategory.custom:
        results.addAll(await _safeSearchFoods(
          () => _customProvider.searchFoods(
            query: effectiveQuery,
            page: pageIndex,
            pageSize: normalizedPageSize,
            filters: filters,
          ),
        ));
        break;
    }

    final deduped = _dedupeSearchResults(results);
    final recentNames = await _loadRecentFoodNames();
    final ranked = _searchRanker.rankResults(
      input: deduped,
      query: effectiveQuery,
      category: filters.category,
      recentNames: recentNames,
    );

    if (ranked.isNotEmpty) {
      await _cache.setJson(
        cacheKey,
        {
          'results': _encodeSearchResults(ranked),
        },
        ttl: _searchCacheTtl,
        schemaVersion: _cacheSchemaVersion,
      );
    } else {
      await _cache.delete(cacheKey);
    }

    unawaited(_prefetchTopDetails(ranked.take(3)));
    return ranked;
  }

  Future<List<FoodSearchResult>> _safeSearchFoods(
    Future<List<FoodSearchResult>> Function() query,
  ) async {
    try {
      return await query();
    } catch (_) {
      return const [];
    }
  }

  Future<List<FoodSearchResult>> _searchWithFallbackQueries({
    required List<String> queries,
    required int maxAttempts,
    required Future<List<FoodSearchResult>> Function(String) search,
  }) async {
    var attempts = 0;
    for (final queryCandidate in queries) {
      if (attempts >= maxAttempts) break;
      final trimmed = queryCandidate.trim();
      if (trimmed.isEmpty) continue;
      attempts += 1;
      final found = await search(trimmed);
      if (found.isNotEmpty) {
        return found;
      }
    }
    return const [];
  }

  Future<FoodItem?> fetchFoodDetail(FoodSearchResult result) async {
    final cacheKey = _detailCacheKey(result.source, result.id);
    final cached = await _cache.getJson(
      cacheKey,
      expectedSchemaVersion: _cacheSchemaVersion,
    );
    if (cached != null) {
      return FoodItem.fromJson(cached);
    }

    final resolved = await _fetchFoodDetailFromProvider(
      source: result.source,
      id: result.id,
    );
    if (resolved == null) return null;

    await _cache.setJson(
      cacheKey,
      resolved.toJson(),
      ttl: _detailCacheTtl,
      schemaVersion: _cacheSchemaVersion,
    );

    return resolved;
  }

  Future<FoodItem?> lookupBarcode(String barcode) async {
    final trimmed = barcode.trim();
    if (trimmed.isEmpty) return null;

    final cacheKey = _barcodeCacheKey(trimmed);
    final cached = await _cache.getJson(
      cacheKey,
      expectedSchemaVersion: _cacheSchemaVersion,
    );
    if (cached != null) {
      return FoodItem.fromJson(cached);
    }

    FoodItem? result;
    result ??= await _usdaProvider.lookupByBarcode(trimmed);
    result ??= await _openFoodFactsProvider.lookupByBarcode(trimmed);
    result ??= isNutritionixEnabled
        ? await _nutritionixProvider.lookupByBarcode(trimmed)
        : null;
    result ??= await _customProvider.lookupByBarcode(trimmed);

    if (result != null) {
      await _cache.setJson(
        cacheKey,
        result.toJson(),
        ttl: _detailCacheTtl,
        schemaVersion: _cacheSchemaVersion,
      );
      await _cache.setJson(
        _detailCacheKey(result.source, result.id),
        result.toJson(),
        ttl: _detailCacheTtl,
        schemaVersion: _cacheSchemaVersion,
      );
    }

    return result;
  }

  Future<void> purgeExpiredCache() => _cache.purgeExpired();

  Future<void> _prefetchTopDetails(Iterable<FoodSearchResult> results) async {
    for (final result in results) {
      final detailKey = _detailCacheKey(result.source, result.id);
      final cached = await _cache.getJson(
        detailKey,
        expectedSchemaVersion: _cacheSchemaVersion,
      );
      if (cached != null) continue;
      try {
        final detail = await _fetchFoodDetailFromProvider(
          source: result.source,
          id: result.id,
        );
        if (detail == null) continue;
        await _cache.setJson(
          detailKey,
          detail.toJson(),
          ttl: _detailCacheTtl,
          schemaVersion: _cacheSchemaVersion,
        );
      } catch (_) {
        // Intentionally ignore prefetch failures.
      }
    }
  }

  Future<FoodItem?> _fetchFoodDetailFromProvider({
    required FoodSource source,
    required String id,
  }) {
    switch (source) {
      case FoodSource.usdaFdc:
        return _usdaProvider.fetchFoodDetailById(id);
      case FoodSource.openFoodFacts:
        return _openFoodFactsProvider.fetchFoodDetailById(id);
      case FoodSource.nutritionix:
        return _nutritionixProvider.fetchFoodDetailById(id);
      case FoodSource.custom:
        return _customProvider.fetchFoodDetailById(id);
    }
  }

  List<FoodSearchResult> _dedupeSearchResults(List<FoodSearchResult> input) {
    final seen = <String>{};
    final output = <FoodSearchResult>[];
    for (final item in input) {
      final key =
          '${_normalizeText(item.name)}|${_normalizeText(item.brand ?? '')}';
      if (seen.add(key)) {
        output.add(item);
      }
    }
    return output;
  }

  Future<Set<String>> _loadRecentFoodNames() async {
    final now = DateTime.now();
    final cachedAt = _recentNameCacheAt;
    if (cachedAt != null &&
        now.difference(cachedAt) < const Duration(minutes: 5)) {
      return _recentNameCache;
    }

    final recent = await _dietRepo.getRecentEntries(limit: 120);
    final names = <String>{};
    for (final entry in recent) {
      final normalized = _normalizeText(entry.mealName);
      if (normalized.isNotEmpty) {
        names.add(normalized);
      }
    }
    _recentNameCacheAt = now;
    _recentNameCache = names;
    return names;
  }

  String _searchCacheKey({
    required String query,
    required int page,
    required int pageSize,
    required FoodSearchFilters filters,
  }) {
    return 'search:${filters.category.name}:$query:$page:$pageSize:${isUsdaEnabled ? 1 : 0}:${isNutritionixEnabled ? 1 : 0}';
  }

  String _normalizeQuery(String value) {
    final normalized = value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(r'[^a-z0-9\s\"]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return normalized;
  }

  String _normalizeText(String value) {
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _buildQueryVariants(
    String normalizedQuery, {
    required _SearchQueryStrategy mode,
  }) {
    final variants = <String>[];
    switch (mode) {
      case _SearchQueryStrategy.usda:
        variants.add(_searchRanker.buildRequiredTokenQuery(normalizedQuery));
        variants.add(normalizedQuery);
        break;
      case _SearchQueryStrategy.fallback:
        variants.add(normalizedQuery);
        break;
    }

    final tokens = normalizedQuery
        .split(' ')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !_searchStopWords.contains(value))
        .toList(growable: false);

    if (tokens.isNotEmpty) {
      variants.add(tokens.first);
      if (tokens.length > 1) {
        variants.add(tokens.take(tokens.length - 1).join(' '));
      }
    }

    final deduped = <String>[];
    final seen = <String>{};
    for (final variant in variants) {
      final normalized = _normalizeQuery(variant);
      if (normalized.isNotEmpty && seen.add(normalized)) {
        deduped.add(normalized);
      }
    }
    return deduped;
  }

  List<String> _dedupeQueries(List<String> queries) {
    final output = <String>[];
    final seen = <String>{};
    for (final query in queries) {
      final normalized = _normalizeQuery(query);
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      output.add(normalized);
    }
    return output;
  }

  bool _isBarcodeQuery(String normalizedQuery) {
    if (normalizedQuery.length < 8 || normalizedQuery.length > 14) return false;
    return RegExp(r'^\d+$').hasMatch(normalizedQuery);
  }

  String _detailCacheKey(FoodSource source, String id) {
    return 'detail:${source.cacheKey}:${id.toLowerCase()}';
  }

  String _barcodeCacheKey(String barcode) {
    return 'barcode:${barcode.toLowerCase()}:${isNutritionixEnabled ? 1 : 0}';
  }

  List<Map<String, dynamic>> _encodeSearchResults(
      List<FoodSearchResult> results) {
    return results
        .map(
          (item) => {
            'id': item.id,
            'source': item.source.cacheKey,
            'name': item.name,
            'brand': item.brand,
            'barcode': item.barcode,
            'subtitle': item.subtitle,
            'dataType': item.dataType,
            'isBranded': item.isBranded,
            'hasRichNutrientPanel': item.hasRichNutrientPanel,
          },
        )
        .toList();
  }

  List<FoodSearchResult> _decodeSearchResults(List<dynamic> list) {
    final results = <FoodSearchResult>[];
    for (final item in list) {
      if (item is! Map) continue;
      final map = Map<String, dynamic>.from(item);
      final sourceRaw = map['source']?.toString() ?? FoodSource.custom.cacheKey;
      final source = FoodSource.values.firstWhere(
        (value) => value.cacheKey == sourceRaw,
        orElse: () => FoodSource.custom,
      );
      final id = map['id']?.toString();
      final name = map['name']?.toString();
      if (id == null || name == null || name.trim().isEmpty) continue;
      results.add(
        FoodSearchResult(
          id: id,
          source: source,
          name: name,
          brand: map['brand']?.toString(),
          barcode: map['barcode']?.toString(),
          subtitle: map['subtitle']?.toString(),
          dataType: map['dataType']?.toString(),
          isBranded: map['isBranded'] == true,
          hasRichNutrientPanel: map['hasRichNutrientPanel'] == true,
        ),
      );
    }
    return results;
  }
}

enum _SearchQueryStrategy {
  usda,
  fallback,
}
