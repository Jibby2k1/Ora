import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../../data/food/food_repository.dart';
import '../../../data/food/search_ranker.dart';
import '../../../diagnostics/diagnostics_log.dart';
import '../../../domain/models/food_models.dart';

class FoodSearchController extends ChangeNotifier {
  FoodSearchController({
    required FoodRepository repository,
    this.debounceDuration = const Duration(milliseconds: 350),
    this.requestTimeout = const Duration(seconds: 12),
    this.pageSize = 20,
  }) : _repository = repository;

  final FoodRepository _repository;
  final Duration debounceDuration;
  final Duration requestTimeout;
  final int pageSize;

  static const int _cacheLimit = 100;
  static const int _cacheVersion = 2;

  final LinkedHashMap<String, _SearchCacheEntry> _searchCache =
      LinkedHashMap<String, _SearchCacheEntry>();
  Timer? _debounceTimer;
  final FoodSearchRanker _ranker = const FoodSearchRanker();

  FoodSearchCategory _category = FoodSearchCategory.all;
  String _query = '';
  List<FoodSearchResult> _results = const [];
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _currentPage = 0;
  String? _error;
  int _activeSearchId = 0;
  FoodItem? _resolvedBarcodeFood;

  FoodSearchCategory get category => _category;
  String get query => _query;
  List<FoodSearchResult> get results => _results;
  bool get loading => _loading;
  bool get loadingMore => _loadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;

  bool get canSearch => _query.length >= 2;

  FoodItem? consumeResolvedBarcodeFood() {
    final food = _resolvedBarcodeFood;
    _resolvedBarcodeFood = null;
    return food;
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void setCategory(FoodSearchCategory value) {
    if (_category == value) return;
    _category = value;
    _error = null;
    _cancelActiveSearch();
    notifyListeners();

    _currentPage = 0;
    _hasMore = false;
    if (canSearch) {
      _scheduleSearch(reset: true);
    }
  }

  void onQueryChanged(String rawInput) {
    final normalized = _normalizeQuery(rawInput);
    if (_query == normalized) return;

    _query = normalized;
    _error = null;
    _resolvedBarcodeFood = null;
    _currentPage = 0;
    _hasMore = false;
    _debounceTimer?.cancel();
    _cancelActiveSearch();

    if (!canSearch) {
      _results = const [];
      notifyListeners();
      return;
    }

    notifyListeners();
    _scheduleSearch(reset: true);
  }

  Future<void> retry() async {
    if (!canSearch) return;
    await _runSearch(reset: true);
  }

  Future<void> loadNextPage() async {
    if (!canSearch || !hasMore || loading || loadingMore) return;
    await _runSearch(reset: false);
  }

  void _scheduleSearch({required bool reset}) {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(
      debounceDuration,
      () => unawaited(_runSearch(reset: reset)),
    );
  }

  Future<void> _runSearch({required bool reset}) async {
    if (!canSearch) return;

    final requestQuery = _query;
    final page = reset ? 1 : (_currentPage + 1);

    if (reset) {
      _loading = true;
      _loadingMore = false;
      _error = null;
    } else {
      _loading = false;
      _loadingMore = true;
      _error = null;
    }
    notifyListeners();

    final requestId = ++_activeSearchId;
    try {
      if (_isBarcodeQuery(requestQuery) &&
          _category != FoodSearchCategory.custom) {
        final barcodeFood = await _repository
            .lookupBarcode(requestQuery)
            .timeout(requestTimeout);
        if (requestId != _activeSearchId) {
          return;
        }

        _resolvedBarcodeFood = barcodeFood;
        _results = const [];
        _currentPage = barcodeFood == null ? 0 : 1;
        _hasMore = false;
        _error =
            barcodeFood == null ? 'No result found for that barcode.' : null;
        return;
      }

      final cacheKey = _cacheKey(
        query: requestQuery,
        category: _category,
        page: page,
      );
      final cached = _searchCache[cacheKey];
      if (cached != null) {
        if (requestId != _activeSearchId) {
          return;
        }
        _touchCache(cacheKey, cached);
        _results = reset
            ? cached.results
            : _mergeSearchResults(_results, cached.results);
        _currentPage = page;
        _hasMore = cached.hasMore;
        _error = null;
        return;
      }

      final fetched = await _repository
          .searchFoods(
            query: requestQuery,
            page: page,
            pageSize: pageSize,
            filters: FoodSearchFilters(category: _category),
          )
          .timeout(requestTimeout);

      if (requestId != _activeSearchId) {
        return;
      }

      final merged = reset ? fetched : _mergeSearchResults(_results, fetched);
      final hasMore = fetched.length >= pageSize;
      _results = merged;
      _currentPage = page;
      _hasMore = hasMore;
      _error = null;

      if (fetched.isNotEmpty) {
        _storeCache(
          cacheKey,
          _SearchCacheEntry(
            results: List<FoodSearchResult>.unmodifiable(merged),
            hasMore: hasMore,
          ),
        );
      }
    } on TimeoutException {
      if (requestId != _activeSearchId) return;
      _error = _results.isEmpty
          ? 'Search is taking too long. Try a shorter query.'
          : null;
    } catch (error, stackTrace) {
      if (requestId != _activeSearchId) return;
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'FoodSearchController._runSearch',
      );
      _error = _results.isEmpty
          ? 'Could not load foods right now. Please try again.'
          : null;
    } finally {
      if (requestId == _activeSearchId) {
        _loading = false;
        _loadingMore = false;
        notifyListeners();
      }
    }
  }

  void _cancelActiveSearch() {
    _activeSearchId++;
    _loading = false;
    _loadingMore = false;
  }

  void _touchCache(String key, _SearchCacheEntry value) {
    _searchCache.remove(key);
    _searchCache[key] = value;
  }

  void _storeCache(String key, _SearchCacheEntry value) {
    _searchCache.remove(key);
    _searchCache[key] = value;
    while (_searchCache.length > _cacheLimit) {
      _searchCache.remove(_searchCache.keys.first);
    }
  }

  String _normalizeQuery(String value) {
    return _ranker.normalizeQuery(value);
  }

  String _cacheKey({
    required String query,
    required FoodSearchCategory category,
    required int page,
  }) {
    return 'v$_cacheVersion|${category.name}|$query|$page';
  }

  List<FoodSearchResult> _mergeSearchResults(
    List<FoodSearchResult> existing,
    List<FoodSearchResult> incoming,
  ) {
    final output = List<FoodSearchResult>.from(existing);
    final seen = <String>{
      for (final item in existing)
        '${item.source.name}:${item.id}:${item.name.toLowerCase()}',
    };

    for (final item in incoming) {
      final key = '${item.source.name}:${item.id}:${item.name.toLowerCase()}';
      if (seen.add(key)) {
        output.add(item);
      }
    }

    return output;
  }

  bool _isBarcodeQuery(String query) {
    if (query.length < 8 || query.length > 14) return false;
    return RegExp(r'^\d+$').hasMatch(query);
  }
}

class _SearchCacheEntry {
  const _SearchCacheEntry({
    required this.results,
    required this.hasMore,
  });

  final List<FoodSearchResult> results;
  final bool hasMore;
}
