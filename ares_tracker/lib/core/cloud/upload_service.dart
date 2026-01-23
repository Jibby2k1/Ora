import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../app.dart';
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
    final messenger = AresApp.messengerKey.currentState;
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
    });
  }
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
