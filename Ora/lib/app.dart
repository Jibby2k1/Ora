import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'core/theme/app_theme.dart';
import 'data/db/db.dart';
import 'data/repositories/settings_repo.dart';
import 'data/seed/demo_history_seed.dart';
import 'diagnostics/diagnostics_log.dart';
import 'diagnostics/diagnostics_page.dart';
import 'ui/screens/settings/cloud_required_screen.dart';
import 'ui/screens/shell/app_shell.dart';
import 'ui/screens/shell/app_shell_controller.dart';

class OraApp extends StatefulWidget {
  const OraApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();
  static final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  static Future<void> _initialize() async {
    try {
      DiagnosticsLog.instance.record('OraApp initialization begin');
      final db = AppDatabase.instance;
      await db.database;
      final settings = SettingsRepo(db);
      final developerMode = await settings.getDeveloperMode();
      AppShellController.instance.setDeveloperMode(developerMode);
      await db.seedExercisesIfNeeded(
        'lib/data/seed/exercise_catalog_seed.json',
        fromAsset: true,
      );
      await db.ensureExercisesFromSeed(
        'lib/data/seed/exercise_catalog_seed.json',
        fromAsset: true,
      );
      await db.applyMuscleMapSeed(
        'lib/data/seed/muscle_map_seed.json',
        fromAsset: true,
      );
      await db.syncExerciseScienceInfoFromSeed(
        'lib/data/seed/exercise_science_seed.json',
        fromAsset: true,
      );
      await DemoHistorySeed(db).ensureHistorySeed();
      await settings.setCloudEnabled(true);
      DiagnosticsLog.instance.record('OraApp initialization complete');
    } catch (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'OraApp initialization failed',
      );
      rethrow;
    }
  }

  @override
  State<OraApp> createState() => _OraAppState();
}

class _OraAppState extends State<OraApp> {
  late Future<void> _initFuture;
  late Future<bool> _cloudReadyFuture;

  @override
  void initState() {
    super.initState();
    _startInitialization();
  }

  void _startInitialization() {
    _initFuture = OraApp._initialize().then((_) => _loadUiSettings());
    _cloudReadyFuture = _checkCloudReady();
  }

  Future<void> _loadUiSettings() async {
    final settings = SettingsRepo(AppDatabase.instance);
    final highContrast = await settings.getSnackbarHighContrast();
    final developerMode = await settings.getDeveloperMode();
    AppShellController.instance.setHighContrastSnackbars(highContrast);
    AppShellController.instance.setDeveloperMode(developerMode);
  }

  Future<bool> _checkCloudReady() async {
    final settings = SettingsRepo(AppDatabase.instance);
    return settings.hasCloudApiKey();
  }

  void _refreshCloud() {
    setState(() {
      _cloudReadyFuture = _checkCloudReady();
    });
  }

  void _retryInitialization() {
    setState(_startInitialization);
  }

  Future<void> _copyReport(
    String report, {
    String confirmation = 'Error details copied to clipboard.',
  }) async {
    await Clipboard.setData(ClipboardData(text: report));
    OraApp.messengerKey.currentState?.showSnackBar(
      SnackBar(
        content: Text(confirmation),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  String _buildInitFailureReport(AsyncSnapshot<void> snapshot) {
    final latestError = DiagnosticsLog.instance.latestError;
    if (latestError != null &&
        latestError.context == 'OraApp initialization failed') {
      return latestError.report;
    }
    final error = snapshot.error;
    if (error == null) {
      return 'OraApp initialization failed without an attached exception.';
    }
    return DiagnosticsLog.instance.buildErrorReport(
      error,
      snapshot.stackTrace ?? StackTrace.current,
      context: 'OraApp initialization failed',
    );
  }

  Widget _buildSplashScreen() {
    return Scaffold(
      backgroundColor: const Color(0xFF1D4ED8),
      body: Center(
        child: Image.asset(
          'assets/branding/ora.png',
          width: 180,
          height: 180,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AppShellController.instance.highContrastSnackbars,
      builder: (context, highContrastSnackbars, _) {
        return MaterialApp(
          title: 'Ora',
          debugShowCheckedModeBanner: false,
          themeMode: ThemeMode.dark,
          darkTheme:
              AppTheme.dark(highContrastSnackbars: highContrastSnackbars),
          scaffoldMessengerKey: OraApp.messengerKey,
          navigatorKey: OraApp.navigatorKey,
          builder: (context, child) => _DeveloperErrorListener(
            child: child ?? const SizedBox.shrink(),
          ),
          home: FutureBuilder<void>(
            future: _initFuture,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return _buildSplashScreen();
              }
              if (snapshot.hasError) {
                final report = _buildInitFailureReport(snapshot);
                return _InitFailureScreen(
                  errorText: '${snapshot.error}',
                  report: report,
                  onCopy: () => _copyReport(
                    report,
                    confirmation: 'Init failure copied to clipboard.',
                  ),
                  onRetry: _retryInitialization,
                );
              }
              return FutureBuilder<bool>(
                future: _cloudReadyFuture,
                builder: (context, cloudSnap) {
                  if (cloudSnap.connectionState != ConnectionState.done) {
                    return _buildSplashScreen();
                  }
                  if (cloudSnap.data != true) {
                    return CloudRequiredScreen(onRefresh: _refreshCloud);
                  }
                  return const AppShell();
                },
              );
            },
          ),
        );
      },
    );
  }
}

class _DeveloperErrorListener extends StatefulWidget {
  const _DeveloperErrorListener({required this.child});

  final Widget child;

  @override
  State<_DeveloperErrorListener> createState() =>
      _DeveloperErrorListenerState();
}

class _DeveloperErrorListenerState extends State<_DeveloperErrorListener> {
  StreamSubscription<DiagnosticsErrorEvent>? _subscription;
  DiagnosticsErrorEvent? _queuedEvent;
  String? _lastFingerprint;
  DateTime? _lastShownAt;
  bool _dialogOpen = false;

  @override
  void initState() {
    super.initState();
    _subscription = DiagnosticsLog.instance.errors.listen(_handleErrorEvent);
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  void _handleErrorEvent(DiagnosticsErrorEvent event) {
    if (!AppShellController.instance.developerMode.value) {
      return;
    }
    final now = DateTime.now();
    if (_lastFingerprint == event.fingerprint &&
        _lastShownAt != null &&
        now.difference(_lastShownAt!) < const Duration(seconds: 2)) {
      return;
    }
    _lastFingerprint = event.fingerprint;
    _lastShownAt = now;
    if (_dialogOpen) {
      _queuedEvent = event;
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(_showErrorDialog(event));
    });
  }

  Future<void> _copyReport(String report) async {
    await Clipboard.setData(ClipboardData(text: report));
    OraApp.messengerKey.currentState?.showSnackBar(
      const SnackBar(
        content: Text('Error details copied to clipboard.'),
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Future<void> _showDiagnosticsPage() async {
    final context = OraApp.navigatorKey.currentContext;
    if (context == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DiagnosticsPage()),
    );
  }

  Future<void> _showErrorDialog(DiagnosticsErrorEvent event) async {
    final navigatorContext = OraApp.navigatorKey.currentContext;
    if (navigatorContext == null) {
      _queuedEvent = event;
      return;
    }
    _dialogOpen = true;
    await showDialog<void>(
      context: navigatorContext,
      builder: (context) {
        final theme = Theme.of(context);
        return AlertDialog(
          title: const Text('Developer Mode Error'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    event.summary,
                    style: theme.textTheme.titleSmall,
                  ),
                  const SizedBox(height: 12),
                  SelectableText(
                    event.report,
                    style: theme.textTheme.bodySmall?.copyWith(height: 1.4),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () async {
                await _copyReport(event.report);
              },
              child: const Text('Copy'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                unawaited(_showDiagnosticsPage());
              },
              child: const Text('Diagnostics'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Dismiss'),
            ),
          ],
        );
      },
    );
    _dialogOpen = false;
    if (_queuedEvent != null && mounted) {
      final queued = _queuedEvent!;
      _queuedEvent = null;
      unawaited(_showErrorDialog(queued));
    }
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

class _InitFailureScreen extends StatelessWidget {
  const _InitFailureScreen({
    required this.errorText,
    required this.report,
    required this.onCopy,
    required this.onRetry,
  });

  final String errorText;
  final String report;
  final Future<void> Function() onCopy;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Initialization failed',
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ora could not finish startup. Copy the details below for debugging.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: SelectableText(
                      'Init failed: $errorText',
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: [
                      ElevatedButton.icon(
                        onPressed: onCopy,
                        icon: const Icon(Icons.copy_all),
                        label: const Text('Copy details'),
                      ),
                      OutlinedButton.icon(
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const DiagnosticsPage(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.article_outlined),
                        label: const Text('View diagnostics'),
                      ),
                      TextButton.icon(
                        onPressed: onRetry,
                        icon: const Icon(Icons.refresh),
                        label: const Text('Retry startup'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Expanded(
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color:
                            theme.colorScheme.surface.withValues(alpha: 0.82),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ),
                      child: SingleChildScrollView(
                        child: SelectableText(
                          report,
                          style:
                              theme.textTheme.bodySmall?.copyWith(height: 1.4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
