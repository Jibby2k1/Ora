import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../domain/models/diet_goal_settings.dart';
import '../../../domain/services/diet_goal_settings_service.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class DietGoalsSettingsPage extends StatefulWidget {
  const DietGoalsSettingsPage({super.key});

  static Future<bool?> show(BuildContext context) {
    return Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const DietGoalsSettingsPage(),
      ),
    );
  }

  @override
  State<DietGoalsSettingsPage> createState() => _DietGoalsSettingsPageState();
}

class _DietGoalsSettingsPageState extends State<DietGoalsSettingsPage>
    with SingleTickerProviderStateMixin {
  static const double _percentTolerance = 0.1;

  late final DietGoalSettingsService _goalsService;
  late final TabController _tabController;

  final TextEditingController _manualProteinController =
      TextEditingController();
  final TextEditingController _manualCarbsController = TextEditingController();
  final TextEditingController _manualFatController = TextEditingController();

  final TextEditingController _percentCaloriesController =
      TextEditingController();
  final TextEditingController _percentProteinController =
      TextEditingController();
  final TextEditingController _percentCarbsController = TextEditingController();
  final TextEditingController _percentFatController = TextEditingController();

  final TextEditingController _optimalCaloriesController =
      TextEditingController();

  bool _loading = true;
  bool _saving = false;
  DietOptimalGoalType _optimalGoalType = DietOptimalGoalType.maintaining;

  @override
  void initState() {
    super.initState();
    _goalsService = DietGoalSettingsService(AppDatabase.instance);
    _tabController = TabController(length: 3, vsync: this);
    _tabController.addListener(_onTabChanged);

    for (final controller in _controllers) {
      controller.addListener(_onFieldChanged);
    }

    _load();
  }

  @override
  void dispose() {
    _tabController
      ..removeListener(_onTabChanged)
      ..dispose();

    for (final controller in _controllers) {
      controller
        ..removeListener(_onFieldChanged)
        ..dispose();
    }
    super.dispose();
  }

  List<TextEditingController> get _controllers => [
        _manualProteinController,
        _manualCarbsController,
        _manualFatController,
        _percentCaloriesController,
        _percentProteinController,
        _percentCarbsController,
        _percentFatController,
        _optimalCaloriesController,
      ];

  Future<void> _load() async {
    final settings = await _goalsService.load();
    if (!mounted) return;

    _manualProteinController.text = _format(settings.manualProteinG);
    _manualCarbsController.text = _format(settings.manualCarbsG);
    _manualFatController.text = _format(settings.manualFatG);

    _percentCaloriesController.text = _format(settings.percentageCalories);
    _percentProteinController.text = _format(settings.percentageProtein);
    _percentCarbsController.text = _format(settings.percentageCarbs);
    _percentFatController.text = _format(settings.percentageFat);

    _optimalCaloriesController.text = _format(settings.optimalCalories);
    _optimalGoalType = settings.optimalGoalType;
    _tabController.index = _modeToTabIndex(settings.mode);

    setState(() {
      _loading = false;
    });
  }

  void _onFieldChanged() {
    if (!_loading && mounted) {
      setState(() {});
    }
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging && mounted) {
      setState(() {});
    }
  }

  int _modeToTabIndex(DietGoalMode mode) {
    switch (mode) {
      case DietGoalMode.manualMacros:
        return 0;
      case DietGoalMode.macroPercentages:
        return 1;
      case DietGoalMode.optimalRatio:
        return 2;
    }
  }

  DietGoalMode get _activeMode {
    switch (_tabController.index) {
      case 0:
        return DietGoalMode.manualMacros;
      case 1:
        return DietGoalMode.macroPercentages;
      case 2:
      default:
        return DietGoalMode.optimalRatio;
    }
  }

  double? _readNumber(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.tryParse(text);
  }

  double _safe(double? value) => value ?? 0;

  bool get _manualValid {
    final protein = _readNumber(_manualProteinController);
    final carbs = _readNumber(_manualCarbsController);
    final fat = _readNumber(_manualFatController);
    if (protein == null || carbs == null || fat == null) return false;
    if (protein < 0 || carbs < 0 || fat < 0) return false;
    return (protein + carbs + fat) > 0;
  }

  double get _manualCaloriesEstimate {
    return (_safe(_readNumber(_manualProteinController)) * 4) +
        (_safe(_readNumber(_manualCarbsController)) * 4) +
        (_safe(_readNumber(_manualFatController)) * 9);
  }

  bool get _percentValid {
    final calories = _readNumber(_percentCaloriesController);
    final protein = _readNumber(_percentProteinController);
    final carbs = _readNumber(_percentCarbsController);
    final fat = _readNumber(_percentFatController);
    if (calories == null || protein == null || carbs == null || fat == null) {
      return false;
    }
    if (calories <= 0 || protein < 0 || carbs < 0 || fat < 0) return false;
    final total = protein + carbs + fat;
    return (total - 100).abs() <= _percentTolerance;
  }

  double get _percentTotal {
    return _safe(_readNumber(_percentProteinController)) +
        _safe(_readNumber(_percentCarbsController)) +
        _safe(_readNumber(_percentFatController));
  }

  DietGoalTargets get _percentageTargets {
    final calories = _safe(_readNumber(_percentCaloriesController));
    final proteinPercent = _safe(_readNumber(_percentProteinController));
    final carbsPercent = _safe(_readNumber(_percentCarbsController));
    final fatPercent = _safe(_readNumber(_percentFatController));
    return DietGoalTargets(
      calories: calories,
      proteinG: (calories * (proteinPercent / 100)) / 4,
      carbsG: (calories * (carbsPercent / 100)) / 4,
      fatG: (calories * (fatPercent / 100)) / 9,
    );
  }

  bool get _optimalValid {
    final calories = _readNumber(_optimalCaloriesController);
    if (calories == null) return false;
    return calories > 0;
  }

  DietGoalTargets get _optimalTargets {
    final calories = _safe(_readNumber(_optimalCaloriesController));
    final ratio = DietMacroRatio.presetFor(_optimalGoalType);
    return DietGoalTargets(
      calories: calories,
      proteinG: (calories * (ratio.proteinPercent / 100)) / 4,
      carbsG: (calories * (ratio.carbPercent / 100)) / 4,
      fatG: (calories * (ratio.fatPercent / 100)) / 9,
    );
  }

  bool get _isSaveEnabled {
    switch (_activeMode) {
      case DietGoalMode.manualMacros:
        return _manualValid && _manualCaloriesEstimate > 0;
      case DietGoalMode.macroPercentages:
        return _percentValid;
      case DietGoalMode.optimalRatio:
        return _optimalValid;
    }
  }

  Future<void> _save() async {
    if (!_isSaveEnabled || _saving) return;
    setState(() {
      _saving = true;
    });

    final settings = DietGoalSettings(
      mode: _activeMode,
      manualProteinG: _safe(_readNumber(_manualProteinController)),
      manualCarbsG: _safe(_readNumber(_manualCarbsController)),
      manualFatG: _safe(_readNumber(_manualFatController)),
      percentageCalories: _safe(_readNumber(_percentCaloriesController)),
      percentageProtein: _safe(_readNumber(_percentProteinController)),
      percentageCarbs: _safe(_readNumber(_percentCarbsController)),
      percentageFat: _safe(_readNumber(_percentFatController)),
      optimalCalories: _safe(_readNumber(_optimalCaloriesController)),
      optimalGoalType: _optimalGoalType,
    );

    await _goalsService.save(settings);
    if (!mounted) return;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(
          content: Text('Diet goals saved.'),
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 3),
        ),
      );

    Navigator.of(context).pop(true);
  }

  String _format(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  String _formatMaybe(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(1);
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required String suffix,
  }) {
    return TextField(
      controller: controller,
      keyboardType: const TextInputType.numberWithOptions(decimal: true),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        isDense: true,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      ),
    );
  }

  Widget _buildSummaryTile({
    required String label,
    required String value,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.78),
              ),
            ),
          ),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildManualTab() {
    final protein = _safe(_readNumber(_manualProteinController));
    final carbs = _safe(_readNumber(_manualCarbsController));
    final fat = _safe(_readNumber(_manualFatController));
    final calories = _manualCaloriesEstimate;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Manual Macros',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Enter protein, carbs, and fat grams. Calories are auto-calculated.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _manualProteinController,
                label: 'Protein Goal',
                suffix: 'g',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _manualCarbsController,
                label: 'Carb Goal',
                suffix: 'g',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _manualFatController,
                label: 'Fat Goal',
                suffix: 'g',
              ),
              if (!_manualValid) ...[
                const SizedBox(height: 10),
                Text(
                  'Use non-negative values and make sure total macros are greater than 0.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Summary',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _buildSummaryTile(
                label: 'Protein',
                value: '${_formatMaybe(protein)} g',
              ),
              _buildSummaryTile(
                label: 'Carbs',
                value: '${_formatMaybe(carbs)} g',
              ),
              _buildSummaryTile(
                label: 'Fat',
                value: '${_formatMaybe(fat)} g',
              ),
              _buildSummaryTile(
                label: 'Estimated Calories',
                value: '${_formatMaybe(calories)} kcal',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPercentagesTab() {
    final total = _percentTotal;
    final remaining = 100 - total;
    final targets = _percentageTargets;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Macro Percentages',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Set calorie target and percentage split. Percentages must total 100%.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _percentCaloriesController,
                label: 'Calorie Goal',
                suffix: 'kcal',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _percentProteinController,
                label: 'Protein',
                suffix: '%',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _percentCarbsController,
                label: 'Carbs',
                suffix: '%',
              ),
              const SizedBox(height: 8),
              _buildTextField(
                controller: _percentFatController,
                label: 'Fat',
                suffix: '%',
              ),
              const SizedBox(height: 10),
              Text(
                _percentValid
                    ? '100% balanced'
                    : 'Remaining: ${_formatMaybe(remaining)}%',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: _percentValid
                      ? theme.colorScheme.primary
                      : theme.colorScheme.error,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (!_percentValid) ...[
                const SizedBox(height: 6),
                Text(
                  'Percentages must equal 100% and calories must be greater than 0.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Calculated Targets',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _buildSummaryTile(
                label: 'Calories',
                value: '${_formatMaybe(targets.calories)} kcal',
              ),
              _buildSummaryTile(
                label: 'Protein',
                value: '${_formatMaybe(targets.proteinG)} g',
              ),
              _buildSummaryTile(
                label: 'Carbs',
                value: '${_formatMaybe(targets.carbsG)} g',
              ),
              _buildSummaryTile(
                label: 'Fat',
                value: '${_formatMaybe(targets.fatG)} g',
              ),
              _buildSummaryTile(
                label: 'Total Percent',
                value: '${_formatMaybe(total)}%',
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOptimalRatioTab() {
    final ratio = DietMacroRatio.presetFor(_optimalGoalType);
    final targets = _optimalTargets;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Optimal Ratio',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose a goal type and calorie target. Macro split is set automatically.',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
                ),
              ),
              const SizedBox(height: 12),
              _buildTextField(
                controller: _optimalCaloriesController,
                label: 'Calorie Goal',
                suffix: 'kcal',
              ),
              const SizedBox(height: 10),
              DropdownButtonFormField<DietOptimalGoalType>(
                key: ValueKey(_optimalGoalType),
                initialValue: _optimalGoalType,
                decoration: const InputDecoration(
                  labelText: 'Goal Type',
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                items: [
                  for (final type in DietOptimalGoalType.values)
                    DropdownMenuItem(
                      value: type,
                      child: Text(type.label),
                    ),
                ],
                onChanged: (value) {
                  if (value == null) return;
                  setState(() {
                    _optimalGoalType = value;
                  });
                },
              ),
              if (!_optimalValid) ...[
                const SizedBox(height: 10),
                Text(
                  'Calories must be greater than 0.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        GlassCard(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Preset Breakdown',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              _buildSummaryTile(
                label: 'Protein Ratio',
                value: '${_formatMaybe(ratio.proteinPercent)}%',
              ),
              _buildSummaryTile(
                label: 'Carbs Ratio',
                value: '${_formatMaybe(ratio.carbPercent)}%',
              ),
              _buildSummaryTile(
                label: 'Fat Ratio',
                value: '${_formatMaybe(ratio.fatPercent)}%',
              ),
              const SizedBox(height: 6),
              _buildSummaryTile(
                label: 'Protein',
                value: '${_formatMaybe(targets.proteinG)} g',
              ),
              _buildSummaryTile(
                label: 'Carbs',
                value: '${_formatMaybe(targets.carbsG)} g',
              ),
              _buildSummaryTile(
                label: 'Fat',
                value: '${_formatMaybe(targets.fatG)} g',
              ),
              _buildSummaryTile(
                label: 'Calories',
                value: '${_formatMaybe(targets.calories)} kcal',
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Diet Settings'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
                  child: GlassCard(
                    padding: const EdgeInsets.all(6),
                    radius: 14,
                    child: TabBar(
                      controller: _tabController,
                      isScrollable: true,
                      indicatorSize: TabBarIndicatorSize.tab,
                      dividerColor: Colors.transparent,
                      indicator: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        color: theme.colorScheme.primary.withValues(alpha: 0.2),
                        border: Border.all(
                          color:
                              theme.colorScheme.outline.withValues(alpha: 0.3),
                        ),
                      ),
                      labelStyle: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      unselectedLabelStyle:
                          theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      labelColor: theme.colorScheme.onSurface,
                      unselectedLabelColor:
                          theme.colorScheme.onSurface.withValues(alpha: 0.74),
                      tabs: const [
                        Tab(text: 'Manual Macros'),
                        Tab(text: 'Macro Percentages'),
                        Tab(text: 'Optimal Ratio'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabController,
                    children: [
                      _buildManualTab(),
                      _buildPercentagesTab(),
                      _buildOptimalRatioTab(),
                    ],
                  ),
                ),
              ],
            ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: GlassCard(
          radius: 16,
          padding: const EdgeInsets.all(10),
          child: SizedBox(
            height: 48,
            child: ElevatedButton(
              onPressed: _isSaveEnabled && !_saving ? _save : null,
              child: Text(_saving ? 'Saving...' : 'Save Goals'),
            ),
          ),
        ),
      ),
    );
  }
}
