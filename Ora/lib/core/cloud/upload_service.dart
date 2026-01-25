import 'dart:convert';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
import '../../core/cloud/appearance_analysis_service.dart';
import '../../core/utils/image_downscaler.dart';
import '../../data/db/db.dart';
import '../../data/repositories/appearance_repo.dart';
import '../../data/repositories/settings_repo.dart';
import '../../domain/models/appearance_entry.dart';
import '../../ui/screens/shell/app_shell_controller.dart';

enum UploadType { diet, appearance }

enum EvaluationStatus { none, processing, complete, failed }

class UploadItem {
  UploadItem({
    required this.type,
    required this.name,
    required this.path,
  });

  final UploadType type;
  final String name;
  final String path;
  UploadStatus status = UploadStatus.queued;
  double progress = 0;
  String? error;
  int retryCount = 0;
  DateTime? nextRetryAt;
  EvaluationStatus evaluationStatus = EvaluationStatus.none;
  String? evaluationSummary;
}

enum UploadStatus { queued, uploading, done, error }

class UploadService extends ChangeNotifier {
  UploadService._();

  static final UploadService instance = UploadService._();

  final List<UploadItem> queue = [];
  final List<UploadEvaluation> _evaluations = [];
  final AppearanceAnalysisService _appearanceAnalysis = AppearanceAnalysisService();

  bool get isSupported => !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  void enqueue(UploadItem item) {
    queue.add(item);
    notifyListeners();
  }

  void remove(UploadItem item) {
    queue.remove(item);
    notifyListeners();
  }

  List<UploadEvaluation> recentEvaluations(UploadType type, {int limit = 5}) {
    final filtered = _evaluations.where((e) => e.type == type).toList();
    filtered.sort((a, b) => b.completedAt.compareTo(a.completedAt));
    if (filtered.length <= limit) return filtered;
    return filtered.sublist(0, limit);
  }

  Future<void> uploadItem(UploadItem item) async {
    if (!isSupported) {
      item.status = UploadStatus.error;
      item.error = 'Uploads supported only on mobile.';
      notifyListeners();
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      item.status = UploadStatus.error;
      item.error = 'Sign in required.';
      notifyListeners();
      return;
    }
    item.status = UploadStatus.uploading;
    item.progress = 0;
    item.error = null;
    notifyListeners();
    try {
      final ref = FirebaseStorage.instance.ref(_buildPath(user.uid, item));
      final task = ref.putFile(File(item.path));
      task.snapshotEvents.listen((snapshot) {
        if (snapshot.totalBytes > 0) {
          item.progress = snapshot.bytesTransferred / snapshot.totalBytes;
          notifyListeners();
        }
      });
      await task;
      item.status = UploadStatus.done;
      item.evaluationStatus = EvaluationStatus.processing;
      item.evaluationSummary = 'Processing';
      notifyListeners();
      _onUploadComplete(item);
    } catch (e) {
      item.status = UploadStatus.error;
      item.error = e.toString();
      item.retryCount += 1;
      item.nextRetryAt = DateTime.now().add(Duration(seconds: 1 << item.retryCount.clamp(1, 5)));
      notifyListeners();
    }
  }

  Future<void> uploadAll() async {
    final items = queue.where((e) => e.status == UploadStatus.queued).toList();
    for (final item in items) {
      await uploadItem(item);
    }
  }

  String _buildPath(String uid, UploadItem item) {
    final today = DateTime.now();
    final day = '${today.year}${today.month.toString().padLeft(2, '0')}${today.day.toString().padLeft(2, '0')}';
    final prefix = item.type == UploadType.diet ? 'diet' : 'appearance';
    return 'users/$uid/$prefix/$day/${item.name}';
  }

  void _onUploadComplete(UploadItem item) {
    final messenger = OraApp.messengerKey.currentState;
    if (item.type == UploadType.diet) {
      AppShellController.instance.selectTab(1);
      messenger?.showSnackBar(
        SnackBar(content: Text('Diet upload complete. Sent for evaluation.')),
      );
    } else {
      AppShellController.instance.selectTab(2);
      messenger?.showSnackBar(
        SnackBar(content: Text('Appearance upload complete. Sent for evaluation.')),
      );
    }
    _simulateEvaluation(item);
  }

  void _simulateEvaluation(UploadItem item) {
    Future.delayed(const Duration(seconds: 2), () {
      item.evaluationStatus = EvaluationStatus.complete;
      item.evaluationSummary = item.type == UploadType.diet
          ? 'Macro balance: solid. Micros: fiber +, sodium ok.'
          : 'Appearance: posture +, symmetry ok. Style: cohesive.';
      _evaluations.add(UploadEvaluation(
        type: item.type,
        completedAt: DateTime.now(),
        summary: item.evaluationSummary ?? '',
      ));
      notifyListeners();
      if (item.type == UploadType.appearance) {
        _logAppearanceFeedback(item, item.evaluationSummary ?? 'Awaiting feedback.');
      }
    });
  }

  Future<void> _logAppearanceFeedback(UploadItem item, String summary) async {
    final repo = AppearanceRepo(AppDatabase.instance);
    final recent = await repo.getRecentEntries(limit: 200);
    final scores = _latestScoresFromEntries(recent);
    final now = DateTime.now();
    final category = await _inferAppearanceCategory(item, summary);
    final score = _scoreForCategory(scores, category);
    final imagePath = await _persistAppearanceImage(item.path, category);
    await repo.addEntry(
      createdAt: now,
      measurements: _buildFeedbackPayload(
        category: category,
        score: score,
        delta: 0,
        feedback: summary.trim(),
        uploadName: item.name,
      ),
      imagePath: imagePath,
    );
  }

  Future<String> _inferAppearanceCategory(UploadItem item, String summary) async {
    final settings = SettingsRepo(AppDatabase.instance);
    final enabled = await settings.getCloudEnabled();
    final apiKey = await settings.getCloudApiKey();
    final provider = await settings.getCloudProvider();
    final model = await settings.getCloudModel();
    if (!enabled || apiKey == null || apiKey.trim().isEmpty) {
      return 'skin';
    }
    try {
      final file = File(item.path);
      if (!await file.exists()) return 'skin';
      final category = await _appearanceAnalysis.classifyImage(
        file: file,
        provider: provider,
        apiKey: apiKey,
        model: model,
        summary: summary,
      );
      return category ?? 'skin';
    } catch (_) {
      return 'skin';
    }
  }

  double _scoreForCategory(_FeedbackScores scores, String category) {
    switch (category) {
      case 'physique':
        return scores.physique;
      case 'style':
        return scores.style;
      case 'skin':
      default:
        return scores.skin;
    }
  }

  Future<String?> _persistAppearanceImage(String path, String category) async {
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final persisted = await ImageDownscaler.persistImageToSubdir(file, 'appearance/$category');
      return persisted.path;
    } catch (_) {
      return null;
    }
  }

  _FeedbackScores _latestScoresFromEntries(List<AppearanceEntry> entries) {
    double skin = 50;
    double physique = 50;
    double style = 50;
    for (final entry in entries) {
      final raw = entry.measurements;
      if (raw == null || raw.toString().trim().isEmpty) continue;
      try {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) continue;
        if (decoded['type'] != 'feedback') continue;
        final category = decoded['category']?.toString();
        final score = _readScore(decoded['score']);
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
      } catch (_) {}
    }
    return _FeedbackScores(skin: skin, physique: physique, style: style);
  }

  double? _readScore(Object? raw) {
    if (raw is int) return raw.toDouble();
    if (raw is double) return raw;
    return double.tryParse(raw?.toString() ?? '');
  }

  String _buildFeedbackPayload({
    required String category,
    required double score,
    required int delta,
    required String feedback,
    required String uploadName,
  }) {
    return jsonEncode({
      'type': 'feedback',
      'category': category,
      'score': score.round(),
      'score_delta': delta,
      'feedback': feedback,
      'upload_name': uploadName,
    });
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

class UploadEvaluation {
  UploadEvaluation({
    required this.type,
    required this.completedAt,
    required this.summary,
  });

  final UploadType type;
  final DateTime completedAt;
  final String summary;
}
