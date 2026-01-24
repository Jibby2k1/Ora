import 'dart:io';

import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:image_picker/image_picker.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/appearance_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/appearance_entry.dart';
import '../../../core/cloud/upload_service.dart';
import '../../../domain/services/calorie_service.dart';
import '../uploads/uploads_screen.dart';
import '../../widgets/consent/cloud_consent.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsRepo _settingsRepo;
  late final AppearanceRepo _appearanceRepo;
  late final CalorieService _calorieService;
  final _notesController = TextEditingController();
  final _measurementsController = TextEditingController();
  List<AppearanceEntry> _history = const [];
  final _uploadService = UploadService.instance;
  final _imagePicker = ImagePicker();
  bool _appearanceProfileEnabled = false;
  String _appearanceSex = 'neutral';
  _CalorieRange _calorieRange = _CalorieRange.day;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _appearanceRepo = AppearanceRepo(AppDatabase.instance);
    _calorieService = CalorieService(AppDatabase.instance);
    _loadHistory();
    _loadAppearanceProfilePrefs();
    _uploadService.addListener(_onUploadsChanged);
  }

  @override
  void dispose() {
    _notesController.dispose();
    _measurementsController.dispose();
    _uploadService.removeListener(_onUploadsChanged);
    super.dispose();
  }

  void _onUploadsChanged() {
    if (!mounted) return;
    setState(() {});
  }

  Future<void> _loadHistory() async {
    final entries = await _appearanceRepo.getRecentEntries();
    if (!mounted) return;
    setState(() {
      _history = entries;
    });
  }

  Future<void> _saveCheckIn() async {
    final measurements = _measurementsController.text.trim();
    final notes = _notesController.text.trim();
    await _appearanceRepo.addEntry(
      createdAt: DateTime.now(),
      measurements: measurements.isEmpty ? null : measurements,
      notes: notes.isEmpty ? null : notes,
    );
    _measurementsController.clear();
    _notesController.clear();
    await _loadHistory();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Check-in saved locally.')),
    );
  }

  Future<void> _loadAppearanceProfilePrefs() async {
    final enabled = await _settingsRepo.getAppearanceProfileEnabled();
    final sex = await _settingsRepo.getAppearanceProfileSex();
    if (!mounted) return;
    setState(() {
      _appearanceProfileEnabled = enabled;
      _appearanceSex = sex;
    });
  }

  Future<void> _toggleAppearanceProfile(bool value) async {
    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Appearance profile consent'),
          content: const Text(
            'This lets Ares personalize anatomy visuals in Training based on your '
            'appearance profile. The setting is stored locally on this device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I agree'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    setState(() {
      _appearanceProfileEnabled = value;
    });
    await _settingsRepo.setAppearanceProfileEnabled(value);
  }

  Future<void> _setAppearanceSex(String value) async {
    setState(() {
      _appearanceSex = value;
    });
    await _settingsRepo.setAppearanceProfileSex(value);
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

  Future<void> _uploadAll() async {
    await _uploadService.uploadAll();
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance'),
        actions: [
          IconButton(
            icon: const Icon(Icons.cloud_upload_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const UploadsScreen()),
              );
            },
          ),
        ],
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
                    const Text('Appearance profile'),
                    const SizedBox(height: 6),
                    Text(
                      'Optional. Used to personalize anatomy visuals in Training.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _appearanceProfileEnabled,
                      onChanged: _toggleAppearanceProfile,
                      title: const Text('Use appearance profile'),
                      subtitle: const Text('Requires consent. Stored locally.'),
                    ),
                    const SizedBox(height: 12),
                    InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Anatomy model',
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _appearanceSex,
                          isExpanded: true,
                          onChanged: _appearanceProfileEnabled
                              ? (value) {
                                  if (value == null) return;
                                  _setAppearanceSex(value);
                                }
                              : null,
                          items: const [
                            DropdownMenuItem(
                              value: 'neutral',
                              child: Text('Neutral'),
                            ),
                            DropdownMenuItem(
                              value: 'male',
                              child: Text('Male'),
                            ),
                            DropdownMenuItem(
                              value: 'female',
                              child: Text('Female'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Check-in'),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _measurementsController,
                      decoration: const InputDecoration(
                        labelText: 'Measurements (e.g. waist, chest, weight)',
                      ),
                      maxLines: 2,
                    ),
                    const SizedBox(height: 8),
                    TextField(
                      controller: _notesController,
                      decoration: const InputDecoration(
                        labelText: 'Notes (sleep, energy, mood)',
                      ),
                      maxLines: 3,
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: ElevatedButton.icon(
                        onPressed: _saveCheckIn,
                        icon: const Icon(Icons.save),
                        label: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Recent Evaluations'),
                    const SizedBox(height: 8),
                    ..._buildEvaluations(),
                  ],
                ),
              ),
              SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Photo / Video (Cloud)'),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        ElevatedButton.icon(
                          onPressed: _pickMedia,
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text('Pick media'),
                        ),
                        ElevatedButton.icon(
                          onPressed: _useCamera,
                          icon: const Icon(Icons.photo_camera),
                          label: const Text('Use camera'),
                        ),
                        TextButton(
                          onPressed: _uploadAll,
                          child: const Text('Upload all'),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_uploadService.queue.where((e) => e.type == UploadType.appearance).isEmpty)
                      const Text('No uploads queued.')
                    else
                      ..._uploadService.queue
                          .where((e) => e.type == UploadType.appearance)
                          .map(_uploadTile),
                  ],
                ),
              ),
              SizedBox(height: 12),
              GlassCard(
                child: ListTile(
                  title: Text('Style Notes'),
                  subtitle: Text('Outfit + grooming reflections'),
                ),
              ),
              SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('History'),
                    const SizedBox(height: 8),
                    if (_history.isEmpty)
                      const Text('No check-ins yet.')
                    else
                      ..._history.map((entry) => ListTile(
                            contentPadding: EdgeInsets.zero,
                            title: Text(entry.createdAt.toLocal().toString().split('.').first),
                            subtitle: Text(entry.measurements ?? entry.notes ?? ''),
                          )),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _uploadTile(UploadItem item) {
    final statusText = item.status == UploadStatus.queued
        ? 'Queued'
        : item.status == UploadStatus.uploading
            ? 'Uploading ${(item.progress * 100).toStringAsFixed(0)}%'
            : item.status == UploadStatus.done
                ? 'Uploaded'
                : 'Error';
    return Column(
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(item.name),
          subtitle: Text(statusText),
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

  List<Widget> _buildEvaluations() {
    final evaluations = _uploadService.recentEvaluations(UploadType.appearance);
    if (evaluations.isEmpty) {
      return const [Text('No evaluations yet.')];
    }
    return evaluations
        .map((eval) => ListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(eval.summary),
              subtitle: Text(eval.completedAt.toLocal().toString().split('.').first),
            ))
        .toList();
  }
}

enum _CalorieRange { day, week, month }
