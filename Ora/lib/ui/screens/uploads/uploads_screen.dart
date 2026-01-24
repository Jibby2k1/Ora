import 'package:flutter/material.dart';

import '../../../core/cloud/upload_service.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class UploadsScreen extends StatefulWidget {
  const UploadsScreen({super.key});

  @override
  State<UploadsScreen> createState() => _UploadsScreenState();
}

class _UploadsScreenState extends State<UploadsScreen> {
  final _uploadService = UploadService.instance;
  UploadStatus? _filter;

  @override
  void initState() {
    super.initState();
    _uploadService.addListener(_onUpdate);
  }

  @override
  void dispose() {
    _uploadService.removeListener(_onUpdate);
    super.dispose();
  }

  void _onUpdate() {
    if (!mounted) return;
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final queue = _filter == null
        ? _uploadService.queue
        : _uploadService.queue.where((e) => e.status == _filter).toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('Uploads'),
        actions: [
          TextButton(
            onPressed: _uploadService.uploadAll,
            child: const Text('Upload all'),
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
                padding: const EdgeInsets.all(12),
                child: Wrap(
                  spacing: 8,
                  children: [
                    _filterChip('All', null),
                    _filterChip('Queued', UploadStatus.queued),
                    _filterChip('Uploading', UploadStatus.uploading),
                    _filterChip('Done', UploadStatus.done),
                    _filterChip('Error', UploadStatus.error),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              if (queue.isEmpty)
                const GlassCard(
                  child: ListTile(
                    title: Text('No uploads queued'),
                    subtitle: Text('Add media from Diet or Appearance.'),
                  ),
                )
              else
                ...queue.map(_uploadTile),
            ],
          ),
        ],
      ),
    );
  }

  Widget _filterChip(String label, UploadStatus? status) {
    final selected = _filter == status;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) {
        setState(() {
          _filter = status;
        });
      },
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
    final typeLabel = item.type == UploadType.diet ? 'Diet' : 'Appearance';
    return GlassCard(
      child: Column(
        children: [
          ListTile(
            title: Text(item.name),
            subtitle: Text(
              '$typeLabel • $statusText${_nextRetryText(item)}${_evalText(item)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (item.status == UploadStatus.queued)
                  IconButton(
                    icon: const Icon(Icons.cloud_upload),
                    onPressed: () => _uploadService.uploadItem(item),
                  ),
                if (item.status == UploadStatus.error &&
                    (item.nextRetryAt == null ||
                        DateTime.now().isAfter(item.nextRetryAt!)))
                  IconButton(
                    icon: const Icon(Icons.refresh),
                    onPressed: () => _uploadService.uploadItem(item),
                  ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => _uploadService.remove(item),
                ),
              ],
            ),
          ),
          if (item.status == UploadStatus.uploading)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: LinearProgressIndicator(value: item.progress),
            ),
        ],
      ),
    );
  }

  String _nextRetryText(UploadItem item) {
    if (item.status != UploadStatus.error || item.nextRetryAt == null) return '';
    final seconds = item.nextRetryAt!.difference(DateTime.now()).inSeconds;
    if (seconds <= 0) return '';
    return ' • Retry in ${seconds}s';
  }

  String _evalText(UploadItem item) {
    if (item.evaluationStatus == EvaluationStatus.processing) {
      return ' • Evaluating';
    }
    if (item.evaluationStatus == EvaluationStatus.complete) {
      return ' • Evaluated';
    }
    return '';
  }
}
