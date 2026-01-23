import 'package:flutter/material.dart';

import '../../../data/repositories/settings_repo.dart';

class CloudConsent {
  static Future<bool> ensureDietConsent(
    BuildContext context,
    SettingsRepo repo,
  ) async {
    final granted = await repo.getCloudConsentDiet();
    if (granted) return true;
    final accepted = await _showConsentDialog(
      context,
      title: 'Diet photo/video analysis',
      body:
          'This feature sends meal photos/videos to cloud AI for analysis. '
          'Only the media and transcript text are sent. '
          'No audio is stored. You can disable this anytime.',
    );
    if (accepted == true) {
      await repo.setCloudConsentDiet(true);
      return true;
    }
    return false;
  }

  static Future<bool> ensureAppearanceConsent(
    BuildContext context,
    SettingsRepo repo,
  ) async {
    final granted = await repo.getCloudConsentAppearance();
    if (granted) return true;
    final accepted = await _showConsentDialog(
      context,
      title: 'Appearance analysis',
      body:
          'This feature sends photos/videos to cloud AI for analysis. '
          'Only the media and transcript text are sent. '
          'No audio is stored. You can disable this anytime.',
    );
    if (accepted == true) {
      await repo.setCloudConsentAppearance(true);
      return true;
    }
    return false;
  }

  static Future<bool> ensureLeaderboardConsent(
    BuildContext context,
    SettingsRepo repo,
  ) async {
    final granted = await repo.getCloudConsentLeaderboard();
    if (granted) return true;
    final accepted = await _showConsentDialog(
      context,
      title: 'Leaderboard sharing',
      body:
          'Leaderboards require cloud sync. Your scores will be uploaded. '
          'You can disable this anytime.',
    );
    if (accepted == true) {
      await repo.setCloudConsentLeaderboard(true);
      return true;
    }
    return false;
  }

  static Future<bool?> _showConsentDialog(
    BuildContext context, {
    required String title,
    required String body,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('I Agree'),
          ),
        ],
      ),
    );
  }
}
