import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:fl_chart/fl_chart.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/appearance_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../core/cloud/appearance_analysis_service.dart';
import '../../../core/utils/image_downscaler.dart';
import '../../../domain/models/appearance_entry.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../shell/app_shell_controller.dart';
import '../../../core/input/input_router.dart';
import '../../widgets/consent/cloud_consent.dart';

enum AppearanceAssessment { skin, physique, style }

class AppearanceScreen extends StatefulWidget {
  const AppearanceScreen({super.key});

  @override
  State<AppearanceScreen> createState() => _AppearanceScreenState();
}

class _AppearanceScreenState extends State<AppearanceScreen> {
  late final SettingsRepo _settingsRepo;
  late final AppearanceRepo _appearanceRepo;
  final AppearanceAnalysisService _appearanceAnalysis = AppearanceAnalysisService();
  bool _accessReady = false;
  AppearanceAssessment _assessment = AppearanceAssessment.physique;
  double _skinScore = 0;
  double _physiqueScore = 0;
  double _styleScore = 0;
  Color _physiqueColor = Colors.blue;
  Color _skinColor = Colors.purple;
  Color _styleColor = Colors.teal;
  String _selectedFeedbackCategory = 'skin';
  Future<List<AppearanceEntry>>? _timelineFuture;
  bool _handlingInput = false;
  Future<List<AppearanceEntry>>? _weightFuture;
  final TextEditingController _weightInputController = TextEditingController();
  String _weightUnit = 'lb';
  
  // Gemini API state
  String? _geminiResponse;
  bool _geminiLoading = false;
  String? _geminiError;
  final TextEditingController _adviceInputController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _appearanceRepo = AppearanceRepo(AppDatabase.instance);
    _ensureAccess();
    _refreshTimeline();
    _loadWeightUnit();
    AppShellController.instance.pendingInput.addListener(_handlePendingInput);
  }

  @override
  void dispose() {
    AppShellController.instance.pendingInput.removeListener(_handlePendingInput);
    _adviceInputController.dispose();
    _weightInputController.dispose();
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
      await _processAppearanceImage(event.file!);
    } else if ((dispatch.entity ?? event.text)?.trim().isNotEmpty == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Appearance logs require a photo upload.')),
      );
    }
    _handlingInput = false;
  }

  Future<void> _processAppearanceImage(File file) async {
    final consent = await CloudConsent.ensureAppearanceConsent(context, _settingsRepo);
    if (!consent || !mounted) return;
    final enabled = await _settingsRepo.getCloudEnabled();
    final apiKey = await _settingsRepo.getCloudApiKey();
    final provider = await _settingsRepo.getCloudProvider();
    final model = await _settingsRepo.getCloudModel();
    if (!enabled || apiKey == null || apiKey.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Cloud analysis requires an API key.')),
      );
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Analyzing appearance...')),
    );
    final result = await _appearanceAnalysis.analyzeImage(
      file: file,
      provider: provider,
      apiKey: apiKey,
      model: model,
    );
    if (!mounted) return;
    if (result == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to analyze appearance.')),
      );
      return;
    }
    final category = result.category;
    final persisted = await ImageDownscaler.persistImageToSubdir(
      file,
      'appearance/$category',
    );
    final recent = await _appearanceRepo.getRecentEntries(limit: 200);
    final scores = _latestScoresFromEntries(recent);
    final score = _scoreForCategory(scores, category);
    await _appearanceRepo.addEntry(
      createdAt: DateTime.now(),
      measurements: _buildFeedbackPayload(
        category: category,
        score: score,
        delta: 0,
        feedback: result.feedback,
        uploadName: file.uri.pathSegments.last,
      ),
      imagePath: persisted.path,
    );
    _refreshTimeline();
  }

  void _refreshTimeline() {
    setState(() {
      _timelineFuture = _appearanceRepo.getRecentEntries(limit: 30);
      _weightFuture = _appearanceRepo.getRecentEntries(limit: 120);
    });
    _refreshScores();
  }

  Future<void> _loadWeightUnit() async {
    final unit = await _settingsRepo.getUnit();
    if (!mounted) return;
    setState(() {
      _weightUnit = unit;
    });
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

  List<_WeightEntry> _weightEntriesFrom(List<AppearanceEntry> entries) {
    final results = <_WeightEntry>[];
    for (final entry in entries) {
      final data = _decodeMeasurements(entry.measurements);
      if (data['type'] != 'weight') continue;
      final value = _readScore(data['value']);
      if (value == null) continue;
      final unit = data['unit']?.toString() ?? _weightUnit;
      results.add(_WeightEntry(
        createdAt: entry.createdAt,
        weight: value,
        unit: unit,
      ));
    }
    results.sort((a, b) => a.createdAt.compareTo(b.createdAt));
    return results;
  }

  Future<void> _saveWeightEntry() async {
    final raw = _weightInputController.text.trim();
    if (raw.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter your weight.')),
      );
      return;
    }
    final value = double.tryParse(raw);
    if (value == null || value <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Enter a valid weight.')),
      );
      return;
    }
    await _appearanceRepo.addEntry(
      createdAt: DateTime.now(),
      measurements: jsonEncode({
        'type': 'weight',
        'value': value,
        'unit': _weightUnit,
      }),
    );
    if (!mounted) return;
    _weightInputController.clear();
    _refreshTimeline();
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

  Future<void> _requestGeminiAdvice(String category, String userInput) async {
    if (!mounted || userInput.trim().isEmpty) return;
    setState(() {
      _geminiLoading = true;
      _geminiError = null;
      _geminiResponse = null;
    });

    try {
      final prompt = '''You are a fitness and personal development coach.
The user wants advice on how to improve their $category.
User's request: "$userInput"

Provide a brief, practical assessment (2-3 sentences maximum) on how they can improve their $category.
Do NOT give advice on ways to change appearance in illegal, immoral, or unethical ways.
Focus only on practical, health-based improvements.
Remember: you are only giving guidance, the user will determine their own score.''';

      // For now, we'll use a simple HTTP request to Gemini API
      // In production, you'd want to get the API key from settings/secure storage
      final apiKey = ''; // TODO: Get from settings
      if (apiKey.isEmpty) {
        if (mounted) {
          setState(() {
            _geminiError = 'Gemini API key not configured. Please set it in settings.';
            _geminiLoading = false;
          });
        }
        return;
      }

      final uri = Uri.https(
        'generativelanguage.googleapis.com',
        '/v1beta/models/gemini-2.5-flash:generateContent',
        {'key': apiKey},
      );

      final payload = {
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': prompt}
            ],
          }
        ],
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 200,
        },
      };

      final response = await http
          .post(
            uri,
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 15));

      if (!mounted) return;

      if (response.statusCode >= 200 && response.statusCode < 300) {
        try {
          final data = jsonDecode(response.body) as Map<String, dynamic>;
          final candidates = data['candidates'] as List<dynamic>? ?? [];
          if (candidates.isNotEmpty) {
            final content = candidates.first['content'] as Map<String, dynamic>?;
            final parts = content?['parts'] as List<dynamic>? ?? [];
            if (parts.isNotEmpty) {
              final text = parts.first['text']?.toString() ?? '';
              setState(() {
                _geminiResponse = text;
                _geminiLoading = false;
              });
              return;
            }
          }
          setState(() {
            _geminiError = 'No response from Gemini API.';
            _geminiLoading = false;
          });
        } catch (e) {
          setState(() {
            _geminiError = 'Failed to parse Gemini response: $e';
            _geminiLoading = false;
          });
        }
      } else {
        setState(() {
          _geminiError = 'Gemini API error: ${response.statusCode}';
          _geminiLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _geminiError = 'Request failed: $e';
          _geminiLoading = false;
        });
      }
    }
  }

  Widget _buildAssessmentCard() {
    final categoryName = _assessment.toString().split('.').last;
    final categoryDisplay = categoryName[0].toUpperCase() + categoryName.substring(1);

    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Advice for $categoryDisplay'),
          const SizedBox(height: 12),
          TextField(
            controller: _adviceInputController,
            decoration: InputDecoration(
              hintText: 'What advice would you like to improve your $categoryDisplay?',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            maxLines: 3,
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: _geminiLoading
                  ? null
                  : () => _requestGeminiAdvice(categoryName, _adviceInputController.text),
              child: _geminiLoading
                  ? const SizedBox(
                      height: 16,
                      width: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Get Advice'),
            ),
          ),
          if (_geminiError != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withOpacity(0.3)),
              ),
              child: Text(
                _geminiError!,
                style: TextStyle(color: Colors.red[700], fontSize: 13),
              ),
            ),
          ],
          if (_geminiResponse != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.withOpacity(0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Advice:',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _geminiResponse!,
                    style: const TextStyle(fontSize: 13, height: 1.5),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.05),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'ⓘ This AI will not give advice on illegal, immoral, or unethical ways to change appearance. Focus is on treatable improvements only.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontSize: 11,
                    color: Colors.amber[900],
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFeedbackHistoryCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Feedback History'),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'skin', label: Text('Skin')),
              ButtonSegment(value: 'physique', label: Text('Physique')),
              ButtonSegment(value: 'style', label: Text('Style')),
            ],
            selected: {_selectedFeedbackCategory},
            onSelectionChanged: (value) {
              setState(() {
                _selectedFeedbackCategory = value.first;
              });
            },
          ),
          const SizedBox(height: 12),
          FutureBuilder<List<AppearanceEntry>>(
            future: _timelineFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = snapshot.data ?? [];
              final filtered = entries.where((entry) {
                final data = _decodeMeasurements(entry.measurements);
                return data['type'] == 'feedback' && data['category'] == _selectedFeedbackCategory;
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
                            imageFile!,
                            height: 160,
                            width: double.infinity,
                            fit: BoxFit.cover,
                          ),
                        ),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(
                          feedback == null || feedback.isEmpty ? 'Feedback logged.' : feedback,
                        ),
                        subtitle: meta.isEmpty ? null : Text(meta),
                        trailing: Text(_formatDate(entry.createdAt), style: Theme.of(context).textTheme.bodySmall),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                }).toList(),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildWeightTrackerCard() {
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Weight Tracker'),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _weightInputController,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: InputDecoration(
                    hintText: 'Enter weight',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_weightUnit),
              ),
              const SizedBox(width: 8),
              FilledButton(
                onPressed: _saveWeightEntry,
                child: const Text('Save'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<AppearanceEntry>>(
            future: _weightFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final entries = _weightEntriesFrom(snapshot.data ?? []);
              if (entries.isEmpty) {
                return const Text('No weight entries yet.');
              }
              final latest = entries.last;
              final minWeight = entries.map((e) => e.weight).reduce((a, b) => a < b ? a : b);
              final maxWeight = entries.map((e) => e.weight).reduce((a, b) => a > b ? a : b);
              final spots = entries.asMap().entries.map((entry) {
                return FlSpot(entry.key.toDouble(), entry.value.weight);
              }).toList();
              final labelStyle = Theme.of(context).textTheme.bodySmall?.copyWith(fontSize: 11);
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Latest: ${latest.weight.toStringAsFixed(1)} ${latest.unit}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 160,
                    child: LineChart(
                      LineChartData(
                        minY: minWeight - 2,
                        maxY: maxWeight + 2,
                        gridData: FlGridData(show: false),
                        borderData: FlBorderData(show: false),
                        titlesData: FlTitlesData(
                          leftTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              reservedSize: 36,
                              getTitlesWidget: (value, meta) {
                                final label = value.toStringAsFixed(0);
                                return Text(label, style: labelStyle);
                              },
                            ),
                          ),
                          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                          bottomTitles: AxisTitles(
                            sideTitles: SideTitles(
                              showTitles: true,
                              interval: entries.length <= 1 ? 1 : (entries.length - 1).toDouble(),
                              getTitlesWidget: (value, meta) {
                                final index = value.round().clamp(0, entries.length - 1);
                                final date = entries[index].createdAt;
                                return Text('${date.month}/${date.day}', style: labelStyle);
                              },
                            ),
                          ),
                        ),
                        lineBarsData: [
                          LineChartBarData(
                            spots: spots,
                            isCurved: true,
                            color: Theme.of(context).colorScheme.primary,
                            barWidth: 2,
                            dotData: FlDotData(show: entries.length <= 12),
                            belowBarData: BarAreaData(
                              show: true,
                              color: Theme.of(context).colorScheme.primary.withOpacity(0.12),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'History',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const SizedBox(height: 8),
                  Column(
                    children: entries.reversed.take(6).map((entry) {
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Row(
                          children: [
                            Text(
                              '${entry.weight.toStringAsFixed(1)} ${entry.unit}',
                              style: Theme.of(context).textTheme.bodyMedium,
                            ),
                            const Spacer(),
                            Text(
                              _formatDate(entry.createdAt),
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                          ],
                        ),
                      );
                    }).toList(),
                  ),
                ],
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
              physiqueColor: _physiqueColor,
              skinColor: _skinColor,
              styleColor: _styleColor,
              selectedAssessment: _assessment,
              onPhysiqueColorChanged: (color) => setState(() => _physiqueColor = color),
              onSkinColorChanged: (color) => setState(() => _skinColor = color),
              onStyleColorChanged: (color) => setState(() => _styleColor = color),
              onAssessmentChanged: (assessment) => setState(() => _assessment = assessment),
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
              _buildAssessmentCard(),
              const SizedBox(height: 12),
              _buildProgressRingsCard(),
              const SizedBox(height: 12),
              _buildWeightTrackerCard(),
              const SizedBox(height: 12),
              _buildFeedbackHistoryCard(),
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

class _WeightEntry {
  _WeightEntry({
    required this.createdAt,
    required this.weight,
    required this.unit,
  });

  final DateTime createdAt;
  final double weight;
  final String unit;
}

class _StackedRings extends StatelessWidget {
  const _StackedRings({
    required this.skin,
    required this.physique,
    required this.style,
    required this.physiqueColor,
    required this.skinColor,
    required this.styleColor,
    required this.selectedAssessment,
    required this.onPhysiqueColorChanged,
    required this.onSkinColorChanged,
    required this.onStyleColorChanged,
    required this.onAssessmentChanged,
  });

  final double skin;
  final double physique;
  final double style;
  final Color physiqueColor;
  final Color skinColor;
  final Color styleColor;
  final AppearanceAssessment selectedAssessment;
  final ValueChanged<Color> onPhysiqueColorChanged;
  final ValueChanged<Color> onSkinColorChanged;
  final ValueChanged<Color> onStyleColorChanged;
  final ValueChanged<AppearanceAssessment> onAssessmentChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Rings
        SizedBox(
          height: 140,
          width: 140,
          child: CustomPaint(
            painter: _RingsPainter(
              skin: skin.clamp(0.0, 1.0),
              physique: physique.clamp(0.0, 1.0),
              style: style.clamp(0.0, 1.0),
              skinColor: skinColor,
              physiqueColor: physiqueColor,
              styleColor: styleColor,
              selectedAssessment: selectedAssessment,
            ),
          ),
        ),
        const SizedBox(width: 24),
        // Legend
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _LegendItem(
              color: physiqueColor,
              label: 'Physique',
              value: (physique * 100).round(),
              onColorChanged: onPhysiqueColorChanged,
              isHighlighted: selectedAssessment == AppearanceAssessment.physique,
              onButtonPressed: () => onAssessmentChanged(AppearanceAssessment.physique),
            ),
            const SizedBox(height: 12),
            _LegendItem(
              color: skinColor,
              label: 'Skin',
              value: (skin * 100).round(),
              onColorChanged: onSkinColorChanged,
              isHighlighted: selectedAssessment == AppearanceAssessment.skin,
              onButtonPressed: () => onAssessmentChanged(AppearanceAssessment.skin),
            ),
            const SizedBox(height: 12),
            _LegendItem(
              color: styleColor,
              label: 'Style',
              value: (style * 100).round(),
              onColorChanged: onStyleColorChanged,
              isHighlighted: selectedAssessment == AppearanceAssessment.style,
              onButtonPressed: () => onAssessmentChanged(AppearanceAssessment.style),
            ),
          ],
        ),
      ],
    );
  }
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({
    required this.color,
    required this.label,
    required this.value,
    required this.onColorChanged,
    required this.onButtonPressed,
    this.isHighlighted = false,
  });

  final Color color;
  final String label;
  final int value;
  final ValueChanged<Color> onColorChanged;
  final VoidCallback onButtonPressed;
  final bool isHighlighted;

  void _showColorPicker(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ColorPickerSheet(
        initialColor: color,
        label: label,
        onColorSelected: onColorChanged,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      padding: EdgeInsets.all(isHighlighted ? 4 : 0),
      decoration: BoxDecoration(
        color: isHighlighted ? color.withOpacity(0.1) : Colors.transparent,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Color value box (clickable)
          GestureDetector(
            onTap: () => _showColorPicker(context),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: color.withOpacity(isHighlighted ? 1.0 : 0.85),
                borderRadius: BorderRadius.circular(6),
                boxShadow: isHighlighted
                    ? [BoxShadow(color: color.withOpacity(0.4), blurRadius: 8, spreadRadius: 1)]
                    : null,
              ),
              child: Text(
                '$value',
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Label + Button (same width as value box)
          GestureDetector(
            onTap: onButtonPressed,
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: isHighlighted ? color.withOpacity(0.2) : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: isHighlighted ? color : Colors.grey.withOpacity(0.3),
                  width: isHighlighted ? 1.5 : 1,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  fontWeight: isHighlighted ? FontWeight.w700 : FontWeight.w500,
                  fontSize: 13,
                  color: isHighlighted ? color : Theme.of(context).textTheme.bodyMedium?.color,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ColorPickerSheet extends StatefulWidget {
  const _ColorPickerSheet({
    required this.initialColor,
    required this.label,
    required this.onColorSelected,
  });

  final Color initialColor;
  final String label;
  final ValueChanged<Color> onColorSelected;

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _selectedColor;
  late TextEditingController _valueController;
  late TextEditingController _notesController;

  static const List<Color> _presetColors = [
    Colors.red,
    Colors.pink,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.brown,
    Colors.grey,
    Colors.blueGrey,
  ];

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _valueController = TextEditingController(text: '50');
    _notesController = TextEditingController();
  }

  @override
  void dispose() {
    _valueController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenHeight = MediaQuery.of(context).size.height;

    return Container(
      height: screenHeight * 0.85,
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${widget.label} Color',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: _selectedColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  ),
                ),
              ],
            ),
          ),
          // Scrollable content
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              children: [
                // Preset colors
                const Text(
                  'Select Color',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 10,
                  runSpacing: 10,
                  children: _presetColors.map((color) {
                    final isSelected = _selectedColor.value == color.value;
                    return GestureDetector(
                      onTap: () {
                        setState(() {
                          _selectedColor = color;
                        });
                      },
                      child: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(8),
                          border: isSelected
                              ? Border.all(color: Colors.white, width: 3)
                              : Border.all(color: Colors.grey.withOpacity(0.3)),
                          boxShadow: isSelected
                              ? [BoxShadow(color: color.withOpacity(0.5), blurRadius: 8)]
                              : null,
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                // Enter Value input
                const Text(
                  'Enter Value (0-100)',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _valueController,
                  decoration: InputDecoration(
                    hintText: 'Enter value',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    counterText: '',
                  ),
                  keyboardType: const TextInputType.numberWithOptions(decimal: false),
                  maxLength: 3,
                  onChanged: (value) {
                    final parsed = int.tryParse(value);
                    if (parsed != null && parsed >= 0 && parsed <= 100) {
                      // Value is valid
                    }
                  },
                ),
                const SizedBox(height: 20),
                // Notes section
                const Text(
                  'Notes',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _notesController,
                  decoration: InputDecoration(
                    hintText: 'Add personal notes about your ${widget.label}...',
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    alignLabelWithHint: true,
                  ),
                  maxLines: 6,
                  minLines: 4,
                ),
                const SizedBox(height: 20),
              ],
            ),
          ),
          // Buttons
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.of(context).pop(),
                    child: const Text('Close'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () {
                      widget.onColorSelected(_selectedColor);
                      Navigator.of(context).pop();
                    },
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _RingsPainter extends CustomPainter {
  _RingsPainter({
    required this.skin,
    required this.physique,
    required this.style,
    required this.skinColor,
    required this.physiqueColor,
    required this.styleColor,
    required this.selectedAssessment,
  });

  final double skin;
  final double physique;
  final double style;
  final Color skinColor;
  final Color physiqueColor;
  final Color styleColor;
  final AppearanceAssessment selectedAssessment;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    const startAngle = -3.14159 / 2; // Start from top

    // Ring configurations (outermost to innermost)
    final rings = [
      (radius: size.width / 2 - 8, value: physique, color: physiqueColor, assessment: AppearanceAssessment.physique),
      (radius: size.width / 2 - 28, value: skin, color: skinColor, assessment: AppearanceAssessment.skin),
      (radius: size.width / 2 - 48, value: style, color: styleColor, assessment: AppearanceAssessment.style),
    ];

    for (final ring in rings) {
      final isSelected = ring.assessment == selectedAssessment;
      final strokeWidth = isSelected ? 18.0 : 12.0;
      final bgOpacity = isSelected ? 0.2 : 0.1;
      final progressOpacity = isSelected ? 1.0 : 0.7;

      // Background track
      final bgPaint = Paint()
        ..color = ring.color.withOpacity(bgOpacity)
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.round;

      canvas.drawCircle(center, ring.radius, bgPaint);

      // Progress arc
      if (ring.value > 0) {
        final progressPaint = Paint()
          ..color = ring.color.withOpacity(progressOpacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = strokeWidth
          ..strokeCap = StrokeCap.round;

        final sweepAngle = 2 * 3.14159 * ring.value;
        canvas.drawArc(
          Rect.fromCircle(center: center, radius: ring.radius),
          startAngle,
          sweepAngle,
          false,
          progressPaint,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_RingsPainter oldDelegate) {
    return skin != oldDelegate.skin ||
        physique != oldDelegate.physique ||
        style != oldDelegate.style ||
        skinColor != oldDelegate.skinColor ||
        physiqueColor != oldDelegate.physiqueColor ||
        styleColor != oldDelegate.styleColor ||
        selectedAssessment != oldDelegate.selectedAssessment;
  }
}
