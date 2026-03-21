import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../../../data/food/food_repository.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/food_models.dart';
import '../../widgets/diet/food_source_badge.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'food_barcode_scan_page.dart';
import 'food_detail_page.dart';
import 'food_search_controller.dart';

class FoodSearchPage extends StatefulWidget {
  const FoodSearchPage({
    super.key,
    required this.foodRepository,
    required this.dietRepo,
    this.initialMealSlot,
    this.selectedDay,
    this.selectionMode = false,
  });

  static Future<bool?> show(
    BuildContext context, {
    required FoodRepository foodRepository,
    required DietRepo dietRepo,
    String? initialMealSlot,
    DateTime? selectedDay,
  }) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => FoodSearchPage(
          foodRepository: foodRepository,
          dietRepo: dietRepo,
          initialMealSlot: initialMealSlot,
          selectedDay: selectedDay,
        ),
      ),
    );
  }

  static Future<FoodItem?> showForSelection(
    BuildContext context, {
    required FoodRepository foodRepository,
    required DietRepo dietRepo,
  }) {
    return Navigator.of(context).push<FoodItem>(
      MaterialPageRoute(
        builder: (_) => FoodSearchPage(
          foodRepository: foodRepository,
          dietRepo: dietRepo,
          selectionMode: true,
        ),
      ),
    );
  }

  final FoodRepository foodRepository;
  final DietRepo dietRepo;
  final String? initialMealSlot;
  final DateTime? selectedDay;
  final bool selectionMode;

  @override
  State<FoodSearchPage> createState() => _FoodSearchPageState();
}

class _FoodSearchPageState extends State<FoodSearchPage> {
  static const String _recentSearchFoodsKey = 'diet_recent_search_foods_v1';
  static const int _recentSearchFoodLimit = 15;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _resultsScrollController = ScrollController();
  final SettingsRepo _settingsRepo = SettingsRepo(AppDatabase.instance);

  late final FoodSearchController _searchState;

  List<_RecentSearchFoodItem> _recentSearchFoods = const [];

  @override
  void initState() {
    super.initState();
    _searchState = FoodSearchController(
      repository: widget.foodRepository,
      pageSize: 20,
    )..addListener(_onSearchStateChanged);

    _searchController.addListener(_onSearchTextChanged);
    _resultsScrollController.addListener(_onResultsScroll);
    unawaited(_loadRecentSearchFoods());
  }

  @override
  void dispose() {
    _searchController
      ..removeListener(_onSearchTextChanged)
      ..dispose();
    _resultsScrollController
      ..removeListener(_onResultsScroll)
      ..dispose();
    _searchState
      ..removeListener(_onSearchStateChanged)
      ..dispose();
    super.dispose();
  }

  void _onSearchStateChanged() {
    if (!mounted) return;

    final barcodeFood = _searchState.consumeResolvedBarcodeFood();
    if (barcodeFood != null) {
      unawaited(_openFoodFromLookup(barcodeFood));
    }

    setState(() {});
  }

  void _onSearchTextChanged() {
    _searchState.onQueryChanged(_searchController.text);
  }

  void _onResultsScroll() {
    if (!_resultsScrollController.hasClients) return;
    final position = _resultsScrollController.position;
    if (position.pixels >= position.maxScrollExtent - 260) {
      unawaited(_searchState.loadNextPage());
    }
  }

  Future<void> _loadRecentSearchFoods() async {
    final raw = await _settingsRepo.getValue(_recentSearchFoodsKey);
    if (!mounted) return;
    if (raw == null || raw.trim().isEmpty) {
      setState(() => _recentSearchFoods = const []);
      return;
    }

    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        setState(() => _recentSearchFoods = const []);
        return;
      }

      final parsed = <_RecentSearchFoodItem>[];
      for (final item in decoded) {
        if (item is! Map) continue;
        final map = Map<String, dynamic>.from(item);
        final foodJson = map['food'];
        if (foodJson is! Map) continue;
        final food = FoodItem.fromJson(Map<String, dynamic>.from(foodJson));
        final viewedAt = DateTime.tryParse(map['viewedAt']?.toString() ?? '') ??
            DateTime.now();
        parsed.add(
          _RecentSearchFoodItem(
            food: food,
            viewedAt: viewedAt,
          ),
        );
      }

      parsed.sort((a, b) => b.viewedAt.compareTo(a.viewedAt));
      setState(() {
        _recentSearchFoods = parsed.take(_recentSearchFoodLimit).toList();
      });
    } catch (_) {
      setState(() => _recentSearchFoods = const []);
    }
  }

  Future<void> _saveRecentSearchFood(FoodItem food) async {
    if (!mounted) return;
    final now = DateTime.now();
    final next = <_RecentSearchFoodItem>[
      _RecentSearchFoodItem(food: food, viewedAt: now),
      for (final item in _recentSearchFoods)
        if (!_isSameFood(item.food, food)) item,
    ].take(_recentSearchFoodLimit).toList(growable: false);

    setState(() {
      _recentSearchFoods = next;
    });

    final payload = [
      for (final item in next)
        {
          'food': item.food.toJson(),
          'viewedAt': item.viewedAt.toIso8601String(),
        },
    ];
    await _settingsRepo.setValue(_recentSearchFoodsKey, jsonEncode(payload));
  }

  bool _isSameFood(FoodItem a, FoodItem b) {
    return a.source == b.source && a.id == b.id;
  }

  Future<void> _openResult(FoodSearchResult result) async {
    final detail = await widget.foodRepository.fetchFoodDetail(result);
    if (!mounted) return;
    if (detail == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to load food details from this source.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    if (widget.selectionMode) {
      await _saveRecentSearchFood(detail);
      if (!mounted) return;
      Navigator.of(context).pop(detail);
      return;
    }

    await _saveRecentSearchFood(detail);
    if (!mounted) return;

    final added = await FoodDetailPage.show(
      context,
      food: detail,
      dietRepo: widget.dietRepo,
      initialMealSlot: widget.initialMealSlot,
      selectedDay: widget.selectedDay,
    );
    if (!mounted) return;
    if (added == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _scanBarcode() async {
    final barcode = await FoodBarcodeScanPage.show(context);
    if (!mounted || barcode == null || barcode.trim().isEmpty) return;

    final food = await widget.foodRepository.lookupBarcode(barcode.trim());
    if (!mounted) return;
    if (food == null) {
      await _showBarcodeNotFoundStub(barcode.trim());
      return;
    }

    if (widget.selectionMode) {
      if (!mounted) return;
      Navigator.of(context).pop(food);
      return;
    }

    final added = await FoodDetailPage.show(
      context,
      food: food,
      dietRepo: widget.dietRepo,
      initialMealSlot: widget.initialMealSlot,
      selectedDay: widget.selectedDay,
    );
    if (!mounted) return;
    if (added == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openFoodFromLookup(FoodItem food) async {
    if (!mounted) return;
    await _saveRecentSearchFood(food);
    if (!mounted) return;
    if (widget.selectionMode) {
      Navigator.of(context).pop(food);
      return;
    }
    final added = await FoodDetailPage.show(
      context,
      food: food,
      dietRepo: widget.dietRepo,
      initialMealSlot: widget.initialMealSlot,
      selectedDay: widget.selectedDay,
    );
    if (!mounted) return;
    if (added == true) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _openRecentFoodDetail(FoodItem food) async {
    if (!mounted) return;
    await _saveRecentSearchFood(food);
    if (!mounted) return;

    final added = await FoodDetailPage.show(
      context,
      food: food,
      dietRepo: widget.dietRepo,
      initialMealSlot: widget.initialMealSlot,
      selectedDay: widget.selectedDay,
    );
    if (!mounted) return;
    if (added == true && !widget.selectionMode) {
      Navigator.of(context).pop(true);
    }
  }

  Future<void> _showBarcodeNotFoundStub(String barcode) async {
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Food not found'),
          content: Text(
            'No product was found for barcode $barcode. '
            'Create Custom Food flow is available as a stub and can be expanded next.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Close'),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(
                  Navigator.of(this.context).push(
                    MaterialPageRoute(
                      builder: (_) => const _CustomFoodStubPage(),
                    ),
                  ),
                );
              },
              child: const Text('Create Custom Food'),
            ),
          ],
        );
      },
    );
  }

  double? _extractKcal(FoodSearchResult result) {
    final text = '${result.subtitle ?? ''} ${result.brand ?? ''}';
    final match = RegExp(
      r'(\d+(?:\.\d+)?)\s*(kcal|cal)',
      caseSensitive: false,
    ).firstMatch(text);
    if (match == null) return null;
    return double.tryParse(match.group(1)!);
  }

  Widget _buildSearchInput(BuildContext context) {
    final theme = Theme.of(context);
    return GlassCard(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        children: [
          TextField(
            controller: _searchController,
            autofocus: true,
            textInputAction: TextInputAction.search,
            onSubmitted: (_) async {
              FocusScope.of(context).unfocus();
            },
            decoration: InputDecoration(
              hintText: 'Search foods',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _searchController.text.trim().isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        _searchState.onQueryChanged('');
                      },
                      icon: const Icon(Icons.close),
                    ),
            ),
          ),
          const SizedBox(height: 10),
          SegmentedButton<FoodSearchCategory>(
            showSelectedIcon: false,
            multiSelectionEnabled: false,
            style: ButtonStyle(
              visualDensity: const VisualDensity(
                horizontal: -2,
                vertical: -2,
              ),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              padding: const WidgetStatePropertyAll(
                EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              ),
              backgroundColor: WidgetStateProperty.resolveWith((states) {
                if (states.contains(WidgetState.selected)) {
                  return theme.colorScheme.primary.withValues(alpha: 0.18);
                }
                return theme.colorScheme.surface.withValues(alpha: 0.12);
              }),
              side: WidgetStateProperty.resolveWith((states) {
                final opacity =
                    states.contains(WidgetState.selected) ? 0.34 : 0.18;
                return BorderSide(
                  color: theme.colorScheme.outline.withValues(alpha: opacity),
                );
              }),
            ),
            segments: const [
              ButtonSegment<FoodSearchCategory>(
                value: FoodSearchCategory.all,
                label: Text('All'),
              ),
              ButtonSegment<FoodSearchCategory>(
                value: FoodSearchCategory.commonFoods,
                label: Text('Generic'),
              ),
              ButtonSegment<FoodSearchCategory>(
                value: FoodSearchCategory.branded,
                label: Text('Branded'),
              ),
              ButtonSegment<FoodSearchCategory>(
                value: FoodSearchCategory.custom,
                label: Text('Custom'),
              ),
            ],
            selected: {_searchState.category},
            onSelectionChanged: (selection) {
              _searchState.setCategory(selection.first);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildResultsList(BuildContext context) {
    final theme = Theme.of(context);
    final results = _searchState.results;
    const loadingSkeletonCount = 3;
    final showRefreshSkeletons =
        _searchState.loading && results.isNotEmpty && !_searchState.loadingMore;
    return ListView.separated(
      controller: _resultsScrollController,
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 18),
      itemCount: results.length +
          (_searchState.loadingMore ? 1 : 0) +
          (showRefreshSkeletons ? loadingSkeletonCount : 0),
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        if (index >= results.length) {
          if (showRefreshSkeletons) {
            final skeletonStart = results.length;
            final skeletonEnd = skeletonStart + loadingSkeletonCount;
            if (index >= skeletonStart && index < skeletonEnd) {
              return GlassCard(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                radius: 14,
                child: Row(
                  children: const [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _SkeletonLine(width: 170, height: 13),
                          SizedBox(height: 6),
                          _SkeletonLine(width: 120, height: 10),
                        ],
                      ),
                    ),
                    SizedBox(width: 12),
                    _SkeletonLine(width: 44, height: 24),
                  ],
                ),
              );
            }
          }
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        }

        final result = results[index];
        final subtitleBits = <String>[
          if ((result.brand ?? '').trim().isNotEmpty) result.brand!.trim(),
          if ((result.subtitle ?? '').trim().isNotEmpty)
            result.subtitle!.trim(),
        ];
        final subtitle = subtitleBits.join(' • ');
        final kcal = _extractKcal(result);

        return InkWell(
          onTap: _searchState.loading ? null : () => _openResult(result),
          borderRadius: BorderRadius.circular(14),
          child: GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            radius: 14,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        result.name,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        subtitle.isEmpty ? result.source.label : subtitle,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FoodSourceBadge(resultType: result.resultType),
                    const SizedBox(height: 7),
                    Text(
                      kcal == null ? '--' : kcal.toStringAsFixed(0),
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Text(
                      'kcal',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color:
                            theme.colorScheme.onSurface.withValues(alpha: 0.62),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildNoQueryContent(BuildContext context) {
    final theme = Theme.of(context);
    final suggestions = const [
      'Chicken breast',
      'Egg',
      'Brown rice',
      'Greek yogurt',
      'Banana',
      'Salmon',
    ];

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
      children: [
        Text(
          'Recent Foods',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        if (_recentSearchFoods.isEmpty)
          GlassCard(
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            radius: 14,
            child: Text(
              'Your recently opened food details will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
          )
        else
          ..._recentSearchFoods.map(
            (item) => Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => _openRecentFoodDetail(item.food),
                child: GlassCard(
                  padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
                  radius: 14,
                  child: Row(
                    children: [
                      const Icon(Icons.history, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              item.food.name,
                              style: theme.textTheme.titleSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              item.food.brand?.trim().isNotEmpty == true
                                  ? item.food.brand!.trim()
                                  : item.food.source.label,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurface
                                    .withValues(alpha: 0.68),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      FoodSourceBadge(
                        resultType: _resultTypeForFood(item.food),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        const SizedBox(height: 8),
        Text(
          'Favorites',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
          radius: 14,
          child: Row(
            children: [
              Icon(
                Icons.star_border,
                size: 16,
                color: theme.colorScheme.onSurface.withValues(alpha: 0.62),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Favorites will appear here once you pin foods.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Suggestions',
          style:
              theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final suggestion in suggestions)
              ActionChip(
                label: Text(suggestion),
                onPressed: () {
                  _searchController.text = suggestion;
                  _searchController.selection = TextSelection.collapsed(
                    offset: suggestion.length,
                  );
                  _searchState.onQueryChanged(suggestion);
                },
              ),
          ],
        ),
      ],
    );
  }

  FoodResultType _resultTypeForFood(FoodItem food) {
    if (food.source == FoodSource.custom) {
      return FoodResultType.custom;
    }
    final dataSource = food.sourceDescription?.toLowerCase() ?? '';
    final isBranded = dataSource.contains('branded') ||
        (food.brand?.trim().isNotEmpty == true && food.barcode != null);
    return isBranded ? FoodResultType.branded : FoodResultType.generic;
  }

  Widget _buildLoadingState() {
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      itemCount: 8,
      separatorBuilder: (_, __) => const SizedBox(height: 7),
      itemBuilder: (context, index) {
        return GlassCard(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          radius: 14,
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _SkeletonLine(width: 170, height: 13),
                    const SizedBox(height: 6),
                    _SkeletonLine(width: 120, height: 10),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              const _SkeletonLine(width: 44, height: 24),
            ],
          ),
        );
      },
    );
  }

  Widget _buildErrorState(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.wifi_off_rounded, size: 26),
            const SizedBox(height: 8),
            Text(
              _searchState.error ?? 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 10),
            ElevatedButton(
              onPressed: _searchState.retry,
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNoResultsState(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 26),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 30,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.64),
            ),
            const SizedBox(height: 8),
            Text(
              'No foods found for this search.',
              style: theme.textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Try a different keyword or create a custom food entry.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () {
                unawaited(
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const _CustomFoodStubPage(),
                    ),
                  ),
                );
              },
              child: const Text('Create Custom Food'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasQuery = _searchState.canSearch;
    final hasResults = _searchState.results.isNotEmpty;

    Widget content;
    if (!hasQuery) {
      content = _buildNoQueryContent(context);
    } else if (_searchState.loading && !hasResults) {
      content = _buildLoadingState();
    } else if (_searchState.error != null && !hasResults) {
      content = _buildErrorState(context);
    } else if (!hasResults) {
      content = _buildNoResultsState(context);
    } else {
      content = _buildResultsList(context);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.selectionMode ? 'Select Food' : 'Add Food'),
        actions: [
          IconButton(
            onPressed: _scanBarcode,
            tooltip: 'Scan Barcode',
            icon: const Icon(Icons.qr_code_scanner),
          ),
        ],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                child: _buildSearchInput(context),
              ),
              Expanded(child: content),
            ],
          ),
          if (_searchState.loading && hasResults)
            const Positioned(
              right: 20,
              top: 20,
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
        ],
      ),
    );
  }
}

class _RecentSearchFoodItem {
  const _RecentSearchFoodItem({
    required this.food,
    required this.viewedAt,
  });

  final FoodItem food;
  final DateTime viewedAt;
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({
    required this.width,
    required this.height,
  });

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(999),
        color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14),
      ),
    );
  }
}

class _CustomFoodStubPage extends StatelessWidget {
  const _CustomFoodStubPage();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Create Custom Food')),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text(
            'Custom food creation is stubbed here.\n\n'
            'Next step: add full custom food editor and save to CUSTOM source.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    );
  }
}
