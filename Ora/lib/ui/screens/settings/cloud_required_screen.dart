import 'package:flutter/material.dart';

import 'settings_screen.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class CloudRequiredScreen extends StatelessWidget {
  const CloudRequiredScreen({super.key, required this.onRefresh});

  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cloud Required'),
        actions: const [SizedBox(width: 72)],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          Center(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: GlassCard(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Ora requires cloud access to run.',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Add your Gemini or OpenAI API key in Settings to continue.',
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        ElevatedButton.icon(
                          onPressed: () async {
                            await Navigator.of(context).push(
                              MaterialPageRoute(builder: (_) => const SettingsScreen()),
                            );
                            onRefresh();
                          },
                          icon: const Icon(Icons.settings),
                          label: const Text('Open Settings'),
                        ),
                        const SizedBox(width: 12),
                        TextButton(
                          onPressed: onRefresh,
                          child: const Text('I added a key'),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
