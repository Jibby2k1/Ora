import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../domain/services/session_service.dart';
import '../session/session_screen.dart';

class SessionEditScreen extends StatelessWidget {
  const SessionEditScreen({super.key, required this.sessionId});

  final int sessionId;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder(
      future: SessionService(AppDatabase.instance).loadSession(sessionId),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return const Scaffold(
            body: Center(child: Text('Session not found.')),
          );
        }
        return SessionScreen(
          contextData: data,
          isEditing: true,
        );
      },
    );
  }
}
