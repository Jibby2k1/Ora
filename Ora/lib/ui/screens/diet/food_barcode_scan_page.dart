import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

class FoodBarcodeScanPage extends StatefulWidget {
  const FoodBarcodeScanPage({super.key});

  static Future<String?> show(BuildContext context) {
    return Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => const FoodBarcodeScanPage()),
    );
  }

  @override
  State<FoodBarcodeScanPage> createState() => _FoodBarcodeScanPageState();
}

class _FoodBarcodeScanPageState extends State<FoodBarcodeScanPage> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.noDuplicates,
    formats: const [
      BarcodeFormat.ean8,
      BarcodeFormat.ean13,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
    ],
  );

  bool _resolving = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_resolving) return;
    if (capture.barcodes.isEmpty) return;

    final value = capture.barcodes.first.rawValue?.trim();
    if (value == null || value.isEmpty) return;

    _resolving = true;
    await _controller.stop();
    if (!mounted) return;
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Scan barcode')),
      body: Stack(
        fit: StackFit.expand,
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _onDetect,
          ),
          Center(
            child: Container(
              width: 240,
              height: 140,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.9),
                  width: 2,
                ),
              ),
            ),
          ),
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Text(
              'Align barcode inside the frame',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
