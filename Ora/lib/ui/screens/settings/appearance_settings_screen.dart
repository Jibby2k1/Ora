import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../shell/app_shell_controller.dart';

class AppearanceSettingsScreen extends StatefulWidget {
  const AppearanceSettingsScreen({super.key});

  @override
  State<AppearanceSettingsScreen> createState() => _AppearanceSettingsScreenState();
}

class _AppearanceSettingsScreenState extends State<AppearanceSettingsScreen> {
  late final SettingsRepo _settingsRepo;
  bool _appearanceEnabled = true;
  bool _profileEnabled = false;
  String _sex = 'neutral';

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _load();
  }

  Future<void> _load() async {
    final access = await _settingsRepo.getAppearanceAccessEnabled();
    final profileEnabled = await _settingsRepo.getAppearanceProfileEnabled();
    final sex = await _settingsRepo.getAppearanceProfileSex();
    if (!mounted) return;
    setState(() {
      _appearanceEnabled = access ?? true;
      _profileEnabled = profileEnabled;
      _sex = sex;
    });
    AppShellController.instance.setAppearanceProfileEnabled(profileEnabled);
    AppShellController.instance.setAppearanceProfileSex(sex);
  }

  Future<void> _setAppearanceEnabled(bool value) async {
    if (!value) {
      await _settingsRepo.setAppearanceAccessEnabled(false);
      AppShellController.instance.setAppearanceEnabled(false);
      setState(() => _appearanceEnabled = false);
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enable Appearance'),
        content: const Text('This enables the Appearance tab. Continue?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Enable'),
          ),
        ],
      ),
    );
    if (accepted != true) return;
    await _settingsRepo.setAppearanceAccessEnabled(true);
    AppShellController.instance.setAppearanceEnabled(true);
    setState(() => _appearanceEnabled = true);
  }

  Future<void> _setProfileEnabled(bool value) async {
    if (value) {
      final accepted = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Appearance profile consent'),
          content: const Text(
            'This lets Ora personalize anatomy visuals in Training based on your profile. '
            'Stored locally on device.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('Not now'),
            ),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text('I agree'),
            ),
          ],
        ),
      );
      if (accepted != true) return;
    }
    setState(() => _profileEnabled = value);
    await _settingsRepo.setAppearanceProfileEnabled(value);
    AppShellController.instance.setAppearanceProfileEnabled(value);
  }

  Future<void> _setSex(String value) async {
    setState(() => _sex = value);
    await _settingsRepo.setAppearanceProfileSex(value);
    AppShellController.instance.setAppearanceProfileSex(value);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Appearance Settings'),
        actions: const [SizedBox(width: 72)],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          ListView(
            padding: const EdgeInsets.all(16),
            children: [
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Access'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _appearanceEnabled,
                      onChanged: _setAppearanceEnabled,
                      title: const Text('Enable Appearance tab'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              GlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Appearance profile'),
                    const SizedBox(height: 8),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _profileEnabled,
                      onChanged: _setProfileEnabled,
                      title: const Text('Use appearance profile'),
                      subtitle: const Text('Used for anatomy visuals.'),
                    ),
                    const SizedBox(height: 8),
                    InputDecorator(
                      decoration: const InputDecoration(labelText: 'Anatomy model'),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _sex,
                          isExpanded: true,
                          onChanged: _profileEnabled
                              ? (value) {
                                  if (value == null) return;
                                  _setSex(value);
                                }
                              : null,
                          items: const [
                            DropdownMenuItem(value: 'neutral', child: Text('Neutral')),
                            DropdownMenuItem(value: 'male', child: Text('Male')),
                            DropdownMenuItem(value: 'female', child: Text('Female')),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
