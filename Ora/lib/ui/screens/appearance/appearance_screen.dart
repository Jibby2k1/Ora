import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/cloud/appearance_analysis_service.dart';
import '../../../core/input/input_router.dart';
import '../../../core/utils/image_downscaler.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/appearance_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/appearance_care.dart';
import '../../../domain/models/appearance_entry.dart';
import '../../widgets/consent/cloud_consent.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../shell/app_shell_controller.dart';

enum _AppearanceHubSection { hub, assessment, plans, progress, sources }

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsRepo _settingsRepo;
  late final AppearanceRepo _appearanceRepo;
  final AppearanceAnalysisService _appearanceAnalysis =
      AppearanceAnalysisService();

  final TextEditingController _diagnosedController = TextEditingController();
  final TextEditingController _concernsController = TextEditingController();
  final TextEditingController _symptomsController = TextEditingController();
  final TextEditingController _goalsController = TextEditingController();
  final TextEditingController _routineController = TextEditingController();
  final TextEditingController _historyController = TextEditingController();
  final TextEditingController _styleContextController = TextEditingController();

  bool _accessReady = false;
  bool _refreshing = true;
  bool _analysisRunning = false;
  bool _handlingInput = false;
  String? _statusMessage;
  String? _statusError;
  Set<String> _selectedDomains = {
    ...AppearanceProtocolLibrary.supportedDomains
  };
  _AppearanceHubSection _selectedSection = _AppearanceHubSection.hub;

  AppearanceAssessmentResult? _latestAssessment;
  List<AppearanceCarePlan> _activePlans = const [];
  List<AppearanceProgressReview> _recentReviews = const [];
  List<AppearanceSourceDocument> _sourceDocuments = const [];
  List<AppearanceEntry> _legacyEntries = const [];

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _appearanceRepo = AppearanceRepo(AppDatabase.instance);
    _ensureAccess();
    _refreshHub();
    AppShellController.instance.pendingInput.addListener(_handlePendingInput);
  }

  @override
  void dispose() {
    AppShellController.instance.pendingInput
        .removeListener(_handlePendingInput);
    _diagnosedController.dispose();
    _concernsController.dispose();
    _symptomsController.dispose();
    _goalsController.dispose();
    _routineController.dispose();
    _historyController.dispose();
    _styleContextController.dispose();
    super.dispose();
  }

  Future<void> _ensureAccess() async {
    final existing = await _settingsRepo.getAppearanceAccessEnabled();
    if (existing != null) {
      if (!mounted) return;
      setState(() => _accessReady = existing);
      return;
    }
    if (!mounted) return;
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Appearance consent'),
        content: const Text(
          'Appearance features may involve sensitive personal data. '
          'By continuing you agree to use this section for your own data only.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Decline'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I agree'),
          ),
        ],
      ),
    );
    final granted = accepted == true;
    await _settingsRepo.setAppearanceAccessEnabled(granted);
    if (mounted) {
      setState(() => _accessReady = granted);
    }
    if (!granted) {
      AppShellController.instance.setAppearanceEnabled(false);
      AppShellController.instance.selectTab(0);
    } else {
      AppShellController.instance.setAppearanceEnabled(true);
    }
  }

  Future<void> _refreshHub() async {
    setState(() {
      _refreshing = true;
    });
    final assessment = await _appearanceRepo.getLatestStructuredAssessment();
    final plans = await _appearanceRepo.getActivePlans();
    final reviews = await _appearanceRepo.getRecentReviews(limit: 20);
    final legacyEntries = await _appearanceRepo.getRecentEntries(limit: 20);
    final sources = assessment?.sourceDocuments.isNotEmpty == true
        ? assessment!.sourceDocuments
        : await _appearanceRepo.getSourceDocuments();
    if (!mounted) return;
    setState(() {
      _latestAssessment = assessment;
      _activePlans = plans;
      _recentReviews = reviews;
      _legacyEntries = legacyEntries;
      _sourceDocuments = sources;
      _refreshing = false;
    });
  }

  Future<void> _handlePendingInput() async {
    if (!mounted || _handlingInput) return;
    final dispatch = AppShellController.instance.pendingInput.value;
    if (dispatch == null || dispatch.intent != InputIntent.appearanceLog) {
      return;
    }
    _handlingInput = true;
    AppShellController.instance.clearPendingInput();
    final event = dispatch.event;
    if (event.file != null) {
      await _processAppearanceImage(event.file!);
    } else if ((dispatch.entity ?? event.text)?.trim().isNotEmpty == true) {
      _showSnack('Appearance reviews require a photo upload.');
    }
    _handlingInput = false;
  }

  Future<void> _processAppearanceImage(File file) async {
    final consent =
        await CloudConsent.ensureAppearanceConsent(context, _settingsRepo);
    if (!consent || !mounted) return;
    final enabled = await _settingsRepo.getCloudEnabled();
    final apiKey = await _settingsRepo.getCloudApiKey();
    final provider = await _settingsRepo.getCloudProvider();
    final model = await _settingsRepo.getCloudModelForTask(
      CloudModelTask.documentImageAnalysis,
    );
    if (!enabled || apiKey == null || apiKey.trim().isEmpty) {
      _showSnack('Cloud analysis requires an API key.');
      return;
    }

    final questionnaire = await _buildQuestionnaire();
    if (!mounted) return;
    setState(() {
      _analysisRunning = true;
      _statusError = null;
      _statusMessage = 'Running structured appearance assessment...';
    });

    final result = await _appearanceAnalysis.analyzeStructuredAssessment(
      file: file,
      questionnaire: questionnaire,
      provider: provider,
      apiKey: apiKey,
      model: model,
    );

    if (!mounted) return;
    if (result == null) {
      setState(() {
        _analysisRunning = false;
        _statusError = 'Unable to generate a structured appearance assessment.';
        _statusMessage = null;
      });
      _showSnack('Unable to analyze appearance.');
      return;
    }

    final persisted = await ImageDownscaler.persistImageToSubdir(
      file,
      'appearance/assessments',
    );
    final enriched = AppearanceAssessmentResult(
      imagePath: persisted.path,
      questionnaire: questionnaire,
      generatedAt: result.generatedAt,
      overallSummary: result.overallSummary,
      directVerdict: result.directVerdict,
      candidateConcerns: result.candidateConcerns,
      plans: result.plans,
      sourceDocuments: result.sourceDocuments,
    );
    final assessmentId =
        await _appearanceRepo.saveStructuredAssessment(enriched);
    await _appearanceRepo.addEntry(
      createdAt: result.generatedAt,
      measurements: jsonEncode({
        'type': 'feedback',
        'category': _legacyCategoryFromAssessment(result),
        'feedback': result.directVerdict,
        'assessment_id': assessmentId,
        'upload_name': file.uri.pathSegments.isEmpty
            ? 'appearance-photo'
            : file.uri.pathSegments.last,
      }),
      imagePath: persisted.path,
    );

    await _refreshHub();
    if (!mounted) return;
    setState(() {
      _analysisRunning = false;
      _selectedSection = _AppearanceHubSection.assessment;
      _statusMessage = result.hasRedFlags
          ? 'Assessment saved. Red-flag items were routed to consult-first guidance.'
          : 'Assessment saved. Active cycles updated.';
    });
    _showSnack('Appearance assessment updated.');
  }

  Future<AppearanceQuestionnaire> _buildQuestionnaire() async {
    final sex = await _settingsRepo.getAppearanceProfileSex();
    return AppearanceQuestionnaire(
      domains: _selectedDomains.toList()..sort(),
      diagnosedConditions: _splitInput(_diagnosedController.text),
      mainConcerns: _splitInput(_concernsController.text),
      symptoms: _splitInput(_symptomsController.text),
      goals: _splitInput(_goalsController.text),
      currentRoutine: _trimOrNull(_routineController.text),
      history: _trimOrNull(_historyController.text),
      styleContext: _trimOrNull(_styleContextController.text),
      profileSex: sex,
    );
  }

  String _legacyCategoryFromAssessment(AppearanceAssessmentResult result) {
    final domain = result.orderedConcerns.isNotEmpty
        ? result.orderedConcerns.first.domain
        : 'skin';
    switch (domain) {
      case 'physique':
        return 'physique';
      case 'style':
      case 'hair':
        return 'style';
      case 'skin':
      default:
        return 'skin';
    }
  }

  List<String> _splitInput(String raw) {
    return raw
        .split(RegExp(r'[\n,]'))
        .map((part) => part.trim())
        .where((part) => part.isNotEmpty)
        .toList();
  }

  String? _trimOrNull(String raw) {
    final value = raw.trim();
    if (value.isEmpty) return null;
    return value;
  }

  void _showSnack(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  Future<void> _copyText(String label, String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    _showSnack('$label copied.');
  }

  Future<void> _showReviewDialog(AppearanceCarePlan plan) async {
    if (plan.id == null) return;
    var adherence = 70.0;
    var symptomChange = 'holding';
    final sideEffectsController = TextEditingController();
    final notesController = TextEditingController();
    final saved = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: Text('Log checkpoint: ${plan.title}'),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Adherence ${adherence.round()}%'),
                  Slider(
                    value: adherence,
                    min: 0,
                    max: 100,
                    divisions: 20,
                    onChanged: (value) {
                      setDialogState(() {
                        adherence = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    initialValue: symptomChange,
                    decoration: const InputDecoration(
                      labelText: 'Symptom trend',
                      border: OutlineInputBorder(),
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'improving', child: Text('Improving')),
                      DropdownMenuItem(
                          value: 'holding', child: Text('Holding')),
                      DropdownMenuItem(
                          value: 'worsening', child: Text('Worsening')),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setDialogState(() {
                        symptomChange = value;
                      });
                    },
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: sideEffectsController,
                    minLines: 2,
                    maxLines: 3,
                    decoration: const InputDecoration(
                      labelText: 'Side effects or friction',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: notesController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Notes',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Cancel'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('Save review'),
              ),
            ],
          );
        },
      ),
    );
    sideEffectsController.dispose();
    notesController.dispose();
    if (saved != true) return;
    await _appearanceRepo.addProgressReview(
      planId: plan.id!,
      createdAt: DateTime.now(),
      adherence: adherence.round(),
      symptomChange: symptomChange,
      sideEffects: sideEffectsController.text,
      notes: notesController.text,
    );
    await _refreshHub();
    if (!mounted) return;
    _showSnack('Checkpoint logged.');
  }

  Future<void> _clearIntake() async {
    _diagnosedController.clear();
    _concernsController.clear();
    _symptomsController.clear();
    _goalsController.clear();
    _routineController.clear();
    _historyController.clear();
    _styleContextController.clear();
    setState(() {
      _selectedDomains = {...AppearanceProtocolLibrary.supportedDomains};
      _statusError = null;
      _statusMessage = null;
    });
  }

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  String _tierLabel(String raw) {
    switch (raw) {
      case 'procedure':
        return 'Procedure consult';
      case 'clinician':
        return 'Clinician gate';
      case 'routine':
        return 'Routine cycle';
      case 'otc':
        return 'OTC cycle';
      default:
        return raw;
    }
  }

  Color _tierColor(BuildContext context, String raw) {
    switch (raw) {
      case 'procedure':
        return Colors.deepOrange;
      case 'clinician':
        return Colors.redAccent;
      case 'otc':
        return Colors.teal;
      case 'routine':
      default:
        return Theme.of(context).colorScheme.secondary;
    }
  }

  Color _severityColor(String raw) {
    switch (raw) {
      case 'high':
        return Colors.redAccent;
      case 'moderate':
        return Colors.orangeAccent;
      case 'low':
      default:
        return Colors.green;
    }
  }

  void _openSection(_AppearanceHubSection section) {
    if (_selectedSection == section) {
      return;
    }
    setState(() {
      _selectedSection = section;
    });
  }

  List<_AppearanceHubSection> get _navigableSections => const [
        _AppearanceHubSection.assessment,
        _AppearanceHubSection.plans,
        _AppearanceHubSection.progress,
        _AppearanceHubSection.sources,
      ];

  _AppearanceHubSection _recommendedSection() {
    final assessment = _latestAssessment;
    if (assessment == null) {
      return _AppearanceHubSection.assessment;
    }
    if (assessment.hasRedFlags) {
      return _AppearanceHubSection.assessment;
    }
    if (_activePlans.isNotEmpty && _recentReviews.isEmpty) {
      return _AppearanceHubSection.plans;
    }
    if (_recentReviews.isNotEmpty) {
      return _AppearanceHubSection.progress;
    }
    if (_sourceDocuments.isNotEmpty) {
      return _AppearanceHubSection.sources;
    }
    return _AppearanceHubSection.assessment;
  }

  String _sectionTitle(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return 'Appearance Hub';
      case _AppearanceHubSection.assessment:
        return 'Assessment';
      case _AppearanceHubSection.plans:
        return 'Plans';
      case _AppearanceHubSection.progress:
        return 'Progress';
      case _AppearanceHubSection.sources:
        return 'Sources';
    }
  }

  String _sectionDescription(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return 'Choose a focused workflow instead of navigating the whole system at once.';
      case _AppearanceHubSection.assessment:
        return 'Build or review the structured appearance critique from the latest photo and intake context.';
      case _AppearanceHubSection.plans:
        return 'Review the active treatment or optimization cycles, checkpoints, and escalation gates.';
      case _AppearanceHubSection.progress:
        return 'Track checkpoints, adherence, and the recent appearance log in one place.';
      case _AppearanceHubSection.sources:
        return 'Inspect the evidence bundle and policy references behind the current recommendations.';
    }
  }

  String _sectionMeta(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return 'One landing page for review, planning, tracking, and source audit.';
      case _AppearanceHubSection.assessment:
        final assessment = _latestAssessment;
        return assessment == null
            ? 'No structured review yet.'
            : 'Last review ${_formatDate(assessment.generatedAt)}';
      case _AppearanceHubSection.plans:
        final count = _activePlans.length;
        return count == 0
            ? 'No active cycles yet.'
            : '$count active cycle${count == 1 ? '' : 's'}';
      case _AppearanceHubSection.progress:
        final count = _recentReviews.length;
        return count == 0
            ? 'No checkpoint reviews yet.'
            : '$count recent checkpoint${count == 1 ? '' : 's'}';
      case _AppearanceHubSection.sources:
        final count = _sourceDocuments.length;
        return count == 0
            ? 'No source bundle loaded yet.'
            : '$count source document${count == 1 ? '' : 's'}';
    }
  }

  IconData _sectionIcon(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return Icons.dashboard_customize_rounded;
      case _AppearanceHubSection.assessment:
        return Icons.face_retouching_natural_rounded;
      case _AppearanceHubSection.plans:
        return Icons.route_rounded;
      case _AppearanceHubSection.progress:
        return Icons.timeline_rounded;
      case _AppearanceHubSection.sources:
        return Icons.library_books_rounded;
    }
  }

  Color _sectionAccent(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return Theme.of(context).colorScheme.primary;
      case _AppearanceHubSection.assessment:
        return Colors.orangeAccent;
      case _AppearanceHubSection.plans:
        return Colors.tealAccent.shade400;
      case _AppearanceHubSection.progress:
        return Colors.lightBlueAccent;
      case _AppearanceHubSection.sources:
        return Colors.amberAccent.shade400;
    }
  }

  String _hubHeadline() {
    final assessment = _latestAssessment;
    if (assessment == null) {
      return 'Start with one structured review, then branch into the exact workflow you need.';
    }
    if (assessment.hasRedFlags) {
      return 'The latest review flagged consult-first issues, so the hub keeps those decisions explicit.';
    }
    if (_activePlans.isNotEmpty) {
      return 'Your appearance cycles are active. Use the hub to review, track, or audit the evidence behind them.';
    }
    return 'The hub is ready for the next appearance review.';
  }

  String _hubSummary() {
    final assessment = _latestAssessment;
    if (assessment == null) {
      return 'The hub keeps appearance work organized: assessment intake, treatment cycles, checkpoint tracking, and source review are separated so the page stays readable.';
    }
    return 'Latest verdict: ${assessment.directVerdict}';
  }

  Widget _buildHubView() {
    final recommended = _recommendedSection();
    final scheme = Theme.of(context).colorScheme;
    final statusCard = _buildStatusCard();
    final hasStatus = statusCard is! SizedBox;
    final assessment = _latestAssessment;
    return RefreshIndicator(
      onRefresh: _refreshHub,
      child: ListView(
        key: const ValueKey('appearance-hub'),
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
        children: [
          if (hasStatus) ...[
            statusCard,
            const SizedBox(height: 12),
          ],
          GlassCard(
            padding: EdgeInsets.zero,
            child: Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    _sectionAccent(recommended).withValues(alpha: 0.18),
                    scheme.surfaceContainerHighest.withValues(alpha: 0.48),
                    scheme.surface.withValues(alpha: 0.72),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: scheme.surface.withValues(alpha: 0.7),
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(
                            color: _sectionAccent(recommended).withValues(
                              alpha: 0.32,
                            ),
                          ),
                        ),
                        child: Icon(
                          Icons.auto_awesome_rounded,
                          color: _sectionAccent(recommended),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Appearance Hub',
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w800),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Review, plan, track, or audit evidence from one landing page.',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      _Badge(
                        label: 'Recommended ${_sectionTitle(recommended)}',
                        color: _sectionAccent(recommended),
                      ),
                    ],
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _hubHeadline(),
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          fontWeight: FontWeight.w800,
                          height: 1.1,
                        ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _hubSummary(),
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  if (assessment != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: scheme.surface.withValues(alpha: 0.62),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: scheme.outline.withValues(alpha: 0.18),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Overall summary',
                            style: Theme.of(context).textTheme.labelLarge,
                          ),
                          const SizedBox(height: 6),
                          Text(assessment.overallSummary),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      _buildQuickStat(
                        label: 'Review state',
                        value: assessment == null
                            ? 'Not started'
                            : assessment.hasRedFlags
                                ? 'Consult-first'
                                : 'Active',
                      ),
                      _buildQuickStat(
                        label: 'Plans',
                        value: _activePlans.isEmpty
                            ? '0 active'
                            : '${_activePlans.length} active',
                      ),
                      _buildQuickStat(
                        label: 'Checkpoints',
                        value: _recentReviews.isEmpty
                            ? '0 logged'
                            : '${_recentReviews.length} logged',
                      ),
                      _buildQuickStat(
                        label: 'Sources',
                        value: _sourceDocuments.isEmpty
                            ? '0 loaded'
                            : '${_sourceDocuments.length} loaded',
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      FilledButton.icon(
                        onPressed: () => _openSection(recommended),
                        icon: Icon(_sectionIcon(recommended)),
                        label: Text('Open ${_sectionTitle(recommended)}'),
                      ),
                      OutlinedButton.icon(
                        onPressed: _refreshHub,
                        icon: const Icon(Icons.sync_rounded),
                        label: const Text('Refresh hub'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Text(
            'Choose what to do',
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Each path narrows the workflow so users can focus on one job at a time.',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 760;
              final cardWidth = isWide
                  ? (constraints.maxWidth - 12) / 2
                  : constraints.maxWidth;
              return Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  for (final section in _navigableSections)
                    SizedBox(
                      width: cardWidth,
                      child: _buildHubActionCard(
                        section,
                        recommended: section == recommended,
                      ),
                    ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildQuickStat({required String label, required String value}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      constraints: const BoxConstraints(minWidth: 132),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surface.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outline.withValues(alpha: 0.16)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodySmall),
          const SizedBox(height: 4),
          Text(
            value,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildHubActionCard(
    _AppearanceHubSection section, {
    required bool recommended,
  }) {
    final color = _sectionAccent(section);
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: () => _openSection(section),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                color.withValues(alpha: 0.12),
                scheme.surfaceContainerHighest.withValues(alpha: 0.38),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(_sectionIcon(section), color: color),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _sectionTitle(section),
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                  ),
                  if (recommended) _Badge(label: 'Recommended', color: color),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                _sectionDescription(section),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 12),
              Text(
                _sectionMeta(section),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: color,
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const SizedBox(height: 14),
              TextButton.icon(
                onPressed: () => _openSection(section),
                icon: const Icon(Icons.arrow_forward_rounded),
                label: Text('Open ${_sectionTitle(section)}'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDetailView() {
    final section = _selectedSection;
    return Column(
      key: ValueKey(_sectionTitle(section)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _buildSectionHeader(section),
        ),
        Expanded(child: _buildSectionBody(section)),
      ],
    );
  }

  Widget _buildSectionHeader(_AppearanceHubSection section) {
    final color = _sectionAccent(section);
    final scheme = Theme.of(context).colorScheme;
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_sectionIcon(section), color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionTitle(section),
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(_sectionDescription(section)),
                    const SizedBox(height: 6),
                    Text(
                      _sectionMeta(section),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _openSection(_AppearanceHubSection.hub),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Hub'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _navigableSections)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_sectionTitle(item)),
                      selected: item == section,
                      onSelected: (_) => _openSection(item),
                      avatar: Icon(
                        _sectionIcon(item),
                        size: 18,
                        color: item == section ? color : null,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (_refreshing) ...[
            const SizedBox(height: 12),
            LinearProgressIndicator(
              minHeight: 3,
              borderRadius: BorderRadius.circular(999),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSectionBody(_AppearanceHubSection section) {
    switch (section) {
      case _AppearanceHubSection.hub:
        return _buildHubView();
      case _AppearanceHubSection.assessment:
        return _buildAssessmentTab();
      case _AppearanceHubSection.plans:
        return _buildPlansTab();
      case _AppearanceHubSection.progress:
        return _buildProgressTab();
      case _AppearanceHubSection.sources:
        return _buildSourcesTab();
    }
  }

  Widget _buildStatusCard() {
    if (_statusMessage == null && _statusError == null && !_analysisRunning) {
      return const SizedBox.shrink();
    }
    final isError = _statusError != null;
    final text = _statusError ?? _statusMessage ?? '';
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_analysisRunning)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else
            Icon(
              isError ? Icons.warning_amber_rounded : Icons.check_circle,
              color: isError ? Colors.redAccent : Colors.green,
            ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAssessmentTab() {
    final assessment = _latestAssessment;
    return RefreshIndicator(
      onRefresh: _refreshHub,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildStatusCard(),
          if (_buildStatusCard() is! SizedBox) const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Assessment Intake',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'This screen is now built for direct appearance review. '
                  'The questionnaire below will be attached to the next appearance photo you upload through the app input flow.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final domain
                        in AppearanceProtocolLibrary.supportedDomains)
                      FilterChip(
                        label: Text(_capitalize(domain)),
                        selected: _selectedDomains.contains(domain),
                        onSelected: (selected) {
                          setState(() {
                            if (selected) {
                              _selectedDomains.add(domain);
                            } else if (_selectedDomains.length > 1) {
                              _selectedDomains.remove(domain);
                            }
                          });
                        },
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _diagnosedController,
                  label: 'Diagnosed issues or known conditions',
                  hint:
                      'e.g. acne vulgaris, seborrheic dermatitis, androgenetic shedding',
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _concernsController,
                  label: 'Main concerns',
                  hint:
                      'Comma or line separated: breakouts, under-eye fatigue, thinning, poor fit',
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _symptomsController,
                  label: 'Symptoms or friction',
                  hint:
                      'itching, irritation, scalp flaking, picking, inconsistent grooming',
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _goalsController,
                  label: 'Appearance goals',
                  hint:
                      'clearer skin, sharper silhouette, denser hair, better posture',
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _routineController,
                  label: 'Current routine',
                  hint: 'Current skin, hair, grooming, or training routine',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _historyController,
                  label: 'History and constraints',
                  hint:
                      'previous treatments, irritation history, budget, schedule',
                  maxLines: 3,
                ),
                const SizedBox(height: 12),
                _buildInputField(
                  controller: _styleContextController,
                  label: 'Style / context notes',
                  hint:
                      'workwear, casual, nightlife, gym, conservative dress code',
                  maxLines: 2,
                ),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: _clearIntake,
                    child: const Text('Clear intake'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          if (assessment != null) ...[
            _buildVerdictCard(assessment),
            const SizedBox(height: 12),
            ...assessment.orderedConcerns.map((concern) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildConcernCard(concern),
              );
            }),
          ] else
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No structured assessment yet. Complete the intake, then send an appearance photo through the app input flow to generate a direct review and treatment cycles.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInputField({
    required TextEditingController controller,
    required String label,
    required String hint,
    int maxLines = 2,
  }) {
    return TextField(
      controller: controller,
      minLines: maxLines,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        border: const OutlineInputBorder(),
      ),
    );
  }

  Widget _buildVerdictCard(AppearanceAssessmentResult assessment) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Current Verdict',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _formatDate(assessment.generatedAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            assessment.directVerdict,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Text(
            assessment.overallSummary,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (assessment.hasRedFlags) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.red.withValues(alpha: 0.25)),
              ),
              child: const Text(
                'Red-flag concerns were detected. Those items are shown for awareness but are routed to consult-first guidance instead of self-managed cycles.',
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildConcernCard(AppearanceCandidateConcern concern) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Badge(
                label: _capitalize(concern.domain),
                color: Colors.blueGrey,
              ),
              _Badge(
                label: concern.severity.toUpperCase(),
                color: _severityColor(concern.severity),
              ),
              _Badge(
                label: _tierLabel(concern.interventionTier),
                color: _tierColor(context, concern.interventionTier),
              ),
              if (concern.redFlag)
                const _Badge(label: 'Consult first', color: Colors.redAccent),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            concern.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 6),
          Text(
            concern.directFeedback,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 8),
          Text(
            concern.evidenceSummary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 10),
          Text(
            'Confidence ${(concern.confidence * 100).round()}%',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildPlansTab() {
    return RefreshIndicator(
      onRefresh: _refreshHub,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (_activePlans.isEmpty)
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Text(
                'No active cycles yet. Run a structured assessment from a photo to generate skin, hair, style, or physique plans.',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            )
          else
            ..._activePlans.map((plan) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _buildPlanCard(plan),
              );
            }),
        ],
      ),
    );
  }

  Widget _buildPlanCard(AppearanceCarePlan plan) {
    final tierColor = _tierColor(context, plan.interventionTier);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      plan.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        _Badge(
                            label: _capitalize(plan.domain),
                            color: Colors.blueGrey),
                        _Badge(
                            label: _tierLabel(plan.interventionTier),
                            color: tierColor),
                        if (plan.checkpointDays.isNotEmpty)
                          _Badge(
                            label: 'Checks ${plan.checkpointDays.join('/')}d',
                            color: Colors.teal,
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              if (plan.id != null)
                TextButton(
                  onPressed: () => _showReviewDialog(plan),
                  child: const Text('Log checkpoint'),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(plan.summary),
          const SizedBox(height: 12),
          Text(
            'Cycle steps',
            style: Theme.of(context).textTheme.labelLarge,
          ),
          const SizedBox(height: 8),
          ...plan.steps.map((step) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(12),
                  border:
                      Border.all(color: Colors.white.withValues(alpha: 0.06)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${step.title} · ${step.durationDays}d',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      step.cadence,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 8),
                    ...step.actions.map((action) => Padding(
                          padding: const EdgeInsets.only(bottom: 4),
                          child: Text('• $action'),
                        )),
                    if (step.stopConditions.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        'Stop / pause conditions',
                        style: Theme.of(context).textTheme.labelMedium,
                      ),
                      const SizedBox(height: 4),
                      ...step.stopConditions.map((condition) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Text('• $condition'),
                          )),
                    ],
                  ],
                ),
              ),
            );
          }),
          if (plan.escalationRules.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              'Escalation rules',
              style: Theme.of(context).textTheme.labelLarge,
            ),
            const SizedBox(height: 6),
            ...plan.escalationRules.map((rule) => Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Text('• $rule'),
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildProgressTab() {
    return RefreshIndicator(
      onRefresh: _refreshHub,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent checkpoint reviews',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_recentReviews.isEmpty)
                  const Text('No checkpoint reviews yet.')
                else
                  ..._recentReviews.map((review) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildReviewCard(review),
                    );
                  }),
              ],
            ),
          ),
          const SizedBox(height: 12),
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Legacy appearance log',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 12),
                if (_legacyEntries.isEmpty)
                  const Text('No legacy feedback logged yet.')
                else
                  ..._legacyEntries.take(8).map((entry) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildLegacyEntryCard(entry),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewCard(AppearanceProgressReview review) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  review.planTitle ?? 'Checkpoint review',
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Text(
                _formatDate(review.createdAt),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (review.adherence != null)
                _Badge(
                    label: 'Adherence ${review.adherence}%',
                    color: Colors.teal),
              if (review.symptomChange != null)
                _Badge(
                  label: _capitalize(review.symptomChange!),
                  color: review.symptomChange == 'improving'
                      ? Colors.green
                      : review.symptomChange == 'worsening'
                          ? Colors.redAccent
                          : Colors.orangeAccent,
                ),
            ],
          ),
          if (review.sideEffects != null &&
              review.sideEffects!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('Side effects: ${review.sideEffects}'),
          ],
          if (review.notes != null && review.notes!.trim().isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(review.notes!),
          ],
        ],
      ),
    );
  }

  Widget _buildLegacyEntryCard(AppearanceEntry entry) {
    final data = _decodeMeasurements(entry.measurements);
    final feedback = data['feedback']?.toString().trim();
    final uploadName = data['upload_name']?.toString().trim();
    final imagePath = entry.imagePath;
    final imageFile =
        imagePath == null || imagePath.isEmpty ? null : File(imagePath);
    final hasImage = imageFile != null && imageFile.existsSync();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasImage)
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.file(
              imageFile,
              height: 160,
              width: double.infinity,
              fit: BoxFit.cover,
            ),
          ),
        const SizedBox(height: 8),
        Text(
          feedback == null || feedback.isEmpty
              ? 'Appearance feedback logged.'
              : feedback,
          style: const TextStyle(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 4),
        Text(
          [
            _formatDate(entry.createdAt),
            if (uploadName != null && uploadName.isNotEmpty) uploadName,
          ].join(' • '),
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }

  Map<String, Object?> _decodeMeasurements(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, dynamic>) {
        return decoded.map((key, value) => MapEntry(key.toString(), value));
      }
    } catch (_) {}
    return {};
  }

  Widget _buildSourcesTab() {
    return RefreshIndicator(
      onRefresh: _refreshHub,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Source documents',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Every active cycle should map back to a source document or a local policy reference so critiques can target a concrete document instead of vague AI text.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                if (_sourceDocuments.isEmpty)
                  const Text('No source documents loaded yet.')
                else
                  ..._sourceDocuments.map((document) {
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _buildSourceCard(document),
                    );
                  }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSourceCard(AppearanceSourceDocument document) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.06)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  document.title,
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              _Badge(
                  label: _capitalize(document.domain), color: Colors.blueGrey),
            ],
          ),
          const SizedBox(height: 8),
          SelectableText(document.citation),
          if (document.rationale != null &&
              document.rationale!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(document.rationale!),
          ],
          if (document.url != null && document.url!.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            SelectableText(document.url!),
          ],
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              TextButton(
                onPressed: () => _copyText('Citation', document.citation),
                child: const Text('Copy citation'),
              ),
              if (document.url != null && document.url!.trim().isNotEmpty)
                TextButton(
                  onPressed: () => _copyText('Link', document.url!),
                  child: const Text('Copy link'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  String _capitalize(String value) {
    if (value.isEmpty) return value;
    return value[0].toUpperCase() + value.substring(1);
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessReady) {
      return const Scaffold(
        body: Center(child: Text('Appearance disabled.')),
      );
    }
    final hasAnyData = _latestAssessment != null ||
        _activePlans.isNotEmpty ||
        _recentReviews.isNotEmpty ||
        _sourceDocuments.isNotEmpty ||
        _legacyEntries.isNotEmpty;
    final showInitialLoader = _refreshing && !hasAnyData;
    final title = _selectedSection == _AppearanceHubSection.hub
        ? 'Appearance Hub'
        : 'Appearance • ${_sectionTitle(_selectedSection)}';
    return PopScope<void>(
      canPop: _selectedSection == _AppearanceHubSection.hub,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedSection != _AppearanceHubSection.hub) {
          _openSection(_AppearanceHubSection.hub);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(title),
          actions: [
            if (_selectedSection != _AppearanceHubSection.hub)
              IconButton(
                tooltip: 'Back to hub',
                onPressed: () => _openSection(_AppearanceHubSection.hub),
                icon: const Icon(Icons.grid_view_rounded),
              ),
            if (_refreshing)
              const Padding(
                padding: EdgeInsets.only(right: 20),
                child: Center(
                  child: SizedBox(
                    height: 18,
                    width: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                ),
              )
            else
              IconButton(
                tooltip: 'Refresh',
                onPressed: _refreshHub,
                icon: const Icon(Icons.sync_rounded),
              ),
          ],
        ),
        body: Stack(
          children: [
            const GlassBackground(),
            if (showInitialLoader)
              const Center(child: CircularProgressIndicator())
            else
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 240),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: _selectedSection == _AppearanceHubSection.hub
                    ? _buildHubView()
                    : _buildDetailView(),
              ),
          ],
        ),
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}
