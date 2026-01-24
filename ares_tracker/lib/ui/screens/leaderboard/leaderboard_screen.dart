import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../../core/cloud/leaderboard_service.dart';
import '../../widgets/consent/cloud_consent.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key});

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  late final SettingsRepo _settingsRepo;
  late final LeaderboardService _leaderboardService;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
    _leaderboardService = LeaderboardService(AppDatabase.instance);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          DefaultTabController(
            length: 2,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: const TabBar(
                      tabs: [
                        Tab(text: 'Friends'),
                        Tab(text: 'Global'),
                      ],
                    ),
                  ),
                ),
                Expanded(
                  child: TabBarView(
                    children: [
                      _LeaderboardTab(
                        title: 'Friends',
                        subtitle: 'Requires account + consent',
                        icon: Icons.group,
                        audience: 'friends',
                        settingsRepo: _settingsRepo,
                        service: _leaderboardService,
                      ),
                      _LeaderboardTab(
                        title: 'Global',
                        subtitle: 'Optional, with warning + consent',
                        icon: Icons.public,
                        audience: 'global',
                        settingsRepo: _settingsRepo,
                        service: _leaderboardService,
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: GlassCard(
                    child: const ListTile(
                      title: Text('Scoring'),
                      subtitle: Text('Geometric mean of training/diet/appearance (placeholder).'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.audience,
    required this.settingsRepo,
    required this.service,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String audience;
  final SettingsRepo settingsRepo;
  final LeaderboardService service;

  @override
  Widget build(BuildContext context) {
    return _TrainingLeaderboard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      audience: audience,
      settingsRepo: settingsRepo,
      service: service,
    );
  }
}

class _TrainingLeaderboard extends StatefulWidget {
  const _TrainingLeaderboard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.audience,
    required this.settingsRepo,
    required this.service,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final String audience;
  final SettingsRepo settingsRepo;
  final LeaderboardService service;

  @override
  State<_TrainingLeaderboard> createState() => _TrainingLeaderboardState();
}

class _TrainingLeaderboardState extends State<_TrainingLeaderboard> {
  final Set<String> _selectedMuscles = {};
  _TrainingMetric _metric = _TrainingMetric.pr;
  final _friendController = TextEditingController();
  bool _consented = false;

  @override
  void dispose() {
    _friendController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        GlassCard(
          child: ListTile(
            title: Text(widget.title),
            subtitle: Text(widget.subtitle),
            trailing: Icon(widget.icon),
            onTap: () async {
              if (FirebaseAuth.instance.currentUser == null) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Sign in to access leaderboards.')),
                );
                return;
              }
              final ok = await CloudConsent.ensureLeaderboardConsent(context, widget.settingsRepo);
              if (!ok || !context.mounted) return;
              setState(() => _consented = true);
            },
          ),
        ),
        const SizedBox(height: 12),
        GlassCard(
          child: ListTile(
            title: const Text('Status'),
            subtitle: Text(_consented ? 'Connected' : 'Awaiting consent'),
            trailing: ElevatedButton(
              onPressed: _consented
                  ? () async {
                      await widget.service.syncScores();
                      if (!mounted) return;
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Leaderboard synced.')),
                      );
                    }
                  : null,
              child: const Text('Sync'),
            ),
          ),
        ),
        const SizedBox(height: 12),
        if (widget.audience == 'friends') ...[
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                StreamBuilder<List<String>>(
                  stream: widget.service.watchFriends(),
                  builder: (context, snapshot) {
                    final friends = snapshot.data ?? const <String>[];
                    final user = FirebaseAuth.instance.currentUser;
                    return Row(
                      children: [
                        const Expanded(child: Text('Friends')),
                        Text(
                          friends.isNotEmpty ? '${friends.length} saved' : 'None yet',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton.icon(
                          onPressed: user == null
                              ? null
                              : () async {
                                  await Clipboard.setData(ClipboardData(text: user.uid));
                                  if (!context.mounted) return;
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    const SnackBar(content: Text('Your UID copied.')),
                                  );
                                },
                          icon: const Icon(Icons.copy, size: 16),
                          label: const Text('Copy my UID'),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _friendController,
                  decoration: const InputDecoration(
                    labelText: 'Add friend by UID',
                  ),
                ),
                const SizedBox(height: 8),
                Align(
                  alignment: Alignment.centerRight,
                  child: ElevatedButton(
                    onPressed: () async {
                      final uid = _friendController.text.trim();
                      if (uid.isEmpty) return;
                      await widget.service.addFriend(uid);
                      _friendController.clear();
                    },
                    child: const Text('Add friend'),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
        ],
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Training Focus (placeholder)'),
              const SizedBox(height: 8),
              Row(
                children: [
                  const Expanded(child: Text('Metric')),
                  DropdownButton<_TrainingMetric>(
                    value: _metric,
                    items: _TrainingMetric.values
                        .map((metric) => DropdownMenuItem(
                              value: metric,
                              child: Text(metric.label),
                            ))
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _metric = value);
                    },
                  ),
                ],
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
              const Text('Rankings'),
              const SizedBox(height: 8),
              if (!_consented)
                const Text('Enable consent and sync to view rankings.')
              else
                StreamBuilder<List<LeaderboardRow>>(
                  stream: widget.audience == 'friends'
                      ? widget.service.watchFriends().asyncExpand(
                          (uids) => widget.service.watchFriendScores(uids),
                        )
                      : widget.service.watchGlobalScores(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const Center(child: CircularProgressIndicator());
                    }
                    final rows = snapshot.data!;
                    if (rows.isEmpty) {
                      return const Text('No leaderboard entries yet.');
                    }
                    return Column(
                      children: [
                        for (var i = 0; i < rows.length; i++)
                          ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: CircleAvatar(
                              backgroundColor: Theme.of(context).colorScheme.primary.withOpacity(0.15),
                              child: Text('${i + 1}'),
                            ),
                            title: Text(rows[i].displayName),
                            subtitle: Text('Score ${rows[i].score.toStringAsFixed(1)}'),
                            trailing: Text('Train ${rows[i].trainingScore.toStringAsFixed(0)}'),
                          ),
                      ],
                    );
                  },
                ),
            ],
          ),
        ),
      ],
    );
  }
}

enum _TrainingMetric {
  pr('PR'),
  volume('Volume'),
  prCount('PR Count');

  const _TrainingMetric(this.label);

  final String label;
}
