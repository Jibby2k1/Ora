import 'package:flutter/material.dart';

class AresApp extends StatelessWidget {
  const AresApp({super.key});

  @override
  Widget build(BuildContext context) {
    final darkScheme = ColorScheme.fromSeed(
      seedColor: const Color(0xFF4F6D7A),
      brightness: Brightness.dark,
    );

    return MaterialApp(
      title: 'Ares Tracker',
      themeMode: ThemeMode.dark,
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: darkScheme,
        scaffoldBackgroundColor: darkScheme.surface,
      ),
      home: const Scaffold(
        body: Center(
          child: Text('Ares Tracker'),
        ),
      ),
    );
  }
}
