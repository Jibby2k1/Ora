import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/appearance_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../core/cloud/upload_service.dart';
import '../../../domain/models/appearance_entry.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../shell/app_shell_controller.dart';
import '../../../core/input/input_router.dart';

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsRepo _settingsRepo;
  late final AppearanceRepo _appearanceRepo;
  final _uploadService = UploadService.instance;
  bool _accessReady = false;
  double _skinScore = 0;
  double _physiqueScore = 0;
  double _styleScore = 0;
  Future<List<AppearanceEntry>>? _timelineFuture;
  bool _handlingInput = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _appearanceRepo = AppearanceRepo(AppDatabase.instance);
    _ensureAccess();
    _refreshTimeline();
    _uploadService.addListener(_onUploadsChanged);
    AppShellController.instance.pendingInput.addListener(_handlePendingInput);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_onUploadsChanged);
    AppShellController.instance.pendingInput.removeListener(_handlePendingInput);
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appearance logs come from Orb uploads.')),
      );
    }
    _handlingInput = false;
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
    _refreshScores();
  }

  Future<void> _refreshScores() async {
    final entries = await _appearanceRepo.getRecentEntries(limit: 200);
    final scores = _latestScoresFromEntries(entries);
    if (!mounted) return;
    setState(() {
      _skinScore = scores.skin;
      _physiqueScore = scores.physique;
      _styleScore = scores.style;
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

  _FeedbackScores _latestScoresFromEntries(List<AppearanceEntry> entries) {
    double skin = 0;
    double physique = 0;
    double style = 0;
    for (final entry in entries) {
      final data = _decodeMeasurements(entry.measurements);
      if (data['type'] != 'feedback') continue;
      final category = data['category']?.toString();
      final score = _readScore(data['score']);
      if (score == null) continue;
      switch (category) {
        case 'skin':
          skin = score;
          break;
        case 'physique':
          physique = score;
          break;
        case 'style':
          style = score;
          break;
      }
    }
    return _FeedbackScores(skin: skin, physique: physique, style: style);
  }

  double? _readScore(Object? raw) {
    if (raw is int) return raw.toDouble();
    if (raw is double) return raw;
    final parsed = double.tryParse(raw?.toString() ?? '');
    return parsed;
  }

  Widget _buildFeedbackHistoryCard(String title, String category) {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title),
          const SizedBox(height: 8),
          FutureBuilder<List<AppearanceEntry>>(
            future: _timelineFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data ?? [];
              final filtered = entries.where((entry) {
                final data = _decodeMeasurements(entry.measurements);
                return data['type'] == 'feedback' && data['category'] == category;
              }).toList();
              if (filtered.isEmpty) {
                return const Text('No feedback yet.');
              }
              return Column(
                children: filtered.take(6).map((entry) {
                  final data = _decodeMeasurements(entry.measurements);
                  final feedback = data['feedback']?.toString().trim();
                  final delta = data['score_delta'];
                  final score = data['score'];
                  final uploadName = data['upload_name']?.toString();
                  final deltaLabel = delta == null ? null : 'Δ ${delta.toString()}';
                  final scoreLabel = score == null ? null : 'Score ${score.toString()}';
                  final meta = [
                    if (scoreLabel != null) scoreLabel,
                    if (deltaLabel != null) deltaLabel,
                    if (uploadName != null && uploadName.trim().isNotEmpty) uploadName.trim(),
                  ].join(' • ');
                  return ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      feedback == null || feedback.isEmpty ? 'Feedback logged.' : feedback,
                    ),
                    subtitle: meta.isEmpty ? null : Text(meta),
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
              skin: _skinScore / 100.0,
              physique: _physiqueScore / 100.0,
              style: _styleScore / 100.0,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Scores update only from upload feedback.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
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
              _buildProgressRingsCard(),
              const SizedBox(height: 12),
              _buildFeedbackHistoryCard('Skin Feedback History', 'skin'),
              const SizedBox(height: 12),
              _buildFeedbackHistoryCard('Physique Feedback History', 'physique'),
              const SizedBox(height: 12),
              _buildFeedbackHistoryCard('Style Feedback History', 'style'),
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
                            .map(_uploadTile),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
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
          subtitle: Text('Appearance • $statusText'),
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

class _StackedRings extends StatelessWidget {
  const _StackedRings({
    required this.skin,
    required this.physique,
    required this.style,
  });

  final double skin;
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
              value: skin.clamp(0.0, 1.0),
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
              Text('Skin ${((skin) * 100).round()}'),
              Text('Phys ${((physique) * 100).round()}'),
              Text('Style ${((style) * 100).round()}'),
            ],
          ),
        ],
      ),
    );
  }
}

class _FeedbackScores {
  const _FeedbackScores({
    required this.skin,
    required this.physique,
    required this.style,
  });

  final double skin;
  final double physique;
  final double style;
}
