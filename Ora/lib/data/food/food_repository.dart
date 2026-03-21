import 'dart:async';
import 'dart:math';

import '../../core/config/food_api_config.dart';
import '../../data/db/db.dart';
import '../../diagnostics/diagnostics_log.dart';
import '../../domain/models/food_models.dart';
import '../../domain/services/food_provider_interfaces.dart';
import 'custom_food_provider.dart';
import 'food_cache_store.dart';
import 'nutritionix_provider.dart';
import 'open_food_facts_provider.dart';
import 'search_ranker.dart';
import 'search_lru_cache.dart';
import 'usda_fdc_provider.dart';
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
        _detailCacheTtl = detailCacheTtl,
        _memorySearchCache = SearchLruCache<String, List<FoodSearchResult>>(
          maxEntries: 100,
          ttl: searchCacheTtl,
        ),
        _memoryDetailCache = SearchLruCache<String, FoodItem>(
          maxEntries: 300,
          ttl: detailCacheTtl,
        ) {
    _commonFoodProviders = <CommonFoodProvider>[
      _UsdaCommonFoodProvider(_usdaProvider),
      if (_nutritionixProvider.isEnabled)
        _NutritionixCommonFoodProvider(_nutritionixProvider),
    ];
    _brandedFoodProviders = <BrandedFoodProvider>[
      _UsdaBrandedFoodProvider(_usdaProvider),
      if (_nutritionixProvider.isEnabled)
        _NutritionixBrandedFoodProvider(_nutritionixProvider),
    ];
    _localFoodProviders = <LocalFoodProvider>[
      _CustomLocalFoodProvider(_customProvider),
    ];
  }

  static const int _cacheSchemaVersion = 9;
  static const Set<String> _searchStopWords = {'a', 'an', 'and', 'the', 'of'};

  final FoodCacheStore _cache;
  final UsdaFdcProvider _usdaProvider;
  final OpenFoodFactsProvider _openFoodFactsProvider;
  final NutritionixProvider _nutritionixProvider;
  final CustomFoodProvider _customProvider;
  final DietRepo _dietRepo;
  final Duration _searchCacheTtl;
  final Duration _detailCacheTtl;
  final SearchLruCache<String, List<FoodSearchResult>> _memorySearchCache;
  final SearchLruCache<String, FoodItem> _memoryDetailCache;
  final FoodSearchRanker _searchRanker = const FoodSearchRanker();
  late final List<CommonFoodProvider> _commonFoodProviders;
  late final List<BrandedFoodProvider> _brandedFoodProviders;
  late final List<LocalFoodProvider> _localFoodProviders;
  DateTime? _recentNameCacheAt;
  Set<String> _recentNameCache = const {};
  DateTime? _favoriteNameCacheAt;
  Set<String> _favoriteNameCache = const {};

  bool get isNutritionixEnabled => _nutritionixProvider.isEnabled;
  bool get isUsdaEnabled => _usdaProvider.isEnabled;

  Future<List<FoodSearchResult>> searchFoods({
    required String query,
    required int page,
    int pageSize = 20,
    FoodSearchFilters filters = const FoodSearchFilters(),
  }) async {
    try {
      final rawQuery = query.trim();
      final normalizedQuery = _normalizeQuery(rawQuery);
      final effectiveQuery =
          normalizedQuery.isNotEmpty ? normalizedQuery : rawQuery.toLowerCase();
      if (effectiveQuery.isEmpty) return const [];
      final queryTokens = _queryTokens(effectiveQuery);

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
      final memoryCached = _memorySearchCache.get(cacheKey);
      if (memoryCached != null) {
        return memoryCached;
      }

      final cached = await _cache.getJson(
        cacheKey,
        expectedSchemaVersion: _cacheSchemaVersion,
      );
      if (cached != null) {
        final list = cached['results'];
        if (list is List) {
          final cachedResults = _decodeSearchResults(list);
          if (cachedResults.isNotEmpty) {
            _memorySearchCache.set(cacheKey, cachedResults);
            return cachedResults;
          }
          await _cache.delete(cacheKey);
        }
      }

      final results = <FoodSearchResult>[];
      switch (filters.category) {
        case FoodSearchCategory.all:
          final groupedResults = await Future.wait<List<FoodSearchResult>>([
            _searchLocalFoods(
              pageIndex: pageIndex,
              pageSize: normalizedPageSize,
              normalizedQuery: effectiveQuery,
            ),
            _searchCommonFoods(
              pageIndex: pageIndex,
              pageSize: normalizedPageSize,
              normalizedQuery: effectiveQuery,
              usdaSearchQueries: usdaSearchQueries,
            ),
            _searchBrandedFoods(
              pageIndex: pageIndex,
              pageSize: normalizedPageSize,
              normalizedQuery: effectiveQuery,
              usdaSearchQueries: usdaSearchQueries,
            ),
          ]);
          for (final group in groupedResults) {
            results.addAll(group);
          }
          break;
        case FoodSearchCategory.commonFoods:
          results.addAll(await _searchCommonFoods(
            pageIndex: pageIndex,
            pageSize: normalizedPageSize,
            normalizedQuery: effectiveQuery,
            usdaSearchQueries: usdaSearchQueries,
          ));
          break;
        case FoodSearchCategory.branded:
          results.addAll(await _searchBrandedFoods(
            pageIndex: pageIndex,
            pageSize: normalizedPageSize,
            normalizedQuery: effectiveQuery,
            usdaSearchQueries: usdaSearchQueries,
          ));
          break;
        case FoodSearchCategory.custom:
          results.addAll(await _searchLocalFoods(
            pageIndex: pageIndex,
            pageSize: normalizedPageSize,
            normalizedQuery: effectiveQuery,
          ));
          break;
      }

      DiagnosticsLog.instance.record(
        'Food search query="$effectiveQuery" category=${filters.category.name} rawResults=${results.length} usdaEnabled=$isUsdaEnabled demoUsda=${FoodApiConfig.isUsingDemoUsdaKey}',
      );

      final categoryFiltered = _filterResultsByCategory(
        input: results,
        category: filters.category,
      );
      final tokenFiltered = _filterResultsByQueryTokens(
        input: categoryFiltered,
        queryTokens: queryTokens,
      );
      final rankedInput = tokenFiltered;
      DiagnosticsLog.instance.record(
        'Food search filtered query="$effectiveQuery" category=${filters.category.name} categoryFiltered=${categoryFiltered.length} tokenFiltered=${tokenFiltered.length}',
      );
      final deduped = _dedupeSearchResults(rankedInput);
      final recentNames = await _loadRecentFoodNames();
      final favoriteNames = await _loadFavoriteFoodNames();
      final ranked = _searchRanker.rankResults(
        input: deduped,
        query: effectiveQuery,
        category: filters.category,
        recentNames: recentNames,
        favoriteNames: favoriteNames,
      );
      final prioritized = _prioritizeFoundationGenericResults(
        input: ranked,
        category: filters.category,
        query: effectiveQuery,
      );

      if (prioritized.isNotEmpty) {
        _memorySearchCache.set(cacheKey, prioritized);
        await _cache.setJson(
          cacheKey,
          {
            'results': _encodeSearchResults(prioritized),
          },
          ttl: _searchCacheTtl,
          schemaVersion: _cacheSchemaVersion,
        );
      } else {
        await _cache.delete(cacheKey);
      }

      unawaited(_prefetchTopDetails(prioritized.take(3)));
      return prioritized;
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'FoodRepository.searchFoods fallback',
      );
      try {
        return await _emergencyFallbackSearch(
          query: query,
          page: page,
          pageSize: pageSize,
          filters: filters,
        );
      } catch (fallbackError, fallbackStackTrace) {
        DiagnosticsLog.instance.recordError(
          fallbackError,
          fallbackStackTrace,
          context: 'FoodRepository.searchFoods emergency fallback failed',
        );
        return const [];
      }
    }
  }

  Future<List<FoodSearchResult>> _emergencyFallbackSearch({
    required String query,
    required int page,
    required int pageSize,
    required FoodSearchFilters filters,
  }) async {
    final normalized = _normalizeQuery(query);
    if (normalized.isEmpty) return const [];
    final normalizedPage = page <= 0 ? 1 : page;
    final normalizedPageSize = pageSize <= 0 ? 20 : pageSize;
    final queryTokens = _queryTokens(normalized);

    final results = <FoodSearchResult>[];
    switch (filters.category) {
      case FoodSearchCategory.all:
        results.addAll(await _searchLocalFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
        ));
        results.addAll(await _searchCommonFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
          usdaSearchQueries: _dedupeQueries(
            _buildQueryVariants(
              normalized,
              mode: _SearchQueryStrategy.usda,
            ),
          ),
        ));
        results.addAll(await _searchBrandedFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
          usdaSearchQueries: _dedupeQueries(
            _buildQueryVariants(
              normalized,
              mode: _SearchQueryStrategy.usda,
            ),
          ),
        ));
        break;
      case FoodSearchCategory.commonFoods:
        results.addAll(await _searchCommonFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
          usdaSearchQueries: _dedupeQueries(
            _buildQueryVariants(
              normalized,
              mode: _SearchQueryStrategy.usda,
            ),
          ),
        ));
        break;
      case FoodSearchCategory.branded:
        results.addAll(await _searchBrandedFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
          usdaSearchQueries: _dedupeQueries(
            _buildQueryVariants(
              normalized,
              mode: _SearchQueryStrategy.usda,
            ),
          ),
        ));
        break;
      case FoodSearchCategory.custom:
        results.addAll(await _searchLocalFoods(
          pageIndex: normalizedPage,
          pageSize: normalizedPageSize,
          normalizedQuery: normalized,
        ));
        break;
    }

    final categoryFiltered = _filterResultsByCategory(
      input: results,
      category: filters.category,
    );
    final tokenFiltered = _filterResultsByQueryTokens(
      input: categoryFiltered,
      queryTokens: queryTokens,
    );
    final rankedInput = tokenFiltered;
    final deduped = _dedupeSearchResults(rankedInput);
    return _searchRanker.rankResults(
      input: deduped,
      query: normalized,
      category: filters.category,
      recentNames: const {},
      favoriteNames: const {},
    );
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

  Future<List<FoodSearchResult>> _searchCommonFoods({
    required int pageIndex,
    required int pageSize,
    required String normalizedQuery,
    required List<String> usdaSearchQueries,
  }) async {
    final results = <FoodSearchResult>[];
    for (final provider in _commonFoodProviders) {
      if (!provider.isEnabled) continue;
      if (provider.providerName == _UsdaCommonFoodProvider.providerNameValue) {
        results.addAll(
          await _searchWithQueryVariants(
            queries: usdaSearchQueries,
            maxAttempts: 2,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => provider.searchCommonFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: pageSize,
              ),
            ),
          ),
        );
      } else {
        results.addAll(
          await _safeSearchFoods(
            () => provider.searchCommonFoods(
              query: normalizedQuery,
              page: pageIndex,
              pageSize: pageSize,
            ),
          ),
        );
      }
    }
    return results;
  }

  Future<List<FoodSearchResult>> _searchBrandedFoods({
    required int pageIndex,
    required int pageSize,
    required String normalizedQuery,
    required List<String> usdaSearchQueries,
  }) async {
    final results = <FoodSearchResult>[];
    for (final provider in _brandedFoodProviders) {
      if (!provider.isEnabled) continue;
      if (provider.providerName == _UsdaBrandedFoodProvider.providerNameValue) {
        results.addAll(
          await _searchWithQueryVariants(
            queries: usdaSearchQueries,
            maxAttempts: 2,
            search: (searchQueryCandidate) => _safeSearchFoods(
              () => provider.searchBrandedFoods(
                query: searchQueryCandidate,
                page: pageIndex,
                pageSize: pageSize,
              ),
            ),
          ),
        );
      } else {
        results.addAll(
          await _safeSearchFoods(
            () => provider.searchBrandedFoods(
              query: normalizedQuery,
              page: pageIndex,
              pageSize: pageSize,
            ),
          ),
        );
      }
    }
    return results;
  }

  Future<List<FoodSearchResult>> _searchLocalFoods({
    required int pageIndex,
    required int pageSize,
    required String normalizedQuery,
  }) async {
    final output = <FoodSearchResult>[];
    for (final provider in _localFoodProviders) {
      output.addAll(
        await _safeSearchFoods(
          () => provider.searchLocalFoods(
            query: normalizedQuery,
            page: pageIndex,
            pageSize: pageSize,
          ),
        ),
      );
    }
    return output;
  }

  Future<List<FoodSearchResult>> _searchWithQueryVariants({
    required List<String> queries,
    required int maxAttempts,
    required Future<List<FoodSearchResult>> Function(String) search,
  }) async {
    final selectedQueries = queries
        .where((value) => value.trim().isNotEmpty)
        .take(maxAttempts)
        .toList(growable: false);
    if (selectedQueries.isEmpty) return const [];

    final batches = await Future.wait<List<FoodSearchResult>>(
      selectedQueries.map(search),
    );
    final merged = <FoodSearchResult>[];
    for (final batch in batches) {
      merged.addAll(batch);
    }
    return _dedupeSearchResults(merged);
  }

  Future<FoodItem?> fetchFoodDetail(FoodSearchResult result) async {
    final cacheKey = _detailCacheKey(result.source, result.id);
    final memoryCached = _memoryDetailCache.get(cacheKey);
    if (memoryCached != null) {
      return memoryCached;
    }

    final cached = await _cache.getJson(
      cacheKey,
      expectedSchemaVersion: _cacheSchemaVersion,
    );
    if (cached != null) {
      final decoded = FoodItem.fromJson(cached);
      _memoryDetailCache.set(cacheKey, decoded);
      return decoded;
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
    _memoryDetailCache.set(cacheKey, resolved);

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
    if (isUsdaEnabled) {
      result = await _usdaProvider.lookupByBarcode(trimmed);
    }
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
      _memoryDetailCache.set(_detailCacheKey(result.source, result.id), result);
    }

    return result;
  }

  Future<void> purgeExpiredCache() => _cache.purgeExpired();

  Future<void> _prefetchTopDetails(Iterable<FoodSearchResult> results) async {
    for (final result in results) {
      final detailKey = _detailCacheKey(result.source, result.id);
      if (_memoryDetailCache.get(detailKey) != null) continue;
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
        _memoryDetailCache.set(detailKey, detail);
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

  Future<Set<String>> _loadFavoriteFoodNames() async {
    final now = DateTime.now();
    final cachedAt = _favoriteNameCacheAt;
    if (cachedAt != null &&
        now.difference(cachedAt) < const Duration(minutes: 5)) {
      return _favoriteNameCache;
    }

    // Favorites support is optional and can be wired to a dedicated table later.
    // Keep this method in place so ranking logic can consume favorites immediately
    // once persistence is enabled.
    _favoriteNameCacheAt = now;
    _favoriteNameCache = const <String>{};
    return _favoriteNameCache;
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
    if (mode == _SearchQueryStrategy.usda) {
      variants.add(_searchRanker.buildRequiredTokenQuery(normalizedQuery));
    }
    variants.add(normalizedQuery);

    final deduped = <String>[];
    final seen = <String>{};
    for (final variant in variants) {
      final normalized = _normalizeVariantQuery(
        variant,
        preserveRequiredTokens: mode == _SearchQueryStrategy.usda,
      );
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
      final normalized = _normalizeVariantQuery(
        query,
        preserveRequiredTokens: true,
      );
      if (normalized.isEmpty || !seen.add(normalized)) continue;
      output.add(normalized);
    }
    return output;
  }

  String _normalizeVariantQuery(
    String value, {
    required bool preserveRequiredTokens,
  }) {
    final pattern =
        preserveRequiredTokens ? r'[^a-z0-9\s\"\+]' : r'[^a-z0-9\s\"]';
    return value
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\u0000-\u001f]'), ' ')
        .replaceAll(RegExp(pattern), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  List<String> _queryTokens(String query) {
    return query
        .split(' ')
        .map((value) => value.trim())
        .where((value) => value.isNotEmpty && !_searchStopWords.contains(value))
        .toList(growable: false);
  }

  List<FoodSearchResult> _filterResultsByQueryTokens({
    required List<FoodSearchResult> input,
    required List<String> queryTokens,
  }) {
    if (input.isEmpty || queryTokens.isEmpty) {
      return input;
    }

    final allTokens = <FoodSearchResult>[];
    final partialTokens = <FoodSearchResult>[];

    for (final item in input) {
      final haystack = _normalizeText(
          '${item.name} ${item.brand ?? ''} ${item.subtitle ?? ''}');
      if (haystack.isEmpty) continue;
      final matched = queryTokens.where((token) => haystack.contains(token));
      final matchCount = matched.length;
      if (matchCount == queryTokens.length) {
        allTokens.add(item);
      } else if (matchCount > 0) {
        partialTokens.add(item);
      }
    }

    if (allTokens.isNotEmpty) return allTokens;
    return partialTokens;
  }

  List<FoodSearchResult> _filterResultsByCategory({
    required List<FoodSearchResult> input,
    required FoodSearchCategory category,
  }) {
    switch (category) {
      case FoodSearchCategory.all:
        return input;
      case FoodSearchCategory.commonFoods:
        return input
            .where((item) => item.resultType == FoodResultType.generic)
            .toList(growable: false);
      case FoodSearchCategory.branded:
        return input
            .where((item) => item.resultType == FoodResultType.branded)
            .toList(growable: false);
      case FoodSearchCategory.custom:
        return input
            .where((item) => item.resultType == FoodResultType.custom)
            .toList(growable: false);
    }
  }

  List<FoodSearchResult> _prioritizeFoundationGenericResults({
    required List<FoodSearchResult> input,
    required FoodSearchCategory category,
    required String query,
  }) {
    if (input.isEmpty ||
        category == FoodSearchCategory.branded ||
        category == FoodSearchCategory.custom) {
      return input;
    }

    final normalizedQuery = _normalizeQuery(query);
    final queryTokens = _queryTokens(normalizedQuery);
    final genericIntent = !_isBrandIntentQuery(queryTokens);
    if (category == FoodSearchCategory.all && !genericIntent) return input;

    final foundation = <FoodSearchResult>[];
    final srLegacy = <FoodSearchResult>[];
    final usdaOtherGeneric = <FoodSearchResult>[];
    final others = <FoodSearchResult>[];
    for (final item in input) {
      if (_isFoundationGeneric(item)) {
        foundation.add(item);
      } else if (_isSrLegacyGeneric(item)) {
        srLegacy.add(item);
      } else if (_isUsdaGeneric(item)) {
        usdaOtherGeneric.add(item);
      } else {
        others.add(item);
      }
    }
    if (foundation.isEmpty && srLegacy.isEmpty && usdaOtherGeneric.isEmpty) {
      return input;
    }
    return [...foundation, ...srLegacy, ...usdaOtherGeneric, ...others];
  }

  bool _isFoundationGeneric(FoodSearchResult item) {
    if (item.source != FoodSource.usdaFdc ||
        item.resultType != FoodResultType.generic) {
      return false;
    }
    final dataType = (item.dataType ?? '').toLowerCase().trim();
    return dataType.contains('foundation');
  }

  bool _isSrLegacyGeneric(FoodSearchResult item) {
    if (!_isUsdaGeneric(item)) return false;
    final dataType = (item.dataType ?? '').toLowerCase().trim();
    return dataType.contains('sr legacy');
  }

  bool _isUsdaGeneric(FoodSearchResult item) {
    return item.source == FoodSource.usdaFdc &&
        item.resultType == FoodResultType.generic;
  }

  bool _isBrandIntentQuery(List<String> queryTokens) {
    if (queryTokens.isEmpty) return false;
    const brandHints = {
      'tyson',
      'fairlife',
      'quest',
      'kirkland',
      'chobani',
      'fage',
      'dannon',
      'oscar',
      'mayer',
      'trader',
      'joes',
      'costco',
      'walmart',
      'great',
      'value',
    };
    return queryTokens.any((token) => brandHints.contains(token));
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
}

class _UsdaCommonFoodProvider implements CommonFoodProvider {
  _UsdaCommonFoodProvider(this._provider);

  static const String providerNameValue = 'usda_common';
  final UsdaFdcProvider _provider;

  @override
  String get providerName => providerNameValue;

  @override
  bool get isEnabled => _provider.isEnabled;

  @override
  Future<List<FoodSearchResult>> searchCommonFoods({
    required String query,
    required int page,
    required int pageSize,
  }) {
    return _provider.searchFoods(
      query: query,
      page: page,
      pageSize: pageSize,
      filters:
          const FoodSearchFilters(category: FoodSearchCategory.commonFoods),
    );
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return _provider.fetchFoodDetailById(id);
  }
}

class _UsdaBrandedFoodProvider implements BrandedFoodProvider {
  _UsdaBrandedFoodProvider(this._provider);

  static const String providerNameValue = 'usda_branded';
  final UsdaFdcProvider _provider;

  @override
  String get providerName => providerNameValue;

  @override
  bool get isEnabled => _provider.isEnabled;

  @override
  Future<List<FoodSearchResult>> searchBrandedFoods({
    required String query,
    required int page,
    required int pageSize,
  }) {
    return _provider.searchFoods(
      query: query,
      page: page,
      pageSize: pageSize,
      filters: const FoodSearchFilters(category: FoodSearchCategory.branded),
    );
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return _provider.fetchFoodDetailById(id);
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) {
    return _provider.lookupByBarcode(barcode);
  }
}

class _NutritionixCommonFoodProvider implements CommonFoodProvider {
  _NutritionixCommonFoodProvider(this._provider);

  final NutritionixProvider _provider;

  @override
  String get providerName => 'nutritionix_common';

  @override
  bool get isEnabled => _provider.isEnabled;

  @override
  Future<List<FoodSearchResult>> searchCommonFoods({
    required String query,
    required int page,
    required int pageSize,
  }) {
    return _provider.searchFoods(
      query: query,
      page: page,
      pageSize: pageSize,
      filters:
          const FoodSearchFilters(category: FoodSearchCategory.commonFoods),
    );
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return _provider.fetchFoodDetailById(id);
  }
}

class _NutritionixBrandedFoodProvider implements BrandedFoodProvider {
  _NutritionixBrandedFoodProvider(this._provider);

  final NutritionixProvider _provider;

  @override
  String get providerName => 'nutritionix_branded';

  @override
  bool get isEnabled => _provider.isEnabled;

  @override
  Future<List<FoodSearchResult>> searchBrandedFoods({
    required String query,
    required int page,
    required int pageSize,
  }) {
    return _provider.searchFoods(
      query: query,
      page: page,
      pageSize: pageSize,
      filters: const FoodSearchFilters(category: FoodSearchCategory.branded),
    );
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return _provider.fetchFoodDetailById(id);
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) {
    return _provider.lookupByBarcode(barcode);
  }
}

class _CustomLocalFoodProvider implements LocalFoodProvider {
  _CustomLocalFoodProvider(this._provider);

  final CustomFoodProvider _provider;

  @override
  String get providerName => 'custom_local';

  @override
  Future<List<FoodSearchResult>> searchLocalFoods({
    required String query,
    required int page,
    required int pageSize,
  }) {
    return _provider.searchFoods(
      query: query,
      page: page,
      pageSize: pageSize,
      filters: const FoodSearchFilters(category: FoodSearchCategory.custom),
    );
  }

  @override
  Future<FoodItem?> fetchFoodDetailById(String id) {
    return _provider.fetchFoodDetailById(id);
  }

  @override
  Future<FoodItem?> lookupByBarcode(String barcode) {
    return _provider.lookupByBarcode(barcode);
  }
}
