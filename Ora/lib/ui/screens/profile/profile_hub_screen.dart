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

enum _ProfileHubSection { hub, profile, leaderboard, settings }

class ProfileHubScreen extends StatefulWidget {
  const ProfileHubScreen({super.key});

  @override
  State<ProfileHubScreen> createState() => _ProfileHubScreenState();
}

class _ProfileHubScreenState extends State<ProfileHubScreen> {
  _ProfileHubSection _selectedSection = _ProfileHubSection.hub;

  void _openSection(_ProfileHubSection section) {
    if (_selectedSection == section) return;
    setState(() => _selectedSection = section);
  }

  String _sectionTitle(_ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return 'Profile Hub';
      case _ProfileHubSection.profile:
        return 'Profile';
      case _ProfileHubSection.leaderboard:
        return 'Leaderboard';
      case _ProfileHubSection.settings:
        return 'Settings';
    }
  }

  String _sectionDescription(_ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return 'Choose whether you want to edit identity details, check rankings, or change app settings.';
      case _ProfileHubSection.profile:
        return 'Edit personal details, avatar, and core body metrics.';
      case _ProfileHubSection.leaderboard:
        return 'Inspect friends and global ranking workflows.';
      case _ProfileHubSection.settings:
        return 'Adjust cloud, training, app, and advanced settings.';
    }
  }

  String _sectionMeta(_ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return 'One landing page for identity, rankings, and configuration.';
      case _ProfileHubSection.profile:
        return 'Identity and personal metrics';
      case _ProfileHubSection.leaderboard:
        return 'Friends and global comparisons';
      case _ProfileHubSection.settings:
        return 'Cloud, app, training, and advanced controls';
    }
  }

  IconData _sectionIcon(_ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return Icons.dashboard_customize_rounded;
      case _ProfileHubSection.profile:
        return Icons.person_rounded;
      case _ProfileHubSection.leaderboard:
        return Icons.leaderboard_rounded;
      case _ProfileHubSection.settings:
        return Icons.tune_rounded;
    }
  }

  Color _sectionAccent(BuildContext context, _ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return Theme.of(context).colorScheme.primary;
      case _ProfileHubSection.profile:
        return Colors.lightBlueAccent;
      case _ProfileHubSection.leaderboard:
        return Colors.orangeAccent;
      case _ProfileHubSection.settings:
        return Colors.tealAccent.shade400;
    }
  }

  List<_ProfileHubSection> get _sections => const [
        _ProfileHubSection.profile,
        _ProfileHubSection.leaderboard,
        _ProfileHubSection.settings,
      ];

  Widget _buildHubView() {
    final theme = Theme.of(context);
    return ListView(
      key: const ValueKey('profile-hub'),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 20),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(
                      Icons.account_circle_rounded,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Profile Hub',
                          style: theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Profile, rankings, and settings in one compact control panel.',
                          style: theme.textTheme.bodySmall,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  FilledButton(
                    onPressed: () => _openSection(_ProfileHubSection.profile),
                    child: const Text('Profile'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  _buildMetric(theme, 'Sections', _sections.length.toString()),
                  _buildMetric(theme, 'Rankings', 'Friends'),
                  _buildMetric(theme, 'Settings', 'Ready'),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columns = constraints.maxWidth >= 1100
                ? 4
                : constraints.maxWidth >= 760
                    ? 3
                    : 2;
            final cardWidth =
                (constraints.maxWidth - ((columns - 1) * 12)) / columns;
            return Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                for (final section in _sections)
                  SizedBox(
                    width: cardWidth,
                    child: _buildActionCard(section),
                  ),
              ],
            );
          },
        ),
      ],
    );
  }

  Widget _buildMetric(ThemeData theme, String label, String value) {
    return Container(
      constraints: const BoxConstraints(minWidth: 104),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: 0.48),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: theme.colorScheme.outline.withValues(alpha: 0.14),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: theme.textTheme.bodySmall),
          const SizedBox(height: 2),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionCard(_ProfileHubSection section) {
    final theme = Theme.of(context);
    final accent = _sectionAccent(context, section);
    return GestureDetector(
      onTap: () => _openSection(section),
      child: GlassCard(
        padding: EdgeInsets.zero,
        child: Container(
          constraints: const BoxConstraints(minHeight: 156),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                accent.withValues(alpha: 0.10),
                theme.colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.30),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Icon(_sectionIcon(section), size: 18, color: accent),
                  ),
                  const Spacer(),
                  Icon(Icons.arrow_outward_rounded, size: 18, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                _sectionTitle(section),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _sectionMeta(section),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: accent,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _sectionDescription(section),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(_ProfileHubSection section) {
    final theme = Theme.of(context);
    final accent = _sectionAccent(context, section);
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(_sectionIcon(section), color: accent),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _sectionTitle(section),
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(_sectionDescription(section)),
                    const SizedBox(height: 6),
                    Text(
                      _sectionMeta(section),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              TextButton.icon(
                onPressed: () => _openSection(_ProfileHubSection.hub),
                icon: const Icon(Icons.grid_view_rounded),
                label: const Text('Hub'),
              ),
            ],
          ),
          const SizedBox(height: 14),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (final item in _sections)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text(_sectionTitle(item)),
                      selected: item == section,
                      onSelected: (_) => _openSection(item),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionBody(_ProfileHubSection section) {
    switch (section) {
      case _ProfileHubSection.hub:
        return _buildHubView();
      case _ProfileHubSection.profile:
        return const _ProfileTab();
      case _ProfileHubSection.leaderboard:
        return const LeaderboardContent(showBackground: false);
      case _ProfileHubSection.settings:
        return const SettingsContent(showBackground: false);
    }
  }

  Widget _buildDetailView() {
    final section = _selectedSection;
    return Column(
      key: ValueKey(_sectionTitle(section)),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
          child: _buildSectionHeader(section),
        ),
        Expanded(child: _buildSectionBody(section)),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope<void>(
      canPop: _selectedSection == _ProfileHubSection.hub,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && _selectedSection != _ProfileHubSection.hub) {
          _openSection(_ProfileHubSection.hub);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            _selectedSection == _ProfileHubSection.hub
                ? 'Profile Hub'
                : 'Profile • ${_sectionTitle(_selectedSection)}',
          ),
          actions: [
            if (_selectedSection != _ProfileHubSection.hub)
              IconButton(
                tooltip: 'Back to hub',
                onPressed: () => _openSection(_ProfileHubSection.hub),
                icon: const Icon(Icons.grid_view_rounded),
              ),
          ],
        ),
        body: Stack(
          children: [
            const GlassBackground(),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 240),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: _selectedSection == _ProfileHubSection.hub
                  ? _buildHubView()
                  : _buildDetailView(),
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
      final ref =
          FirebaseStorage.instance.ref('users/${user.uid}/profile/avatar.jpg');
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
              (user == null
                  ? 'Profile saved locally.'
                  : 'Profile saved + synced.'),
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
                      final currentValue =
                          double.tryParse(_heightController.text.trim());
                      double? cmValue;
                      if (currentValue != null) {
                        cmValue = previousUnit == 'in'
                            ? currentValue * 2.54
                            : currentValue;
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
      return CircleAvatar(
          radius: radius, backgroundImage: FileImage(File(_avatarPath!)));
    }
    if (_remoteAvatarUrl != null && _remoteAvatarUrl!.isNotEmpty) {
      return CircleAvatar(
          radius: radius, backgroundImage: NetworkImage(_remoteAvatarUrl!));
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
