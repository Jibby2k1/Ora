import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../app.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import 'account_screen.dart';
import 'profile_screen.dart';
import '../shell/app_shell_controller.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final SettingsRepo _settingsRepo;
  bool _loading = true;

  String _unit = 'lb';
  double _increment = 2.5;
  int _restDefault = 120;
  bool _voiceEnabled = true;
  bool _wakeWordEnabled = false;
  String _cloudProvider = 'gemini';
  bool _orbHidden = false;
  String _themeMode = 'dark';

  final _incrementController = TextEditingController();
  final _restController = TextEditingController();
  final _cloudKeyController = TextEditingController();
  final _cloudModelController = TextEditingController();
  bool _showCloudKey = false;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _load();
  }

  @override
  void dispose() {
    _incrementController.dispose();
    _restController.dispose();
    _cloudKeyController.dispose();
    _cloudModelController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final unit = await _settingsRepo.getUnit();
    final increment = await _settingsRepo.getIncrement();
    final rest = await _settingsRepo.getRestDefault();
    final voiceEnabled = await _settingsRepo.getVoiceEnabled();
    final wakeWordEnabled = await _settingsRepo.getWakeWordEnabled();
    final cloudKey = await _settingsRepo.getCloudApiKey();
    final cloudModel = await _settingsRepo.getCloudModel();
    final cloudProvider = await _settingsRepo.getCloudProvider();
    final orbHidden = await _settingsRepo.getOrbHidden();
    final themeMode = await _settingsRepo.getThemeMode();
    setState(() {
      _unit = unit;
      _increment = increment;
      _restDefault = rest;
      _voiceEnabled = voiceEnabled;
      _wakeWordEnabled = wakeWordEnabled;
      _incrementController.text = increment.toStringAsFixed(2);
      _restController.text = rest.toString();
      _cloudKeyController.text = cloudKey ?? '';
      _cloudModelController.text = cloudModel;
      _cloudProvider = cloudProvider;
      _orbHidden = orbHidden;
      _themeMode = themeMode;
      _loading = false;
    });
  }

  Future<void> _saveIncrement() async {
    final value = double.tryParse(_incrementController.text.trim());
    if (value == null) return;
    setState(() => _increment = value);
    await _settingsRepo.setIncrement(value);
  }

  Future<void> _saveRest() async {
    final value = int.tryParse(_restController.text.trim());
    if (value == null) return;
    setState(() => _restDefault = value);
    await _settingsRepo.setRestDefault(value);
  }

  Future<void> _saveCloudSettings() async {
    await _settingsRepo.setCloudApiKey(_cloudKeyController.text);
    await _settingsRepo.setCloudModel(_cloudModelController.text);
    await _settingsRepo.setCloudProvider(_cloudProvider);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Cloud settings saved.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: const [SizedBox(width: 72)],
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else
            ListView(
              padding: const EdgeInsets.all(16),
              children: [
                GlassCard(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Account'),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Sign in'),
                        subtitle: const Text('Apple, Google, Microsoft, Email'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const AccountScreen()),
                          );
                        },
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
                      const Text('Appearance'),
                      const SizedBox(height: 8),
                      const Text('App theme'),
                      const SizedBox(height: 8),
                      SegmentedButton<String>(
                        segments: const [
                          ButtonSegment(value: 'dark', label: Text('Dark')),
                          ButtonSegment(value: 'light', label: Text('Light')),
                        ],
                        selected: {_themeMode},
                        onSelectionChanged: (value) async {
                          final mode = value.first;
                          setState(() => _themeMode = mode);
                          await _settingsRepo.setThemeMode(mode);
                          OraApp.themeMode.value =
                              mode == 'light' ? ThemeMode.light : ThemeMode.dark;
                        },
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
                      const Text('Ora Orb'),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: !_orbHidden,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Show floating input'),
                        subtitle: const Text('Always-on input hub across tabs'),
                        onChanged: (value) async {
                          setState(() => _orbHidden = !value);
                          await _settingsRepo.setOrbHidden(!value);
                          AppShellController.instance.setOrbHidden(!value);
                        },
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
                      const Text('Profile'),
                      const SizedBox(height: 8),
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Profile (On-device only)'),
                        subtitle: const Text('Name, age, height, weight'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(builder: (_) => const ProfileScreen()),
                          );
                        },
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
                      Row(
                        children: [
                          const Expanded(child: Text('Cloud Parsing (Required)')),
                          IconButton(
                            icon: const Icon(Icons.info_outline),
                            onPressed: () {
                              final title = _cloudProvider == 'openai'
                                  ? 'OpenAI API setup'
                                  : 'Gemini API setup';
                              final body = _cloudProvider == 'openai'
                                  ? 'To use OpenAI, follow these steps:\n'
                                      '1) Go to platform.openai.com\n'
                                      '2) Sign in or create an account.\n'
                                      '3) Open the “API Keys” page.\n'
                                      '4) Click “Create new secret key”.\n'
                                      '5) Copy the key immediately (you won’t see it again).\n'
                                      '6) Paste it into the “API Key” field and press Save.\n'
                                      'Text and file previews may be sent for classification. No audio is sent.'
                                  : 'To use Gemini, follow these steps:\n'
                                      '1) Go to aistudio.google.com\n'
                                      '2) Sign in with your Google account.\n'
                                      '3) Open “Get API key”.\n'
                                      '4) Create a new key.\n'
                                      '5) Copy the key and paste it into the “API Key” field, then press Save.\n'
                                      'Note: the student Gemini plan for the consumer app does not automatically '
                                      'include API access. Text, file previews, and images may be sent for classification.';
                              showDialog<void>(
                                context: context,
                                builder: (context) {
                                  return AlertDialog(
                                    title: Text(title),
                                    content: Text(body),
                                    actions: [
                                      TextButton(
                                        onPressed: () => Navigator.of(context).pop(),
                                        child: const Text('OK'),
                                      ),
                                    ],
                                  );
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Provider')),
                          DropdownButton<String>(
                            value: _cloudProvider,
                            items: const [
                              DropdownMenuItem(value: 'gemini', child: Text('Gemini')),
                              DropdownMenuItem(value: 'openai', child: Text('OpenAI')),
                            ],
                            onChanged: (value) {
                              if (value == null) return;
                              setState(() {
                                _cloudProvider = value;
                                if (value == 'gemini') {
                                  _cloudModelController.text = 'gemini-2.5-pro';
                                } else if (value == 'openai') {
                                  _cloudModelController.text = 'gpt-5-nano';
                                }
                              });
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      const Text(
                        'API keys are stored securely on-device (Keychain/Keystore) and never uploaded.',
                      ),
                      const SizedBox(height: 8),
                      const Text('Cloud parsing is required for this app.'),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _cloudKeyController,
                        decoration: InputDecoration(
                          labelText: 'API Key',
                          suffixIcon: IconButton(
                            icon: Icon(_showCloudKey ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _showCloudKey = !_showCloudKey),
                          ),
                        ),
                        obscureText: !_showCloudKey,
                        onSubmitted: (_) => _settingsRepo.setCloudApiKey(_cloudKeyController.text),
                      ),
                      const SizedBox(height: 8),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: () async {
                            _cloudKeyController.clear();
                            await _settingsRepo.setCloudApiKey(null);
                            if (!mounted) return;
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('API key cleared.')),
                            );
                          },
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('Clear API key'),
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Expanded(child: Text('Model')),
                          Builder(
                            builder: (context) {
                              final models = _cloudProvider == 'openai'
                                  ? const ['gpt-5-nano', 'gpt-4o', 'gpt-4o-mini']
                                  : const ['gemini-2.5-pro', 'gemini-2.0-flash', 'gemini-1.5-flash'];
                              var current = _cloudModelController.text.trim();
                              if (current.isEmpty || !models.contains(current)) {
                                current = models.first;
                                _cloudModelController.text = current;
                              }
                              return DropdownButton<String>(
                                value: current,
                                items: models
                                    .map((model) => DropdownMenuItem(value: model, child: Text(model)))
                                    .toList(),
                                onChanged: (value) {
                                  if (value == null) return;
                                  setState(() {
                                    _cloudModelController.text = value;
                                  });
                                },
                              );
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _saveCloudSettings,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                      const SizedBox(height: 12),
                      const Text(
                        'Other providers: coming soon (offline-first is primary).',
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
                      const Text('Preferences'),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          const Expanded(child: Text('Units')),
                          DropdownButton<String>(
                            value: _unit,
                            items: const [
                              DropdownMenuItem(value: 'lb', child: Text('lb')),
                              DropdownMenuItem(value: 'kg', child: Text('kg')),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              setState(() => _unit = value);
                              await _settingsRepo.setUnit(value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _incrementController,
                        decoration: const InputDecoration(
                          labelText: 'Weight increment',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveIncrement(),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _restController,
                        decoration: const InputDecoration(
                          labelText: 'Default rest (sec)',
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (_) => _saveRest(),
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
                      const Text('Voice'),
                      const SizedBox(height: 8),
                      SwitchListTile(
                        value: _voiceEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Enable voice'),
                        subtitle: const Text('On-device only'),
                        onChanged: (value) async {
                          setState(() => _voiceEnabled = value);
                          await _settingsRepo.setVoiceEnabled(value);
                        },
                      ),
                      SwitchListTile(
                        value: _wakeWordEnabled,
                        contentPadding: EdgeInsets.zero,
                        title: const Text('Wake word: “Hey Ora”'),
                        subtitle: const Text('Session-only, foreground-only'),
                        onChanged: (value) async {
                          setState(() => _wakeWordEnabled = value);
                          await _settingsRepo.setWakeWordEnabled(value);
                        },
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
                      const Text('About'),
                      const SizedBox(height: 8),
                      const Text('Local-only. No accounts, no cloud sync.'),
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
