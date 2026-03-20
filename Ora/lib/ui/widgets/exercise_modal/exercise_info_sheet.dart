import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import '../../../diagnostics/diagnostics_log.dart';
import '../../../domain/models/exercise_science_info.dart';
import '../glass/glass_card.dart';

class ExerciseInfoSheet extends StatefulWidget {
  const ExerciseInfoSheet({
    super.key,
    required this.exerciseId,
    required this.exerciseName,
  });

  final int exerciseId;
  final String exerciseName;

  static Future<void> show(
    BuildContext context, {
    required int exerciseId,
    required String exerciseName,
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ExerciseInfoSheet(
        exerciseId: exerciseId,
        exerciseName: exerciseName,
      ),
    );
  }

  @override
  State<ExerciseInfoSheet> createState() => _ExerciseInfoSheetState();
}

class _ExerciseInfoSheetState extends State<ExerciseInfoSheet> {
  late final ExerciseRepo _repo;
  ExerciseScienceInfo? _info;
  bool _loading = true;
  String? _selectedTabKey;
  String? _loadErrorReport;

  @override
  void initState() {
    super.initState();
    _repo = ExerciseRepo(AppDatabase.instance);
    _loadInfo();
  }

  Future<void> _loadInfo() async {
    try {
      final info = await _repo.getExerciseScienceInfo(widget.exerciseId);
      if (!mounted) return;
      setState(() {
        _info = info;
        _loading = false;
        _loadErrorReport = null;
        _selectedTabKey = info == null ? null : _initialTabKey(info);
      });
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'Exercise information load failed',
        details:
            'exerciseId=${widget.exerciseId}\nexerciseName=${widget.exerciseName}',
      );
      if (!mounted) return;
      setState(() {
        _loading = false;
        _info = null;
        _loadErrorReport = DiagnosticsLog.instance.buildErrorReport(
          error,
          stackTrace,
          context: 'Exercise information load failed',
          details:
              'exerciseId=${widget.exerciseId}\nexerciseName=${widget.exerciseName}',
        );
      });
    }
  }

  String? _initialTabKey(ExerciseScienceInfo info) {
    final tabs = _buildTabs(info);
    if (tabs.isEmpty) {
      return null;
    }
    return tabs.first.key;
  }

  Future<void> _copyText(String text, String confirmation) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(confirmation),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scrollController) {
        return ClipRRect(
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
            child: Container(
              color: theme.colorScheme.surface.withValues(alpha: 0.85),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(theme),
                  Expanded(
                    child: _loading
                        ? const Center(child: CircularProgressIndicator())
                        : _info == null
                            ? _buildEmptyState(theme)
                            : _buildContent(theme, scrollController),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 16, 16, 16),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.1),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.exerciseName} Information',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Technique, safety, effectiveness, and source documents.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.68),
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme) {
    final hasError = _loadErrorReport != null;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              hasError ? Icons.error_outline_rounded : Icons.science_outlined,
              size: 48,
              color: hasError
                  ? theme.colorScheme.error
                  : theme.colorScheme.onSurface.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            Text(
              hasError
                  ? 'Unable to load exercise information.'
                  : 'No exercise information available for this exercise yet.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurface.withValues(alpha: 0.72),
              ),
            ),
            if (hasError) ...[
              const SizedBox(height: 12),
              Text(
                'The failure was written to diagnostics. You can also copy the full report directly from here.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () => _copyText(
                  _loadErrorReport!,
                  'Exercise information error copied to clipboard.',
                ),
                icon: const Icon(Icons.copy_all_rounded),
                label: const Text('Copy Error Report'),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildContent(ThemeData theme, ScrollController controller) {
    final info = _info!;
    final tabs = _buildTabs(info);
    if (tabs.isEmpty) {
      return _buildEmptyState(theme);
    }
    final selectedKey = tabs.any((tab) => tab.key == _selectedTabKey)
        ? _selectedTabKey!
        : tabs.first.key;
    final selectedTab = tabs.firstWhere((tab) => tab.key == selectedKey);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildTabStrip(theme, tabs, selectedKey),
        Expanded(
          child: ListView(
            controller: controller,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 48),
            children: _buildTabChildren(theme, info, selectedTab),
          ),
        ),
      ],
    );
  }

  List<_ExerciseInfoTab> _buildTabs(ExerciseScienceInfo info) {
    final tabs = <_ExerciseInfoTab>[];
    final seenKeys = <String>{};

    void addTab(_ExerciseInfoTab tab) {
      if (seenKeys.add(tab.key)) {
        tabs.add(tab);
      }
    }

    final techniqueSection = info.sectionForKey('technique');
    if (info.instructions.isNotEmpty ||
        info.visualAssetPaths.isNotEmpty ||
        techniqueSection != null) {
      addTab(
        _ExerciseInfoTab(
          key: 'technique',
          label: 'Technique',
          icon: Icons.play_circle_outline,
          section: techniqueSection,
        ),
      );
    }

    final safetySection = info.sectionForKey('safety');
    if (info.avoid.isNotEmpty || safetySection != null) {
      addTab(
        _ExerciseInfoTab(
          key: 'safety',
          label: 'Safety',
          icon: Icons.health_and_safety_outlined,
          section: safetySection,
        ),
      );
    }

    final effectivenessSection = info.sectionForKey('effectiveness');
    if (effectivenessSection != null) {
      addTab(
        _ExerciseInfoTab(
          key: 'effectiveness',
          label: 'Effectiveness',
          icon: Icons.trending_up_rounded,
          section: effectivenessSection,
        ),
      );
    }

    for (final section in info.orderedSections) {
      if (section.normalizedId == 'technique' ||
          section.normalizedId == 'safety' ||
          section.normalizedId == 'effectiveness') {
        continue;
      }
      addTab(
        _ExerciseInfoTab(
          key: section.normalizedId,
          label: section.title,
          icon: _iconForSection(section.normalizedId),
          section: section,
        ),
      );
    }

    if (info.resolvedSourceDocuments.isNotEmpty) {
      addTab(
        const _ExerciseInfoTab(
          key: 'sources',
          label: 'Sources',
          icon: Icons.menu_book_outlined,
        ),
      );
    }

    return tabs;
  }

  List<Widget> _buildTabChildren(
    ThemeData theme,
    ExerciseScienceInfo info,
    _ExerciseInfoTab tab,
  ) {
    switch (tab.key) {
      case 'technique':
        return _buildTechniqueChildren(theme, info, tab.section);
      case 'safety':
        return _buildSafetyChildren(theme, info, tab.section);
      case 'effectiveness':
        return _buildSectionChildren(theme, info, tab.section);
      case 'sources':
        return _buildSourcesChildren(theme, info);
      default:
        return _buildSectionChildren(theme, info, tab.section);
    }
  }

  List<Widget> _buildTechniqueChildren(
    ThemeData theme,
    ExerciseScienceInfo info,
    ExerciseScienceSection? section,
  ) {
    final widgets = <Widget>[];
    if (info.visualAssetPaths.isNotEmpty) {
      widgets.add(
        _buildSectionTitle(
          theme,
          'Visual Reference',
          Icons.image_outlined,
        ),
      );
      widgets.add(const SizedBox(height: 12));
      widgets.add(_buildVisuals(theme, info.visualAssetPaths));
      widgets.add(const SizedBox(height: 24));
    }

    if (section != null) {
      widgets.addAll(
        _buildStructuredSectionWidgets(
          theme,
          info,
          section,
          icon: Icons.play_circle_outline,
          accentColor: theme.colorScheme.primary,
          titleOverride: 'Technique Notes',
        ),
      );
    }

    if (info.instructions.isNotEmpty) {
      widgets.add(
        _buildNumberedListCard(
          theme,
          title: 'How to Perform It',
          icon: Icons.play_circle_outline,
          items: info.instructions,
        ),
      );
      widgets.add(const SizedBox(height: 24));
    }

    if (widgets.isEmpty) {
      widgets.add(
        _buildEmptyTabCard(
          theme,
          title: 'Technique not available',
          message:
              'This exercise does not yet have a structured technique extraction.',
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildSafetyChildren(
    ThemeData theme,
    ExerciseScienceInfo info,
    ExerciseScienceSection? section,
  ) {
    final widgets = <Widget>[];

    if (section != null) {
      widgets.addAll(
        _buildStructuredSectionWidgets(
          theme,
          info,
          section,
          icon: Icons.health_and_safety_outlined,
          accentColor: Colors.orange,
        ),
      );
    }

    if (info.avoid.isNotEmpty) {
      widgets.add(
        _buildAvoidCard(
          theme,
          title: 'Common Mistakes To Avoid',
          items: info.avoid,
        ),
      );
      widgets.add(const SizedBox(height: 24));
    }

    if (widgets.isEmpty) {
      widgets.add(
        _buildEmptyTabCard(
          theme,
          title: 'No safety extraction yet',
          message:
              'Add structured safety notes or “avoid” bullets in the exercise science seed to populate this tab.',
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildSectionChildren(
    ThemeData theme,
    ExerciseScienceInfo info,
    ExerciseScienceSection? section,
  ) {
    if (section == null) {
      return [
        _buildEmptyTabCard(
          theme,
          title: 'No structured section yet',
          message:
              'This tab is reserved for structured exercise information, but the current seed does not include it yet.',
        ),
      ];
    }

    final widgets = _buildStructuredSectionWidgets(
      theme,
      info,
      section,
      icon: _iconForSection(section.normalizedId),
      accentColor: _accentColorForSection(section.normalizedId),
    );
    if (widgets.isEmpty) {
      widgets.add(
        _buildEmptyTabCard(
          theme,
          title: 'No content yet',
          message:
              'The section exists, but it does not contain a summary or claim items yet.',
        ),
      );
    }
    return widgets;
  }

  List<Widget> _buildStructuredSectionWidgets(
    ThemeData theme,
    ExerciseScienceInfo info,
    ExerciseScienceSection section, {
    required IconData icon,
    Color? accentColor,
    String? titleOverride,
  }) {
    final widgets = <Widget>[];
    final title = titleOverride ?? section.title;
    final summary = section.summary?.trim();
    if (summary != null && summary.isNotEmpty) {
      widgets.add(
        _buildSummaryCard(
          theme,
          title: title,
          icon: icon,
          summary: summary,
          color: accentColor,
        ),
      );
      widgets.add(const SizedBox(height: 16));
    } else if (section.items.isNotEmpty) {
      widgets.add(_buildSectionTitle(theme, title, icon, color: accentColor));
      widgets.add(const SizedBox(height: 12));
    }

    for (final point in section.items) {
      widgets.add(
        _buildPointCard(
          theme,
          info,
          point,
          accentColor: accentColor,
        ),
      );
      widgets.add(const SizedBox(height: 12));
    }
    if (widgets.isNotEmpty) {
      widgets.add(const SizedBox(height: 12));
    }
    return widgets;
  }

  List<Widget> _buildSourcesChildren(
    ThemeData theme,
    ExerciseScienceInfo info,
  ) {
    final sources = info.resolvedSourceDocuments;
    final widgets = <Widget>[
      GlassCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.route_outlined,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    'Source Traceability',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Each structured claim can reference the document IDs below. Copy the evidence report if you want to critique the extraction outside the app.',
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildMetaPill(
                  theme,
                  '${sources.length} document${sources.length == 1 ? '' : 's'}',
                ),
                _buildMetaPill(
                  theme,
                  '${info.orderedSections.length} structured section${info.orderedSections.length == 1 ? '' : 's'}',
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () => _copyText(
                _buildEvidenceReport(info),
                'Evidence report copied to clipboard.',
              ),
              icon: const Icon(Icons.copy_all_rounded),
              label: const Text('Copy Evidence Report'),
            ),
          ],
        ),
      ),
      const SizedBox(height: 16),
    ];

    if (info.sourceDocuments.isEmpty && info.citations.isNotEmpty) {
      widgets.add(
        _buildEmptyTabCard(
          theme,
          title: 'Legacy source list',
          message:
              'This entry still comes from the older citation-only format. Ora generated stable source IDs so claims can reference the documents consistently.',
        ),
      );
      widgets.add(const SizedBox(height: 16));
    }

    for (final source in sources) {
      widgets.add(_buildSourceCard(theme, source));
      widgets.add(const SizedBox(height: 16));
    }

    return widgets;
  }

  Widget _buildTabStrip(
    ThemeData theme,
    List<_ExerciseInfoTab> tabs,
    String selectedKey,
  ) {
    return SizedBox(
      height: 56,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        itemCount: tabs.length,
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, index) {
          final tab = tabs[index];
          final selected = tab.key == selectedKey;
          return Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(999),
              onTap: () => setState(() => _selectedTabKey = tab.key),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 180),
                curve: Curves.easeOut,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: selected
                      ? theme.colorScheme.primary.withValues(alpha: 0.16)
                      : theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(
                    color: selected
                        ? theme.colorScheme.primary.withValues(alpha: 0.44)
                        : theme.colorScheme.onSurface.withValues(alpha: 0.08),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      tab.icon,
                      size: 18,
                      color: selected
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurface.withValues(alpha: 0.72),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      tab.label,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight:
                            selected ? FontWeight.w700 : FontWeight.w600,
                        color: selected
                            ? theme.colorScheme.primary
                            : theme.colorScheme.onSurface
                                .withValues(alpha: 0.82),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSummaryCard(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required String summary,
    Color? color,
  }) {
    final accentColor = color ?? theme.colorScheme.primary;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: accentColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            summary,
            style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
          ),
        ],
      ),
    );
  }

  Widget _buildNumberedListCard(
    ThemeData theme, {
    required String title,
    required IconData icon,
    required List<String> items,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(theme, title, icon),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${i + 1}.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: theme.colorScheme.primary,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i],
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildAvoidCard(
    ThemeData theme, {
    required String title,
    required List<String> items,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSectionTitle(
            theme,
            title,
            Icons.warning_amber_rounded,
            color: Colors.orange,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < items.length; i++) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.close, size: 16, color: Colors.orange),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    items[i],
                    style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
                  ),
                ),
              ],
            ),
            if (i != items.length - 1) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }

  Widget _buildPointCard(
    ThemeData theme,
    ExerciseScienceInfo info,
    ExerciseSciencePoint point, {
    Color? accentColor,
  }) {
    final effectiveColor = accentColor ?? theme.colorScheme.primary;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            point.title,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
              color: effectiveColor,
            ),
          ),
          if (point.detail != null && point.detail!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              point.detail!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45),
            ),
          ],
          if (point.sourceIds.isNotEmpty) ...[
            const SizedBox(height: 12),
            _buildSourceReferenceChips(theme, info, point.sourceIds),
          ],
        ],
      ),
    );
  }

  Widget _buildSourceReferenceChips(
    ThemeData theme,
    ExerciseScienceInfo info,
    List<String> sourceIds,
  ) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final sourceId in sourceIds)
          Tooltip(
            message: _sourceTooltip(info, sourceId),
            child: ActionChip(
              avatar: const Icon(Icons.menu_book_outlined, size: 16),
              label: Text(sourceId),
              onPressed: () => setState(() => _selectedTabKey = 'sources'),
              backgroundColor:
                  theme.colorScheme.primary.withValues(alpha: 0.12),
              labelStyle: theme.textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.w700,
                color: theme.colorScheme.primary,
              ),
              side: BorderSide(
                color: theme.colorScheme.primary.withValues(alpha: 0.18),
              ),
            ),
          ),
      ],
    );
  }

  String _sourceTooltip(ExerciseScienceInfo info, String sourceId) {
    final source = info.sourceById(sourceId);
    if (source == null) {
      return 'See Sources tab for $sourceId';
    }
    return '$sourceId: ${source.displayTitle}';
  }

  Widget _buildSourceCard(
    ThemeData theme,
    ExerciseScienceSourceDocument source,
  ) {
    final title = source.title?.trim();
    final hasSeparateTitle =
        title != null && title.isNotEmpty && title != source.citation.trim();
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  source.normalizedId,
                  style: theme.textTheme.labelLarge?.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hasSeparateTitle ? title : source.citation,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    if (hasSeparateTitle) ...[
                      const SizedBox(height: 8),
                      SelectableText(
                        source.citation,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.4,
                          fontStyle: FontStyle.italic,
                          color: theme.colorScheme.onSurface
                              .withValues(alpha: 0.72),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _copyText(
                  source.citation,
                  'Source ${source.normalizedId} copied to clipboard.',
                ),
                icon: const Icon(Icons.copy_rounded, size: 18),
                tooltip: 'Copy citation',
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          if (source.documentType != null || source.year != null) ...[
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (source.documentType != null)
                  _buildMetaPill(theme, source.documentType!),
                if (source.year != null)
                  _buildMetaPill(theme, source.year.toString()),
              ],
            ),
          ],
          if (source.relevance != null &&
              source.relevance!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              source.relevance!,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.4),
            ),
          ],
          if (source.url != null && source.url!.trim().isNotEmpty) ...[
            const SizedBox(height: 12),
            SelectableText(
              source.url!,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.primary,
                height: 1.4,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildMetaPill(ThemeData theme, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:
            theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
          color: theme.colorScheme.onSurface.withValues(alpha: 0.74),
        ),
      ),
    );
  }

  Widget _buildEmptyTabCard(
    ThemeData theme, {
    required String title,
    required String message,
  }) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            message,
            style: theme.textTheme.bodyMedium?.copyWith(
              height: 1.45,
              color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  String _buildEvidenceReport(ExerciseScienceInfo info) {
    final buffer = StringBuffer()
      ..writeln('Exercise: ${widget.exerciseName}')
      ..writeln('Exercise ID: ${widget.exerciseId}');

    if (info.instructions.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Technique:');
      for (var i = 0; i < info.instructions.length; i++) {
        buffer.writeln('${i + 1}. ${info.instructions[i]}');
      }
    }

    if (info.avoid.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Safety - Avoid:');
      for (final item in info.avoid) {
        buffer.writeln('- $item');
      }
    }

    for (final section in info.orderedSections) {
      buffer
        ..writeln()
        ..writeln('${section.title}:');
      final summary = section.summary?.trim();
      if (summary != null && summary.isNotEmpty) {
        buffer.writeln('Summary: $summary');
      }
      for (final item in section.items) {
        buffer.write('- ${item.title}');
        final detail = item.detail?.trim();
        if (detail != null && detail.isNotEmpty) {
          buffer.write(': $detail');
        }
        if (item.sourceIds.isNotEmpty) {
          buffer.write(' [${item.sourceIds.join(', ')}]');
        }
        buffer.writeln();
      }
    }

    final sources = info.resolvedSourceDocuments;
    if (sources.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('Sources:');
      for (final source in sources) {
        buffer.writeln('[${source.normalizedId}] ${source.citation}');
        final relevance = source.relevance?.trim();
        if (relevance != null && relevance.isNotEmpty) {
          buffer.writeln('  Relevance: $relevance');
        }
        final url = source.url?.trim();
        if (url != null && url.isNotEmpty) {
          buffer.writeln('  URL: $url');
        }
      }
    }

    return buffer.toString().trimRight();
  }

  Widget _buildVisuals(ThemeData theme, List<String> paths) {
    return SizedBox(
      height: 200,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: paths.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          return ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.asset(
              paths[index],
              height: 200,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(
                width: 200,
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(child: Icon(Icons.image_not_supported)),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSectionTitle(
    ThemeData theme,
    String title,
    IconData icon, {
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? theme.colorScheme.primary),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            title,
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ),
      ],
    );
  }

  IconData _iconForSection(String key) {
    switch (key) {
      case 'technique':
        return Icons.play_circle_outline;
      case 'safety':
        return Icons.health_and_safety_outlined;
      case 'effectiveness':
        return Icons.trending_up_rounded;
      case 'programming':
        return Icons.tune_rounded;
      case 'considerations':
        return Icons.fact_check_outlined;
      default:
        return Icons.library_books_outlined;
    }
  }

  Color? _accentColorForSection(String key) {
    switch (key) {
      case 'safety':
        return Colors.orange;
      case 'effectiveness':
        return Colors.green;
      default:
        return null;
    }
  }
}

class _ExerciseInfoTab {
  const _ExerciseInfoTab({
    required this.key,
    required this.label,
    required this.icon,
    this.section,
  });

  final String key;
  final String label;
  final IconData icon;
  final ExerciseScienceSection? section;
}
