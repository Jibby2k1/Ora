import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
import '../../widgets/consent/cloud_consent.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Leaderboard'),
        actions: const [SizedBox(width: 72)],
      ),
      body: const LeaderboardContent(showBackground: true),
    );
  }
}

class LeaderboardContent extends StatefulWidget {
  const LeaderboardContent({super.key, required this.showBackground});

  final bool showBackground;

  @override
  State<LeaderboardContent> createState() => _LeaderboardContentState();
}

class _LeaderboardContentState extends State<LeaderboardContent> {
  late final SettingsRepo _settingsRepo;

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
  }

  @override
  Widget build(BuildContext context) {
    final content = DefaultTabController(
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
                  onTap: () async {
                    if (FirebaseAuth.instance.currentUser == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sign in to access leaderboards.')),
                      );
                      return;
                    }
                    final ok = await CloudConsent.ensureLeaderboardConsent(context, _settingsRepo);
                    if (!ok || !context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Friends leaderboard coming soon.')),
                    );
                  },
                ),
                _LeaderboardTab(
                  title: 'Global',
                  subtitle: 'Optional, with warning + consent',
                  icon: Icons.public,
                  audience: 'global',
                  onTap: () async {
                    if (FirebaseAuth.instance.currentUser == null) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Sign in to access leaderboards.')),
                      );
                      return;
                    }
                    final ok = await CloudConsent.ensureLeaderboardConsent(context, _settingsRepo);
                    if (!ok || !context.mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Global leaderboard coming soon.')),
                    );
                  },
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: GlassCard(
              child: const ListTile(
                title: Text('Scoring'),
                subtitle: Text('Geometric mean (placeholder)'),
              ),
            ),
          ),
        ],
      ),
    );

    if (!widget.showBackground) {
      return content;
    }

    return Stack(
      children: [
        const GlassBackground(),
        content,
      ],
    );
  }
}

class _LeaderboardTab extends StatelessWidget {
  const _LeaderboardTab({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.audience,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String audience;

  @override
  Widget build(BuildContext context) {
    return _TrainingLeaderboard(
      title: title,
      subtitle: subtitle,
      icon: icon,
      onTap: onTap,
      audience: audience,
    );
  }
}

List<_ScoreRow> _demoScores() {
  final raw = [
    _ScoreRow('Avery', 82, 76, 70),
    _ScoreRow('Jordan', 75, 88, 64),
    _ScoreRow('Taylor', 68, 72, 90),
  ];
  final scored = raw.map((row) => row.withScore()).toList();
  scored.sort((a, b) => b.score.compareTo(a.score));
  for (var i = 0; i < scored.length; i++) {
    scored[i].rank = i + 1;
  }
  return scored;
}

class _ScoreRow {
  _ScoreRow(this.name, this.workout, this.diet, this.appearance);

  final String name;
  final double workout;
  final double diet;
  final double appearance;
  double score = 0;
  int rank = 0;

  _ScoreRow withScore() {
    final values = [workout, diet, appearance];
    final product = values.fold<double>(1, (acc, v) => acc * v);
    score = product == 0 ? 0 : MathHelper.nthRoot(product, values.length);
    return this;
  }
}

class _TrainingLeaderboard extends StatefulWidget {
  const _TrainingLeaderboard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    required this.audience,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final String audience;

  @override
  State<_TrainingLeaderboard> createState() => _TrainingLeaderboardState();
}

class _TrainingLeaderboardState extends State<_TrainingLeaderboard> {
  final Set<String> _selectedMuscles = {};
  _TrainingMetric _metric = _TrainingMetric.pr;

  @override
  Widget build(BuildContext context) {
    final scores = _demoScores();
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        GlassCard(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.title, style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(widget.subtitle, style: Theme.of(context).textTheme.bodySmall),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _MetricChip(
                    label: 'PR',
                    selected: _metric == _TrainingMetric.pr,
                    onTap: () => setState(() => _metric = _TrainingMetric.pr),
                  ),
                  _MetricChip(
                    label: 'Volume',
                    selected: _metric == _TrainingMetric.volume,
                    onTap: () => setState(() => _metric = _TrainingMetric.volume),
                  ),
                  _MetricChip(
                    label: 'Consistency',
                    selected: _metric == _TrainingMetric.consistency,
                    onTap: () => setState(() => _metric = _TrainingMetric.consistency),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton.icon(
                  onPressed: widget.onTap,
                  icon: const Icon(Icons.cloud_upload),
                  label: const Text('Join leaderboard'),
                ),
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
              const Text('Filters'),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final group in ['Chest', 'Back', 'Shoulders', 'Legs', 'Arms'])
                    FilterChip(
                      label: Text(group),
                      selected: _selectedMuscles.contains(group),
                      onSelected: (value) {
                        setState(() {
                          if (value) {
                            _selectedMuscles.add(group);
                          } else {
                            _selectedMuscles.remove(group);
                          }
                        });
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
            children: [
              for (final row in scores)
                ListTile(
                  leading: CircleAvatar(child: Text('${row.rank}')),
                  title: Text(row.name),
                  subtitle: Text('Workout ${row.workout.toInt()} · Diet ${row.diet.toInt()} · App ${row.appearance.toInt()}'),
                  trailing: Text(row.score.toStringAsFixed(1)),
                ),
            ],
          ),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MetricChip extends StatelessWidget {
  const _MetricChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withOpacity(0.2) : scheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: scheme.primary.withOpacity(selected ? 0.45 : 0.15)),
        ),
        child: Text(label),
      ),
    );
  }
}

enum _TrainingMetric { pr, volume, consistency }

class MathHelper {
  static double nthRoot(double value, int n) {
    return math.pow(value, 1 / n).toDouble();
  }
}
