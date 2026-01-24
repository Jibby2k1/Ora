import 'package:flutter/material.dart';

import 'core/theme/app_theme.dart';
import 'data/db/db.dart';
import 'data/seed/demo_history_seed.dart';
import 'ui/screens/shell/app_shell.dart';

class OraApp extends StatelessWidget {
  OraApp({super.key});

  final Future<void> _initFuture = _initialize();
  static final GlobalKey<ScaffoldMessengerState> messengerKey =
      GlobalKey<ScaffoldMessengerState>();

  static Future<void> _initialize() async {
    final db = AppDatabase.instance;
    await db.database;
    await db.seedExercisesIfNeeded('lib/data/seed/exercise_catalog_seed.json', fromAsset: true);
    await db.ensureExercisesFromSeed('lib/data/seed/exercise_catalog_seed.json', fromAsset: true);
    await db.applyMuscleMapSeed('lib/data/seed/muscle_map_seed.json', fromAsset: true);
    await DemoHistorySeed(db).ensureHistorySeed();
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Ora',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: AppTheme.dark(),
      scaffoldMessengerKey: messengerKey,
      home: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          }
          if (snapshot.hasError) {
            return Scaffold(
              body: Center(
                child: Text('Init failed: ${snapshot.error}'),
              ),
            );
          }
          return const AppShell();
        },
      ),
    );
  }
}
