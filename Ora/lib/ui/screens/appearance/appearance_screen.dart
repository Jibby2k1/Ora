import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/appearance_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../core/cloud/upload_service.dart';
import '../../../domain/services/calorie_service.dart';
import '../../../domain/models/appearance_entry.dart';
import '../../widgets/consent/cloud_consent.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../shell/app_shell_controller.dart';
import '../../../core/input/input_router.dart';

enum AppearanceAssessment { face, physique, style }

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsRepo _settingsRepo;
  late final CalorieService _calorieService;
  late final AppearanceRepo _appearanceRepo;
  final _uploadService = UploadService.instance;
  final _imagePicker = ImagePicker();
  bool _accessReady = false;
  AppearanceAssessment _assessment = AppearanceAssessment.physique;
  _CalorieRange _calorieRange = _CalorieRange.day;
  double _fitScore = 7;
  String _fitFeedback = 'Submit a fit to get feedback.';
  final _fitNotesController = TextEditingController();
  final _styleNotesController = TextEditingController();
  final _routineNotesController = TextEditingController();
  final _confidenceNotesController = TextEditingController();
  double _confidenceScore = 7;
  double _faceScore = 72;
  double _physiqueScore = 68;
  double _styleScore = 70;
  final _measurementWaist = TextEditingController();
  final _measurementHips = TextEditingController();
  final _measurementChest = TextEditingController();
  final _measurementWeight = TextEditingController();
  String _styleSummary = 'No summary yet.';
  Future<List<AppearanceEntry>>? _timelineFuture;
  bool _handlingInput = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _calorieService = CalorieService(AppDatabase.instance);
    _appearanceRepo = AppearanceRepo(AppDatabase.instance);
    _ensureAccess();
    _refreshTimeline();
    Future.microtask(_rebuildStyleSummary);
    _uploadService.addListener(_onUploadsChanged);
    AppShellController.instance.pendingInput.addListener(_handlePendingInput);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_onUploadsChanged);
    AppShellController.instance.pendingInput.removeListener(_handlePendingInput);
    _fitNotesController.dispose();
    _styleNotesController.dispose();
    _routineNotesController.dispose();
    _confidenceNotesController.dispose();
    _measurementWaist.dispose();
    _measurementHips.dispose();
    _measurementChest.dispose();
    _measurementWeight.dispose();
    super.dispose();
  }

  Future<void> _handlePendingInput() async {
    if (!mounted || _handlingInput) return;
    final dispatch = AppShellController.instance.pendingInput.value;
    if (dispatch == null || dispatch.intent != InputIntent.appearanceLog) return;
    _handlingInput = true;
    AppShellController.instance.clearPendingInput();
    final event = dispatch.event;
    if (event.file != null) {
      await _confirmAppearanceUpload(event.file!);
    } else if ((dispatch.entity ?? event.text)?.trim().isNotEmpty == true) {
      await _confirmAppearanceNote((dispatch.entity ?? event.text!).trim());
    }
    _handlingInput = false;
  }

  Future<void> _confirmAppearanceNote(String note) async {
    if (!mounted) return;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Add appearance note'),
                const SizedBox(height: 8),
                Text(note),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.check),
                    label: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (approved != true) return;
    await _saveAppearanceEntry(type: 'style_notes', notes: note);
  }

  Future<void> _confirmAppearanceUpload(File file) async {
    if (!mounted) return;
    final approved = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Queue appearance upload'),
                const SizedBox(height: 8),
                Text(file.path.split('/').last),
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton.icon(
                    onPressed: () => Navigator.of(context).pop(true),
                    icon: const Icon(Icons.cloud_upload),
                    label: const Text('Queue'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
    if (approved != true) return;
    _uploadService.enqueue(
      UploadItem(
        type: UploadType.appearance,
        name: file.uri.pathSegments.last,
        path: file.path,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued for upload.')),
    );
  }

  void _onUploadsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  void _refreshTimeline() {
    setState(() {
      _timelineFuture = _appearanceRepo.getRecentEntries(limit: 30);
    });
  }

  Future<void> _saveAppearanceEntry({
    required String type,
    Map<String, Object?>? payload,
    String? notes,
  }) async {
    final data = <String, Object?>{
      'type': type,
      'payload': payload ?? <String, Object?>{},
    };
    await _appearanceRepo.addEntry(
      createdAt: DateTime.now(),
      measurements: jsonEncode(data),
      notes: notes?.trim().isEmpty == true ? null : notes?.trim(),
    );
    _refreshTimeline();
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

  String _formatDate(DateTime date) {
    final mm = date.month.toString().padLeft(2, '0');
    final dd = date.day.toString().padLeft(2, '0');
    return '${date.year}-$mm-$dd';
  }

  String _dailyQuote() {
    const quotes = [
      'Small steps, sharp details.',
      'Consistency beats intensity.',
      'Show up, then level up.',
      'Discipline, then confidence.',
      'Progress looks good on you.',
      'Strong is a style choice.',
      'You are the mood board.',
    ];
    final day = DateTime.now().day + DateTime.now().month * 31;
    return quotes[day % quotes.length];
  }

  Future<void> _rebuildStyleSummary() async {
    final entries = await _appearanceRepo.getRecentEntries(limit: 50);
    final now = DateTime.now();
    final weekStart = now.subtract(const Duration(days: 7));
    final notes = entries
        .where((entry) => entry.createdAt.isAfter(weekStart))
        .where((entry) => _decodeMeasurements(entry.measurements)['type'] == 'style_notes')
        .map((entry) => entry.notes ?? '')
        .where((note) => note.trim().isNotEmpty)
        .toList();
    if (!mounted) return;
    if (notes.isEmpty) {
      setState(() => _styleSummary = 'No summary yet.');
      return;
    }
    final last = notes.first;
    final preview = last.length > 80 ? '${last.substring(0, 80)}...' : last;
    setState(() {
      _styleSummary = '${notes.length} notes this week. Latest: $preview';
    });
  }

  String _fitFeedbackFor(double score) {
    if (score >= 9) return 'Elite fit. Try a bolder accent or texture.';
    if (score >= 7) return 'Strong fit. Consider a sharper silhouette or accessory.';
    if (score >= 5) return 'Solid base. Improve contrast and layering.';
    return 'Start simple: clean lines, neutral base, one statement piece.';
  }

  String _confidenceLabel(double value) {
    if (value >= 9) return 'Unstoppable';
    if (value >= 7) return 'Confident';
    if (value >= 5) return 'Steady';
    return 'Rebuilding';
  }

  Future<DateTime?> _latestEntryDate(String type) async {
    final entries = await _appearanceRepo.getRecentEntries(limit: 50);
    for (final entry in entries) {
      final data = _decodeMeasurements(entry.measurements);
      if (data['type'] == type) return entry.createdAt;
    }
    return null;
  }

  Widget _buildProgressRingsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Progress Rings'),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.center,
            child: _StackedRings(
              face: _faceScore / 100.0,
              physique: _physiqueScore / 100.0,
              style: _styleScore / 100.0,
            ),
          ),
          const SizedBox(height: 12),
          _ScoreSlider(
            label: 'Face',
            value: _faceScore,
            onChanged: (value) => setState(() => _faceScore = value),
          ),
          _ScoreSlider(
            label: 'Physique',
            value: _physiqueScore,
            onChanged: (value) => setState(() => _physiqueScore = value),
          ),
          _ScoreSlider(
            label: 'Style',
            value: _styleScore,
            onChanged: (value) => setState(() => _styleScore = value),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _saveAppearanceEntry(
                  type: 'checkin',
                  payload: {
                    'face': _faceScore.round(),
                    'physique': _physiqueScore.round(),
                    'style': _styleScore.round(),
                  },
                );
              },
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Save check-in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFitSessionCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Fit Session'),
          const SizedBox(height: 8),
          Text('Rate the fit and get instant feedback.'),
          const SizedBox(height: 12),
          _ScoreSlider(
            label: 'Fit score',
            value: _fitScore,
            onChanged: (value) => setState(() => _fitScore = value),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _fitNotesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Fit notes',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _fitFeedback,
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                final feedback = _fitFeedbackFor(_fitScore);
                setState(() => _fitFeedback = feedback);
                await _saveAppearanceEntry(
                  type: 'fit_session',
                  payload: {
                    'score': _fitScore.round(),
                    'feedback': feedback,
                  },
                  notes: _fitNotesController.text,
                );
                _fitNotesController.clear();
              },
              icon: const Icon(Icons.flash_on),
              label: const Text('Submit fit'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRoutineCheckInCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Skin + Hair Routine'),
          const SizedBox(height: 8),
          FutureBuilder<DateTime?>(
            future: _latestEntryDate('routine'),
            builder: (context, snapshot) {
              final date = snapshot.data;
              final due = date == null || DateTime.now().difference(date).inDays >= 7;
              return Text(
                date == null
                    ? 'No check-ins yet.'
                    : 'Last check-in: ${_formatDate(date)}${due ? ' (due)' : ''}',
                style: Theme.of(context).textTheme.bodySmall,
              );
            },
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _routineNotesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Routine feedback',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _saveAppearanceEntry(
                  type: 'routine',
                  payload: {'cadence': 'weekly'},
                  notes: _routineNotesController.text,
                );
                _routineNotesController.clear();
              },
              icon: const Icon(Icons.spa_outlined),
              label: const Text('Log check-in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStyleNotesCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Style Notes'),
          const SizedBox(height: 8),
          TextField(
            controller: _styleNotesController,
            maxLines: 3,
            decoration: const InputDecoration(
              labelText: 'Outfit + grooming reflections',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _saveAppearanceEntry(
                  type: 'style_notes',
                  notes: _styleNotesController.text,
                );
                _styleNotesController.clear();
                await _rebuildStyleSummary();
              },
              icon: const Icon(Icons.note_add_outlined),
              label: const Text('Save note'),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            _styleSummary,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  Widget _buildMeasurementsCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Body Measurements'),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _measurementWaist,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Waist (in)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _measurementHips,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Hips (in)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _measurementChest,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Chest (in)'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _measurementWeight,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Weight (lb)'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _saveAppearanceEntry(
                  type: 'measurements',
                  payload: {
                    'waist': _measurementWaist.text.trim(),
                    'hips': _measurementHips.text.trim(),
                    'chest': _measurementChest.text.trim(),
                    'weight': _measurementWeight.text.trim(),
                  },
                );
                _measurementWaist.clear();
                _measurementHips.clear();
                _measurementChest.clear();
                _measurementWeight.clear();
              },
              icon: const Icon(Icons.straighten),
              label: const Text('Save measurements'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildConfidenceCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Confidence Check-in'),
          const SizedBox(height: 8),
          Text('Quote of the day: "${_dailyQuote()}"'),
          const SizedBox(height: 8),
          Text('Today: ${_confidenceLabel(_confidenceScore)}'),
          Slider(
            value: _confidenceScore,
            min: 1,
            max: 10,
            divisions: 9,
            label: _confidenceScore.round().toString(),
            onChanged: (value) => setState(() => _confidenceScore = value),
          ),
          TextField(
            controller: _confidenceNotesController,
            maxLines: 2,
            decoration: const InputDecoration(
              labelText: 'Reflection',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerRight,
            child: ElevatedButton.icon(
              onPressed: () async {
                await _saveAppearanceEntry(
                  type: 'confidence',
                  payload: {'score': _confidenceScore.round()},
                  notes: _confidenceNotesController.text,
                );
                _confidenceNotesController.clear();
              },
              icon: const Icon(Icons.mood),
              label: const Text('Save check-in'),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTimelineCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Appearance Timeline'),
          const SizedBox(height: 8),
          FutureBuilder<List<AppearanceEntry>>(
            future: _timelineFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data ?? [];
              if (entries.isEmpty) {
                return const Text('No entries yet.');
              }
              return Column(
                children: entries.take(10).map((entry) {
                  final data = _decodeMeasurements(entry.measurements);
                  final type = (data['type'] ?? 'note').toString();
                  final payload = data['payload'] is Map ? data['payload'] as Map : const {};
                  final label = _timelineLabel(type);
                  final detail = _timelineDetail(type, payload, entry.notes);
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(label),
                    subtitle: Text(detail),
                    trailing: Text(_formatDate(entry.createdAt), style: Theme.of(context).textTheme.bodySmall),
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  String _timelineLabel(String type) {
    switch (type) {
      case 'checkin':
        return 'Progress Check-in';
      case 'fit_session':
        return 'Fit Session';
      case 'routine':
        return 'Routine Check-in';
      case 'style_notes':
        return 'Style Notes';
      case 'measurements':
        return 'Measurements';
      case 'confidence':
        return 'Confidence';
      default:
        return 'Entry';
    }
  }

  String _timelineDetail(String type, Map payload, String? notes) {
    if (type == 'checkin') {
      final face = payload['face'] ?? '-';
      final physique = payload['physique'] ?? '-';
      final style = payload['style'] ?? '-';
      return 'Face $face • Physique $physique • Style $style';
    }
    if (type == 'fit_session') {
      final score = payload['score'] ?? '-';
      return 'Score $score • ${notes ?? 'No notes'}';
    }
    if (type == 'measurements') {
      final waist = payload['waist'] ?? '-';
      final hips = payload['hips'] ?? '-';
      final chest = payload['chest'] ?? '-';
      return 'W $waist • H $hips • C $chest';
    }
    if (notes != null && notes.trim().isNotEmpty) {
      return notes.trim();
    }
    return 'No notes';
  }

  DateTimeRange _rangeFor(_CalorieRange range) {
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    switch (range) {
      case _CalorieRange.day:
        return DateTimeRange(start: startOfToday, end: startOfToday.add(const Duration(days: 1)));
      case _CalorieRange.week:
        return DateTimeRange(start: startOfToday.subtract(const Duration(days: 6)), end: startOfToday.add(const Duration(days: 1)));
      case _CalorieRange.month:
        return DateTimeRange(start: startOfToday.subtract(const Duration(days: 29)), end: startOfToday.add(const Duration(days: 1)));
    }
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

  Future<void> _pickMedia() async {
    final ok = await CloudConsent.ensureAppearanceConsent(context, _settingsRepo);
    if (!ok || !context.mounted) return;
    final result = await FilePicker.platform.pickFiles(
      allowMultiple: true,
      type: FileType.media,
    );
    if (result == null || result.files.isEmpty) return;
    setState(() {
      for (final file in result.files) {
        if (file.path == null) continue;
        _uploadService.enqueue(
          UploadItem(
            type: UploadType.appearance,
            name: file.name,
            path: file.path!,
          ),
        );
      }
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Queued for upload.')),
    );
  }

  Future<void> _useCamera() async {
    if (!(Platform.isAndroid || Platform.isIOS)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Camera is available on mobile devices.')),
      );
      return;
    }
    final ok = await CloudConsent.ensureAppearanceConsent(context, _settingsRepo);
    if (!ok || !context.mounted) return;
    final file = await _imagePicker.pickImage(source: ImageSource.camera);
    if (file == null) return;
    setState(() {
      _uploadService.enqueue(
        UploadItem(
          type: UploadType.appearance,
          name: file.name,
          path: file.path,
        ),
      );
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Captured and queued.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_accessReady) {
      return const Scaffold(
        body: Center(child: Text('Appearance disabled.')),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: const [SizedBox(width: 72)],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Assessment'),
                    const SizedBox(height: 12),
                    SegmentedButton<AppearanceAssessment>(
                      segments: const [
                        ButtonSegment(value: AppearanceAssessment.face, label: Text('Face')),
                        ButtonSegment(value: AppearanceAssessment.physique, label: Text('Physique')),
                        ButtonSegment(value: AppearanceAssessment.style, label: Text('Style')),
                      ],
                      selected: {_assessment},
                      onSelectionChanged: (value) {
                        setState(() => _assessment = value.first);
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              _buildProgressRingsCard(),
              const SizedBox(height: 12),
              _buildFitSessionCard(),
              const SizedBox(height: 12),
              _buildRoutineCheckInCard(),
              const SizedBox(height: 12),
              _buildStyleNotesCard(),
              const SizedBox(height: 12),
              _buildMeasurementsCard(),
              const SizedBox(height: 12),
              _buildConfidenceCard(),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Energy Balance'),
                    const SizedBox(height: 12),
                    SegmentedButton<_CalorieRange>(
                      segments: const [
                        ButtonSegment(value: _CalorieRange.day, label: Text('Day')),
                        ButtonSegment(value: _CalorieRange.week, label: Text('Week')),
                        ButtonSegment(value: _CalorieRange.month, label: Text('Month')),
                      ],
                      selected: {_calorieRange},
                      onSelectionChanged: (value) {
                        setState(() => _calorieRange = value.first);
                      },
                    ),
                    const SizedBox(height: 12),
                    FutureBuilder<CalorieAggregate>(
                      future: _calorieService.aggregateCaloriesForRange(
                        _rangeFor(_calorieRange).start,
                        _rangeFor(_calorieRange).end,
                      ),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState != ConnectionState.done) {
                          return const Center(child: CircularProgressIndicator());
                        }
                        final data = snapshot.data;
                        if (data == null) {
                          return const Text('No calorie data yet.');
                        }
                        final net = data.netCalories;
                        final netLabel = net >= 0 ? 'Surplus' : 'Deficit';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '${net.abs().toStringAsFixed(0)} kcal $netLabel',
                              style: Theme.of(context).textTheme.titleLarge,
                            ),
                            const SizedBox(height: 8),
                            Text('Added ${data.caloriesAdded.toStringAsFixed(0)} kcal'),
                            Text('Consumed ${(data.caloriesConsumed).toStringAsFixed(0)} kcal'),
                            const SizedBox(height: 8),
                            Text('Workout ${data.workoutCalories.toStringAsFixed(0)} kcal'),
                            Text('BMR ${data.bmrCalories.toStringAsFixed(0)} kcal'),
                            if (!data.bmrAvailable) ...[
                              const SizedBox(height: 6),
                              Text(
                                'Add age/height/weight in Profile for BMR.',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (_uploadService.queue.where((e) => e.type == UploadType.appearance).isNotEmpty)
                ...[
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Uploads (Appearance)'),
                        const SizedBox(height: 8),
                        ..._uploadService.queue
                            .where((e) => e.type == UploadType.appearance)
                            .map((item) => _uploadTile(item, _assessment)),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
              _buildTimelineCard(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uploadTile(UploadItem item, AppearanceAssessment assessment) {
    final statusText = item.status == UploadStatus.queued
        ? 'Queued'
        : item.status == UploadStatus.uploading
            ? 'Uploading ${(item.progress * 100).toStringAsFixed(0)}%'
            : item.status == UploadStatus.done
                ? 'Uploaded'
                : 'Error';
    final assessmentLabel = switch (assessment) {
      AppearanceAssessment.face => 'Face',
      AppearanceAssessment.physique => 'Physique',
      AppearanceAssessment.style => 'Style',
    };
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.name),
          subtitle: Text('$assessmentLabel • $statusText'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (item.status == UploadStatus.queued)
                IconButton(
                  icon: const Icon(Icons.cloud_upload),
                  onPressed: () => _uploadService.uploadItem(item),
                ),
              if (item.status == UploadStatus.error)
                IconButton(
                  icon: const Icon(Icons.refresh),
                  onPressed: () => _uploadService.uploadItem(item),
                ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _uploadService.remove(item);
                  });
                },
              ),
            ],
          ),
        ),
        if (item.status == UploadStatus.uploading)
          LinearProgressIndicator(value: item.progress),
      ],
    );
  }
}

enum _CalorieRange { day, week, month }

class _ScoreSlider extends StatelessWidget {
  const _ScoreSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('$label ${value.round()}'),
        Slider(
          value: value,
          min: 0,
          max: 100,
          divisions: 20,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _StackedRings extends StatelessWidget {
  const _StackedRings({
    required this.face,
    required this.physique,
    required this.style,
  });

  final double face;
  final double physique;
  final double style;

  @override
  Widget build(BuildContext context) {
    final primary = Theme.of(context).colorScheme.primary;
    final secondary = Theme.of(context).colorScheme.secondary;
    return SizedBox(
      height: 160,
      width: 160,
      child: Stack(
        alignment: Alignment.center,
        children: [
          SizedBox(
            height: 150,
            width: 150,
            child: CircularProgressIndicator(
              value: physique.clamp(0.0, 1.0),
              strokeWidth: 10,
              backgroundColor: primary.withOpacity(0.12),
              color: primary.withOpacity(0.8),
            ),
          ),
          SizedBox(
            height: 120,
            width: 120,
            child: CircularProgressIndicator(
              value: face.clamp(0.0, 1.0),
              strokeWidth: 10,
              backgroundColor: secondary.withOpacity(0.12),
              color: secondary.withOpacity(0.75),
            ),
          ),
          SizedBox(
            height: 90,
            width: 90,
            child: CircularProgressIndicator(
              value: style.clamp(0.0, 1.0),
              strokeWidth: 10,
              backgroundColor: Theme.of(context).colorScheme.tertiary.withOpacity(0.12),
              color: Theme.of(context).colorScheme.tertiary.withOpacity(0.75),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Face ${((face) * 100).round()}'),
              Text('Phys ${((physique) * 100).round()}'),
              Text('Style ${((style) * 100).round()}'),
            ],
          ),
        ],
      ),
    );
  }
}
