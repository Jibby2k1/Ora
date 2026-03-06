import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'app.dart';
import 'diagnostics/diagnostics_log.dart';

Future<void> main() async {
  await runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await DiagnosticsLog.instance.initialize();

      FlutterError.onError = (details) {
        DiagnosticsLog.instance.recordFlutterError(details);
        Zone.current.handleUncaughtError(
          details.exception,
          details.stack ?? StackTrace.current,
        );
      };

      PlatformDispatcher.instance.onError = (error, stackTrace) {
        DiagnosticsLog.instance.recordError(
          error,
          stackTrace,
          context: 'PlatformDispatcher error',
        );
        return true;
      };

      DiagnosticsLog.instance.record('Application startup begin');
      if (Platform.isLinux || Platform.isWindows || Platform.isMacOS) {
        sqfliteFfiInit();
        databaseFactory = databaseFactoryFfi;
      } else if (Platform.isAndroid || Platform.isIOS) {
        const enableFirebase =
            bool.fromEnvironment('ENABLE_FIREBASE', defaultValue: false);
        if (enableFirebase) {
          try {
            await Firebase.initializeApp();
          } catch (error, stackTrace) {
            DiagnosticsLog.instance.recordError(
              error,
              stackTrace,
              context: 'Firebase initialization skipped',
            );
          }
        } else {
          DiagnosticsLog.instance.record(
            'Firebase disabled for this run. Set ENABLE_FIREBASE=true to enable.',
          );
        }
      }
      DiagnosticsLog.instance.record('Running OraApp');
      runApp(const ProviderScope(child: OraApp()));
    },
    (error, stackTrace) {
      DiagnosticsLog.instance.recordError(
        error,
        stackTrace,
        context: 'runZonedGuarded uncaught error',
      );
    },
  );
}
