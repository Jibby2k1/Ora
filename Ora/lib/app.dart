import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/db/db.dart';
import 'data/seed/demo_history_seed.dart';
import 'data/repositories/settings_repo.dart';
import 'ui/screens/shell/app_shell.dart';
import 'ui/screens/settings/cloud_required_screen.dart';

class OraApp extends StatefulWidget {
  OraApp({super.key});

  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static Future<void> _initialize() async {
    final db = AppDatabase.instance;
    await db.database;
    await db.seedExercisesIfNeeded('lib/data/seed/exercise_catalog_seed.json', fromAsset: true);
    await db.ensureExercisesFromSeed('lib/data/seed/exercise_catalog_seed.json', fromAsset: true);
    await db.applyMuscleMapSeed('lib/data/seed/muscle_map_seed.json', fromAsset: true);
    await DemoHistorySeed(db).ensureHistorySeed();
    await SettingsRepo(db).setCloudEnabled(true);
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
    _initFuture = OraApp._initialize();
    _cloudReadyFuture = _checkCloudReady();
  }

  Future<bool> _checkCloudReady() async {
    final settings = SettingsRepo(AppDatabase.instance);
    final apiKey = await settings.getCloudApiKey();
    return apiKey != null && apiKey.trim().isNotEmpty;
  }

  void _refreshCloud() {
    setState(() {
      _cloudReadyFuture = _checkCloudReady();
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      scaffoldMessengerKey: OraApp.messengerKey,
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return Scaffold(
              backgroundColor: const Color(0xFF1D4ED8),
              body: Center(
                child: Image.asset(
                  'assets/branding/ora_logo_blue.png',
                  width: 180,
                  height: 180,
                ),
              ),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Init failed: ${snapshot.error}'),
              ),
            );
          }
          return FutureBuilder<bool>(
            future: _cloudReadyFuture,
            builder: (context, cloudSnap) {
              if (cloudSnap.connectionState != ConnectionState.done) {
                return Scaffold(
                  backgroundColor: const Color(0xFF1D4ED8),
                  body: Center(
                    child: Image.asset(
                      'assets/branding/ora_logo_blue.png',
                      width: 180,
                      height: 180,
                    ),
                  ),
                );
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
  }
}
