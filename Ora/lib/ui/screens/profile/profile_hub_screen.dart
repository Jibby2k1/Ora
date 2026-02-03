import 'dart:async';
import 'dart:io';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/image_downscaler.dart';
import '../../../data/db/db.dart';
import '../../../data/repositories/profile_repo.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../domain/models/user_profile.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';
import '../leaderboard/leaderboard_screen.dart';
import '../settings/settings_screen.dart';

class ProfileHubScreen extends StatelessWidget {
  const ProfileHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 3,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Profile'),
          actions: const [SizedBox(width: 72)],
        ),
        body: Stack(
          children: [
            const GlassBackground(),
            Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: const Center(
                      child: TabBar(
                        isScrollable: true,
                        tabs: [
                          Tab(text: 'Profile'),
                          Tab(text: 'Leaderboard'),
                          Tab(text: 'Settings'),
                        ],
                      ),
                    ),
                  ),
                ),
                const Expanded(
                  child: TabBarView(
                    children: [
                      _ProfileTab(),
                      LeaderboardContent(showBackground: false),
                      SettingsContent(showBackground: false),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ProfileTab extends StatefulWidget {
  const _ProfileTab();

  @override
  State<_ProfileTab> createState() => _ProfileTabState();
}

class _ProfileTabState extends State<_ProfileTab> {
  late final ProfileRepo _profileRepo;
  late final SettingsRepo _settingsRepo;
  final ImagePicker _imagePicker = ImagePicker();

  StreamSubscription<User?>? _authSub;

  final _usernameController = TextEditingController();
  final _ageController = TextEditingController();
  final _heightController = TextEditingController();
  final _weightController = TextEditingController();
  final _notesController = TextEditingController();

  String _weightUnit = 'lb';
  String _heightUnit = 'cm';
  bool _loading = true;
  UserProfile? _profile;
  String? _avatarPath;
  String? _remoteAvatarUrl;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _profileRepo = ProfileRepo(db);
    _settingsRepo = SettingsRepo(db);
    _load();
    _listenToAuthChanges();
  }

  @override
  void dispose() {
    _authSub?.cancel();
    _usernameController.dispose();
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
    final avatarPath = await _settingsRepo.getProfileAvatarPath();
    final user = _safeCurrentUser();
    if (!mounted) return;
    setState(() {
      _profile = profile;
      _weightUnit = unit;
      _heightUnit = heightUnit;
      _avatarPath = avatarPath;
      _remoteAvatarUrl = user?.photoURL;
      _loading = false;
    });
    if (!mounted) return;
    if (profile != null) {
      _usernameController.text = profile.displayName ?? '';
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

  Future<void> _pickAvatar() async {
    final picked = await _imagePicker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final scaled = await ImageDownscaler.downscaleImageIfNeeded(
      File(picked.path),
      maxDimension: 512,
      jpegQuality: 82,
    );
    await _settingsRepo.setProfileAvatarPath(scaled.path);
    if (!mounted) return;
    setState(() => _avatarPath = scaled.path);
  }

  Future<String?> _uploadAvatar(String path) async {
    if (!_isFirebaseReady) return null;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    try {
      final ref = FirebaseStorage.instance.ref('users/${user.uid}/profile/avatar.jpg');
      await ref.putFile(File(path));
      return ref.getDownloadURL();
    } catch (e) {
      debugPrint('Avatar upload failed: $e');
      return null;
    }
  }

  Future<void> _save() async {
    final username = _usernameController.text.trim();
    final age = int.tryParse(_ageController.text.trim());
    final heightCm = _parseHeightToCm(_heightController.text);
    final weightKg = _parseWeightToKg(_weightController.text);
    final notes = _notesController.text.trim();

    final saved = await _profileRepo.upsertProfile(
      displayName: username.isEmpty ? null : username,
      age: age,
      heightCm: heightCm,
      weightKg: weightKg,
      notes: notes.isEmpty ? null : notes,
    );
    if (!mounted) return;
    setState(() {
      _profile = saved;
    });

    final user = _safeCurrentUser();
    String? syncError;
    if (user != null) {
      try {
        if (username.isNotEmpty) {
          await user.updateDisplayName(username);
        }
      } catch (e) {
        syncError = 'Profile saved locally; display name sync failed.';
        debugPrint('Profile display name sync failed: $e');
      }
      if (_avatarPath != null) {
        try {
          final url = await _uploadAvatar(_avatarPath!);
          if (url != null) {
            await user.updatePhotoURL(url);
            if (mounted) {
              setState(() => _remoteAvatarUrl = url);
            }
          }
        } catch (e) {
          syncError = 'Profile saved locally; avatar sync failed.';
          debugPrint('Profile avatar sync failed: $e');
        }
      }
    }

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          syncError ??
              (user == null ? 'Profile saved locally.' : 'Profile saved + synced.'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    final avatar = _buildAvatar();
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Profile'),
              const SizedBox(height: 12),
              Row(
                children: [
                  avatar,
                  const SizedBox(width: 16),
                  Expanded(
                    child: TextField(
                      controller: _usernameController,
                      decoration: const InputDecoration(
                        labelText: 'Username',
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _pickAvatar,
                  icon: const Icon(Icons.photo_camera),
                  label: const Text('Change photo'),
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
    );
  }

  Widget _buildAvatar() {
    final radius = 32.0;
    if (_avatarPath != null && File(_avatarPath!).existsSync()) {
      return CircleAvatar(radius: radius, backgroundImage: FileImage(File(_avatarPath!)));
    }
    if (_remoteAvatarUrl != null && _remoteAvatarUrl!.isNotEmpty) {
      return CircleAvatar(radius: radius, backgroundImage: NetworkImage(_remoteAvatarUrl!));
    }
    return CircleAvatar(
      radius: radius,
      backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
      child: Icon(Icons.person, color: Theme.of(context).colorScheme.primary),
    );
  }

  bool get _isFirebaseReady => Firebase.apps.isNotEmpty;

  User? _safeCurrentUser() {
    if (!_isFirebaseReady) return null;
    try {
      return FirebaseAuth.instance.currentUser;
    } catch (_) {
      return null;
    }
  }

  void _listenToAuthChanges() {
    if (!_isFirebaseReady) return;
    try {
      _authSub = FirebaseAuth.instance.authStateChanges().listen((_) {
        if (!mounted) return;
        _load();
      });
    } catch (_) {
      // Ignore auth subscription failures when Firebase isn't initialized.
    }
  }
}
