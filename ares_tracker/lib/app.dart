import 'package:flutter/material.dart';

import 'data/db/db.dart';
import 'data/seed/demo_history_seed.dart';
import 'ui/screens/programs/programs_screen.dart';

class AresApp extends StatelessWidget {
  AresApp({super.key});

  final Future<void> _initFuture = _initialize();

  static Future<void> _initialize() async {
    final db = AppDatabase.instance;
    await db.database;
    await db.seedExercisesIfNeeded('lib/data/seed/exercise_catalog_seed.json', fromAsset: true);
    await DemoHistorySeed(db).ensureHistorySeed();
  }

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F6D7A),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Ares Tracker',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
      ),
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
          return const ProgramsScreen();
        },
      ),
    );
  }
}
