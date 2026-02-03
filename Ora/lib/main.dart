import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  } else if (Platform.isAndroid || Platform.isIOS) {
    const enableFirebase =
        bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: false);
    if (enableFirebase) {
      try {
        await Firebase.initializeApp();
      } catch (error) {
        debugPrint('Firebase init skipped: $error');
      }
    } else {
      debugPrint(
          'Firebase disabled for this run. Set ENABLE_FIREBASE=true to enable.');
    }
  }
  runApp(ProviderScope(child: OraApp()));
}
