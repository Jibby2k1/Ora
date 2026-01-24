import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/profile_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/user_profile.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final ProfileRepo _profileRepo;
  late final SettingsRepo _settingsRepo;

  final _nameController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  String _weightUnit = 'lb';
  String _heightUnit = 'cm';
  bool _loading = true;
  UserProfile? _profile;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _profileRepo = ProfileRepo(db);
    _settingsRepo = SettingsRepo(db);
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _ageController.dispose();
    _heightController.dispose();
    _weightController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final profile = await _profileRepo.getProfile();
    final unit = await _settingsRepo.getUnit();
    final heightUnit = await _settingsRepo.getHeightUnit();
    setState(() {
      _profile = profile;
      _weightUnit = unit;
      _heightUnit = heightUnit;
      _loading = false;
    });
    if (profile != null) {
      _nameController.text = profile.displayName ?? '';
      _ageController.text = profile.age?.toString() ?? '';
      _heightController.text = _formatHeight(profile.heightCm);
      _weightController.text = _formatWeight(profile.weightKg);
      _notesController.text = profile.notes ?? '';
    }
  }

  String _formatHeight(double? cm) {
    if (cm == null) return '';
    if (_heightUnit == 'in') {
      final inches = cm / 2.54;
      return inches.toStringAsFixed(1);
    }
    return cm.toStringAsFixed(1);
  }

  String _formatWeight(double? kg) {
    if (kg == null) return '';
    if (_weightUnit == 'lb') {
      final lbs = kg * 2.2046226218;
      return lbs.toStringAsFixed(1);
    }
    return kg.toStringAsFixed(1);
  }

  double? _parseHeightToCm(String text) {
    final value = double.tryParse(text.trim());
    if (value == null) return null;
    if (_heightUnit == 'in') {
      return value * 2.54;
    }
    return value;
  }

  double? _parseWeightToKg(String text) {
    final value = double.tryParse(text.trim());
    if (value == null) return null;
    if (_weightUnit == 'lb') {
      return value / 2.2046226218;
    }
    return value;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());
    final heightCm = _parseHeightToCm(_heightController.text);
    final weightKg = _parseWeightToKg(_weightController.text);
    final notes = _notesController.text.trim();

    final saved = await _profileRepo.upsertProfile(
      displayName: name.isEmpty ? null : name,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes.isEmpty ? null : notes,
    );
    setState(() {
      _profile = saved;
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Profile saved locally.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Profile'),
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
                      const Text('Profile (On-device only)'),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _nameController,
                        decoration: const InputDecoration(
                          labelText: 'Name',
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _ageController,
                        decoration: const InputDecoration(
                          labelText: 'Age',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: _heightController,
                              decoration: InputDecoration(
                                labelText: 'Height (${_heightUnit.toUpperCase()})',
                              ),
                              keyboardType: TextInputType.number,
                            ),
                          ),
                          const SizedBox(width: 12),
                          DropdownButton<String>(
                            value: _heightUnit,
                            items: const [
                              DropdownMenuItem(value: 'cm', child: Text('cm')),
                              DropdownMenuItem(value: 'in', child: Text('in')),
                            ],
                            onChanged: (value) async {
                              if (value == null) return;
                              final previousUnit = _heightUnit;
                              final currentValue = double.tryParse(_heightController.text.trim());
                              double? cmValue;
                              if (currentValue != null) {
                                cmValue = previousUnit == 'in' ? currentValue * 2.54 : currentValue;
                              }
                              setState(() {
                                _heightUnit = value;
                                _heightController.text = _formatHeight(cmValue);
                              });
                              await _settingsRepo.setHeightUnit(value);
                            },
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _weightController,
                        decoration: InputDecoration(
                          labelText: 'Weight (${_weightUnit.toUpperCase()})',
                        ),
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 12),
                      TextField(
                        controller: _notesController,
                        decoration: const InputDecoration(
                          labelText: 'Notes',
                        ),
                        maxLines: 3,
                      ),
                      const SizedBox(height: 16),
                      Align(
                        alignment: Alignment.centerRight,
                        child: ElevatedButton.icon(
                          onPressed: _save,
                          icon: const Icon(Icons.save),
                          label: const Text('Save'),
                        ),
                      ),
                      if (_profile != null) ...[
                        const SizedBox(height: 12),
                        Text('Last updated: ${_profile!.updatedAt.toLocal()}'),
                      ],
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
