import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../ui/widgets/glass/glass_background.dart';
import '../ui/widgets/glass/glass_card.dart';
import 'diagnostics_log.dart';

class DiagnosticsPage extends StatefulWidget {
  const DiagnosticsPage({super.key});

  @override
  State<DiagnosticsPage> createState() => _DiagnosticsPageState();
}

class _DiagnosticsPageState extends State<DiagnosticsPage> {
  static const int _maxVisibleLines = 250;

  late Future<List<String>> _linesFuture;

  @override
  void initState() {
    super.initState();
    _linesFuture = DiagnosticsLog.instance.readTailLines(
      maxLines: _maxVisibleLines,
    );
  }

  Future<void> _reload() async {
    setState(() {
      _linesFuture = DiagnosticsLog.instance.readTailLines(
        maxLines: _maxVisibleLines,
      );
    });
  }

  Future<void> _copyLogs() async {
    final text = await DiagnosticsLog.instance.readTailText(
      maxLines: _maxVisibleLines,
    );
    if (!mounted) return;
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Diagnostics copied to clipboard.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _shareLogs() async {
    final path = await DiagnosticsLog.instance.logFilePath;
    if (!mounted || path == null) return;
    await Share.shareXFiles(
      [XFile(path)],
      text: 'Ora diagnostics log',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Diagnostics'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          FutureBuilder<List<String>>(
            future: _linesFuture,
            builder: (context, snapshot) {
              final lines = snapshot.data ?? const <String>[];
              return ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Recent Diagnostics',
                          style: Theme.of(context).textTheme.titleMedium
                              ?.copyWith(fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Shows the last $_maxVisibleLines log lines captured by the app. Use this after a release-mode crash.',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            OutlinedButton(
                              onPressed: _reload,
                              child: const Text('Refresh'),
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton(
                              onPressed: _copyLogs,
                              child: const Text('Copy'),
                            ),
                            const SizedBox(width: 8),
                            ElevatedButton(
                              onPressed: _shareLogs,
                              child: const Text('Share'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                  GlassCard(
                    padding: const EdgeInsets.all(16),
                    child: snapshot.connectionState != ConnectionState.done
                        ? const Center(child: CircularProgressIndicator())
                        : SelectableText(
                            lines.isEmpty
                                ? 'No diagnostics have been logged yet.'
                                : lines.join('\n'),
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(height: 1.4),
                          ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
