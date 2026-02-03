import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../../core/cloud/diet_analysis_service.dart';
import '../../../data/repositories/diet_repo.dart';
import '../../../domain/models/diet_entry.dart';

class FoodBarcodeScannerPage extends StatefulWidget {
  const FoodBarcodeScannerPage({super.key, required this.dietRepo});

  static Future<DietEstimate?> show(
    BuildContext context, {
    required DietRepo dietRepo,
  }) {
    return Navigator.of(context).push<DietEstimate>(
      MaterialPageRoute(
        builder: (_) => FoodBarcodeScannerPage(dietRepo: dietRepo),
      ),
    );
  }

  final DietRepo dietRepo;

  @override
  State<FoodBarcodeScannerPage> createState() => _FoodBarcodeScannerPageState();
}

class _FoodBarcodeScannerPageState extends State<FoodBarcodeScannerPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );
  final OpenFoodFactsClient _client = OpenFoodFactsClient();

  FoodBarcodeResult? _result;
  String? _error;
  String? _barcode;
  bool _loading = false;
  int _duplicateCount = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _handleDetect(BarcodeCapture capture) async {
    if (_loading || _result != null) return;
    if (capture.barcodes.isEmpty) return;
    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;
    setState(() {
      _barcode = value;
      _error = null;
      _loading = true;
    });
    await _controller.stop();
    final result = await _client.lookup(value);
    if (!mounted) return;
    if (result == null) {
      setState(() {
        _error = 'No nutrition data found for this barcode.';
        _loading = false;
      });
      await _controller.start();
      return;
    }
    final duplicateInfo = await _checkDuplicate(value);
    final withBarcode = result.withBarcode(value);
    await _signalScanSuccess();
    setState(() {
      _result = withBarcode;
      _duplicateCount = duplicateInfo.count;
      _loading = false;
    });
  }

  Future<void> _scanAgain() async {
    setState(() {
      _result = null;
      _error = null;
      _barcode = null;
      _loading = false;
      _duplicateCount = 0;
    });
    await _controller.start();
  }

  Future<void> _signalScanSuccess() async {
    await HapticFeedback.mediumImpact();
    SystemSound.play(SystemSoundType.click);
  }

  Future<_DuplicateInfo> _checkDuplicate(String barcode) async {
    try {
      final entries = await widget.dietRepo.getEntriesForDay(DateTime.now());
      var count = 0;
      for (final entry in entries) {
        if (_notesHasBarcode(entry.notes, barcode)) {
          count++;
        }
      }
      return _DuplicateInfo(found: count > 0, count: count);
    } catch (_) {
      return const _DuplicateInfo(found: false, count: 0);
    }
  }

  bool _notesHasBarcode(String? notes, String barcode) {
    if (notes == null || notes.isEmpty) return false;
    return notes.contains(_barcodeTag(barcode));
  }

  Future<void> _manualEntry() async {
    final estimate = await showModalBottomSheet<DietEstimate>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return _ManualEntrySheet(barcode: _barcode);
      },
    );
    if (!mounted || estimate == null) return;
    Navigator.of(context).pop(estimate);
  }

  Future<void> _showDuplicateEntries() async {
    final barcode = _barcode;
    if (barcode == null || barcode.isEmpty) return;
    final entries = await widget.dietRepo.getEntriesForDay(DateTime.now());
    final matches =
        entries.where((entry) => _notesHasBarcode(entry.notes, barcode)).toList();
    if (!mounted) return;
    if (matches.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No entries found for this barcode today.')),
      );
      return;
    }
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return _DuplicateEntriesSheet(entries: matches);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan barcode'),
        actions: [
          ValueListenableBuilder<MobileScannerState>(
            valueListenable: _controller,
            builder: (context, state, _) {
              final torchState = state.torchState;
              final isAvailable = torchState != TorchState.unavailable;
              final icon = torchState == TorchState.on ? Icons.flash_on : Icons.flash_off;
              return IconButton(
                onPressed: isAvailable ? () => _controller.toggleTorch() : null,
                icon: Icon(icon),
                tooltip: isAvailable ? 'Toggle torch' : 'Torch unavailable',
              );
            },
          ),
          if (result != null)
            IconButton(
              onPressed: _scanAgain,
              icon: const Icon(Icons.refresh),
              tooltip: 'Scan again',
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _handleDetect,
                ),
                const Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _ScannerOverlayPainter(),
                    ),
                  ),
                ),
                if (result == null)
                  Positioned(
                    left: 16,
                    right: 16,
                    bottom: 16,
                    child: _ZoomSlider(
                      controller: _controller,
                    ),
                  ),
                Align(
                  alignment: Alignment.topCenter,
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: _StatusBanner(
                      loading: _loading,
                      barcode: _barcode,
                      error: _error,
                      hasResult: result != null,
                      duplicateCount: _duplicateCount,
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (result != null)
            _ResultSheet(
              result: result,
              duplicateCount: _duplicateCount,
              onUse: () => Navigator.of(context).pop(result.estimate),
              onRescan: _scanAgain,
              onViewDuplicates: _duplicateCount > 0 ? _showDuplicateEntries : null,
            )
          else
            _HelpFooter(
              onCancel: () => Navigator.of(context).pop(),
              onManualEntry: _error != null ? _manualEntry : null,
            ),
        ],
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.loading,
    required this.barcode,
    required this.error,
    required this.hasResult,
    required this.duplicateCount,
  });

  final bool loading;
  final String? barcode;
  final String? error;
  final bool hasResult;
  final int duplicateCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    String message;
    if (loading) {
      message = barcode == null ? 'Looking up barcode...' : 'Looking up $barcode...';
    } else if (error != null) {
      message = error!;
    } else if (hasResult) {
      if (duplicateCount > 0) {
        message = 'Already logged today ($duplicateCount).';
      } else {
        message = 'Product found.';
      }
    } else {
      message = 'Align the barcode inside the frame.';
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withAlpha(217),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          message,
          style: theme.textTheme.bodySmall,
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class _HelpFooter extends StatelessWidget {
  const _HelpFooter({required this.onCancel, this.onManualEntry});

  final VoidCallback onCancel;
  final VoidCallback? onManualEntry;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Text(
                'Tip: use good lighting for faster scans.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            if (onManualEntry != null)
              TextButton(
                onPressed: onManualEntry,
                child: const Text('Manual entry'),
              ),
            TextButton(
              onPressed: onCancel,
              child: const Text('Close'),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultSheet extends StatelessWidget {
  const _ResultSheet({
    required this.result,
    required this.duplicateCount,
    required this.onUse,
    required this.onRescan,
    required this.onViewDuplicates,
  });

  final FoodBarcodeResult result;
  final int duplicateCount;
  final VoidCallback onUse;
  final VoidCallback onRescan;
  final VoidCallback? onViewDuplicates;

  @override
  Widget build(BuildContext context) {
    final estimate = result.estimate;
    final micros = estimate.micros ?? const {};
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (duplicateCount > 0) ...[
              Text(
                'Logged today: $duplicateCount time${duplicateCount == 1 ? '' : 's'}.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
            ],
            if (result.imageUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  result.imageUrl!,
                  height: 140,
                  width: double.infinity,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(height: 8),
            ],
            Text(
              result.displayName,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (result.perServingLabel != null) ...[
              const SizedBox(height: 4),
              Text(
                result.perServingLabel!,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: 8),
            _ResultRow(label: 'Calories', value: estimate.calories),
            _ResultRow(label: 'Protein (g)', value: estimate.proteinG),
            _ResultRow(label: 'Carbs (g)', value: estimate.carbsG),
            _ResultRow(label: 'Fat (g)', value: estimate.fatG),
            _ResultRow(label: 'Fiber (g)', value: estimate.fiberG),
            _ResultRow(label: 'Sodium (mg)', value: estimate.sodiumMg),
            if (micros.isNotEmpty) ...[
              const SizedBox(height: 8),
              const Text('Micros'),
              const SizedBox(height: 4),
              ...micros.entries.map((entry) {
                return Text('${entry.key}: ${entry.value.toStringAsFixed(1)}');
              }),
            ],
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ElevatedButton.icon(
                  onPressed: onUse,
                  icon: const Icon(Icons.add),
                  label: const Text('Add to day'),
                ),
                if (onViewDuplicates != null)
                  OutlinedButton.icon(
                    onPressed: onViewDuplicates,
                    icon: const Icon(Icons.list),
                    label: const Text('View today'),
                  ),
                OutlinedButton(
                  onPressed: onRescan,
                  child: const Text('Scan again'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.label, required this.value});

  final String label;
  final double? value;

  @override
  Widget build(BuildContext context) {
    return Text('$label: ${value?.toStringAsFixed(1) ?? '-'}');
  }
}

class FoodBarcodeResult {
  FoodBarcodeResult({
    required this.estimate,
    required this.displayName,
    this.imageUrl,
    this.perServingLabel,
  });

  final DietEstimate estimate;
  final String displayName;
  final String? imageUrl;
  final String? perServingLabel;

  FoodBarcodeResult withBarcode(String barcode) {
    final taggedNotes = _attachBarcodeNote(estimate.notes, barcode);
    return FoodBarcodeResult(
      estimate: DietEstimate(
        mealName: estimate.mealName,
        calories: estimate.calories,
        proteinG: estimate.proteinG,
        carbsG: estimate.carbsG,
        fatG: estimate.fatG,
        fiberG: estimate.fiberG,
        sodiumMg: estimate.sodiumMg,
        micros: estimate.micros,
        notes: taggedNotes,
      ),
      displayName: displayName,
      imageUrl: imageUrl,
      perServingLabel: perServingLabel,
    );
  }
}

class OpenFoodFactsClient {
  static const String _host = 'world.openfoodfacts.net';

  Future<FoodBarcodeResult?> lookup(String barcode) async {
    final uri = Uri.https(
      _host,
      '/api/v2/product/$barcode',
      {
        'fields':
            'product_name,brands,serving_size,quantity,nutriments,image_url,image_front_url',
      },
    );
    http.Response response;
    try {
      response = await http.get(
        uri,
        headers: const {
          'User-Agent': 'Ora/0.1 (support@ora.app)',
        },
      );
    } catch (_) {
      return null;
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      return null;
    }
    try {
      final data = jsonDecode(response.body) as Map<String, dynamic>;
      if (data['status'] != 1) return null;
      final product = data['product'] as Map<String, dynamic>? ?? {};
      final nutriments = product['nutriments'] as Map<String, dynamic>? ?? {};
      final mealName = _buildName(product, barcode);
      final servingSize = product['serving_size']?.toString().trim();
      final useServing = _hasServingValues(nutriments);

      final calories = _readCalories(nutriments, useServing);
      final protein = _readNutrient(nutriments, 'proteins', useServing);
      final carbs = _readNutrient(nutriments, 'carbohydrates', useServing);
      final fat = _readNutrient(nutriments, 'fat', useServing);
      final fiber = _readNutrient(nutriments, 'fiber', useServing);
      final sodium = _readSodiumMg(nutriments, useServing);
      final micros = _readMicros(nutriments, useServing);

      final perServingLabel = useServing && servingSize != null && servingSize.isNotEmpty
          ? 'Per serving ($servingSize)'
          : (useServing ? 'Per serving' : 'Per 100 g');

      final estimate = DietEstimate(
        mealName: mealName,
        calories: calories,
        proteinG: protein,
        carbsG: carbs,
        fatG: fat,
        fiberG: fiber,
        sodiumMg: sodium,
        micros: micros.isEmpty ? null : micros,
        notes: 'Source: Open Food Facts ($perServingLabel)',
      );

      final imageUrl =
          product['image_front_url']?.toString() ?? product['image_url']?.toString();

      return FoodBarcodeResult(
        estimate: estimate,
        displayName: mealName,
        imageUrl: imageUrl?.isEmpty == true ? null : imageUrl,
        perServingLabel: perServingLabel,
      );
    } catch (_) {
      return null;
    }
  }

  String _buildName(Map<String, dynamic> product, String barcode) {
    final name = product['product_name']?.toString().trim();
    final brands = product['brands']?.toString().trim();
    if (name != null && name.isNotEmpty) {
      if (brands != null && brands.isNotEmpty) {
        final primaryBrand = brands.split(',').first.trim();
        if (primaryBrand.isNotEmpty) {
          return '$name - $primaryBrand';
        }
      }
      return name;
    }
    return 'Barcode $barcode';
  }

  bool _hasServingValues(Map<String, dynamic> nutriments) {
    return nutriments.keys.any((key) => key.endsWith('_serving'));
  }

  double? _readCalories(Map<String, dynamic> nutriments, bool useServing) {
    final suffix = useServing ? '_serving' : '_100g';
    final kcal = _readValue(nutriments, 'energy-kcal$suffix') ??
        _readValue(nutriments, 'energy_kcal$suffix');
    if (kcal != null) return kcal;
    final energy = _readValue(nutriments, 'energy$suffix');
    if (energy == null) return null;
    final unit = _readUnit(nutriments, 'energy');
    if (unit == null) return energy;
    final normalized = unit.replaceAll('\u00b5', 'u');
    final lower = normalized.toLowerCase();
    if (lower == 'kj' || lower == 'kJ') {
      return energy / 4.184;
    }
    return energy;
  }

  double? _readNutrient(Map<String, dynamic> nutriments, String base, bool useServing) {
    final suffix = useServing ? '_serving' : '_100g';
    return _readValue(nutriments, '$base$suffix');
  }

  double? _readSodiumMg(Map<String, dynamic> nutriments, bool useServing) {
    final suffix = useServing ? '_serving' : '_100g';
    final value = _readValue(nutriments, 'sodium$suffix');
    if (value == null) return null;
    final unit = _readUnit(nutriments, 'sodium');
    return _convertToMg(value, unit);
  }

  Map<String, double> _readMicros(Map<String, dynamic> nutriments, bool useServing) {
    final micros = <String, double>{};
    void addMicro(String apiKey, String label) {
      final value = _readNutrientVariant(nutriments, apiKey, useServing);
      if (value == null) return;
      final unit = _readUnit(nutriments, apiKey);
      micros[label] = _convertToMg(value, unit);
    }

    addMicro('potassium', 'potassium_mg');
    addMicro('calcium', 'calcium_mg');
    addMicro('iron', 'iron_mg');
    addMicro('vitamin-a', 'vitamin_a_mg');
    addMicro('vitamin-c', 'vitamin_c_mg');
    addMicro('vitamin-d', 'vitamin_d_mg');
    addMicro('vitamin-b12', 'vitamin_b12_mg');

    return micros;
  }

  double? _readNutrientVariant(
    Map<String, dynamic> nutriments,
    String base,
    bool useServing,
  ) {
    final suffix = useServing ? '_serving' : '_100g';
    final value = _readValue(nutriments, '$base$suffix');
    if (value != null) return value;
    final alt = base.replaceAll('-', '_');
    if (alt == base) return null;
    return _readValue(nutriments, '$alt$suffix');
  }

  double _convertToMg(double value, String? unit) {
    if (unit == null) return value;
    final normalized = unit.replaceAll('\u00b5', 'u');
    final lower = normalized.toLowerCase();
    if (lower == 'g') return value * 1000;
    if (lower == 'mg') return value;
    if (lower == 'ug' || lower == 'mcg') return value / 1000;
    return value;
  }

  double? _readValue(Map<String, dynamic> nutriments, String key) {
    final value = nutriments[key];
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }

  String? _readUnit(Map<String, dynamic> nutriments, String base) {
    final unitKey = '${base}_unit';
    if (nutriments[unitKey] != null) return nutriments[unitKey].toString();
    final alt = base.replaceAll('-', '_');
    final altKey = '${alt}_unit';
    if (nutriments[altKey] != null) return nutriments[altKey].toString();
    return null;
  }
}

class _ScannerOverlayPainter extends CustomPainter {
  const _ScannerOverlayPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final overlayPaint = Paint()
      ..color = Colors.black.withAlpha(90)
      ..style = PaintingStyle.fill;
    final framePaint = Paint()
      ..color = Colors.white.withAlpha(220)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3;

    final frameWidth = size.width * 0.78;
    final frameHeight = frameWidth * 0.6;
    final left = (size.width - frameWidth) / 2;
    final top = (size.height - frameHeight) / 2;
    final frameRect = Rect.fromLTWH(left, top, frameWidth, frameHeight);

    final path = Path()
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)))
      ..fillType = PathFillType.evenOdd;

    canvas.drawPath(path, overlayPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(16)), framePaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _ManualEntrySheet extends StatefulWidget {
  const _ManualEntrySheet({this.barcode});

  final String? barcode;

  @override
  State<_ManualEntrySheet> createState() => _ManualEntrySheetState();
}

class _ManualEntrySheetState extends State<_ManualEntrySheet> {
  final _nameController = TextEditingController();
  final _caloriesController = TextEditingController();
  final _proteinController = TextEditingController();
  final _carbsController = TextEditingController();
  final _fatController = TextEditingController();

  @override
  void dispose() {
    _nameController.dispose();
    _caloriesController.dispose();
    _proteinController.dispose();
    _carbsController.dispose();
    _fatController.dispose();
    super.dispose();
  }

  double? _parseDouble(String text) {
    final trimmed = text.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text('Manual entry'),
              const SizedBox(height: 12),
              TextField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Food name'),
                autofocus: true,
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _caloriesController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Calories'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _proteinController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Protein (g)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _carbsController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Carbs (g)'),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: _fatController,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(labelText: 'Fat (g)'),
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: () {
                    final name = _nameController.text.trim();
                    if (name.isEmpty) return;
                    final notes = _attachBarcodeNote('Manual barcode entry', widget.barcode);
                    Navigator.of(context).pop(
                      DietEstimate(
                        mealName: name,
                        calories: _parseDouble(_caloriesController.text),
                        proteinG: _parseDouble(_proteinController.text),
                        carbsG: _parseDouble(_carbsController.text),
                        fatG: _parseDouble(_fatController.text),
                        notes: notes,
                      ),
                    );
                  },
                  icon: const Icon(Icons.save),
                  label: const Text('Use values'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DuplicateEntriesSheet extends StatelessWidget {
  const _DuplicateEntriesSheet({required this.entries});

  final List<DietEntry> entries;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
        left: 16,
        right: 16,
        top: 24,
      ),
      child: Material(
        color: Colors.transparent,
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius: BorderRadius.circular(16),
          ),
          child: ListView(
            shrinkWrap: true,
            children: [
              const Text("Today's entries"),
              const SizedBox(height: 12),
              ...entries.map((entry) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(entry.mealName),
                  subtitle: Text(_formatEntry(entry)),
                );
              }),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ZoomSlider extends StatelessWidget {
  const _ZoomSlider({required this.controller});

  final MobileScannerController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ValueListenableBuilder<MobileScannerState>(
      valueListenable: controller,
      builder: (context, state, _) {
        final zoom = state.zoomScale.clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withAlpha(220),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: [
                const Icon(Icons.zoom_in),
                Expanded(
                  child: Slider(
                    min: 0.0,
                    max: 1.0,
                    value: zoom,
                    onChanged: (value) => controller.setZoomScale(value),
                  ),
                ),
                const Icon(Icons.zoom_out),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _DuplicateInfo {
  const _DuplicateInfo({required this.found, required this.count});

  final bool found;
  final int count;
}

String _barcodeTag(String barcode) => '[barcode:$barcode]';

String? _attachBarcodeNote(String? base, String? barcode) {
  if (barcode == null || barcode.trim().isEmpty) return base;
  final tag = _barcodeTag(barcode.trim());
  if (base == null || base.trim().isEmpty) return tag;
  if (base.contains(tag)) return base;
  return '$base $tag';
}

String _formatEntry(DietEntry entry) {
  final parts = <String>[];
  if (entry.calories != null) parts.add('${entry.calories!.toStringAsFixed(0)} kcal');
  if (entry.proteinG != null) parts.add('P ${entry.proteinG!.toStringAsFixed(1)}g');
  if (entry.carbsG != null) parts.add('C ${entry.carbsG!.toStringAsFixed(1)}g');
  if (entry.fatG != null) parts.add('F ${entry.fatG!.toStringAsFixed(1)}g');
  if (parts.isEmpty) return 'No macros logged.';
  return parts.join(' - ');
}
