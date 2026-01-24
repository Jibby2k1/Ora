import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:firebase_auth/firebase_auth.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/settings_repo.dart';
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

  @override
  void initState() {
    super.initState();
    _settingsRepo = SettingsRepo(AppDatabase.instance);
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
    final rows = _demoTrainingScores(
      audience: widget.audience,
      muscles: _selectedMuscles.isEmpty ? _muscleOptions : _selectedMuscles.toList(),
      metric: _metric,
    );

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        GlassCard(
          child: ListTile(
            title: Text(widget.title),
            subtitle: Text(widget.subtitle),
            trailing: Icon(widget.icon),
            onTap: widget.onTap,
          ),
        ),
        const SizedBox(height: 12),
        const GlassCard(
          child: ListTile(
            title: Text('Status'),
            subtitle: Text('Not connected yet'),
          ),
        ),
        const SizedBox(height: 12),
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
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final muscle in _muscleOptions)
                    FilterChip(
                      label: Text(muscle),
                      selected: _selectedMuscles.contains(muscle),
                      onSelected: (selected) {
                        setState(() {
                          if (selected) {
                            _selectedMuscles.add(muscle);
                          } else {
                            _selectedMuscles.remove(muscle);
                          }
                        });
                      },
                    ),
                ],
              ),
              const SizedBox(height: 12),
              ...rows.map((row) => ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: CircleAvatar(child: Text(row.rank.toString())),
                    title: Text(row.name),
                    subtitle: Text('${_metric.label}: ${row.displayValue}'),
                  )),
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

class _TrainingRow {
  _TrainingRow(this.name, this.value, this.rank, this.displayValue);

  final String name;
  final double value;
  final int rank;
  final String displayValue;
}

const _muscleOptions = [
  'Chest',
  'Back',
  'Lats',
  'Upper Back',
  'Traps',
  'Shoulders',
  'Front Delts',
  'Side Delts',
  'Rear Delts',
  'Biceps',
  'Triceps',
  'Forearms',
  'Abs',
  'Obliques',
  'Quads',
  'Hamstrings',
  'Glutes',
  'Calves',
  'Adductors',
  'Abductors',
  'Hip Flexors',
];

List<_TrainingRow> _demoTrainingScores({
  required String audience,
  required List<String> muscles,
  required _TrainingMetric metric,
}) {
  final names = ['You', 'Avery', 'Jordan', 'Taylor', 'Riley', 'Morgan'];
  final rows = <_TrainingRow>[];
  for (final name in names) {
    final seed = _hash('$audience|${metric.name}|${muscles.join(',')}|$name');
    double value;
    String display;
    switch (metric) {
      case _TrainingMetric.pr:
        value = 135 + (seed % 120);
        display = '${value.toStringAsFixed(0)} lb';
        break;
      case _TrainingMetric.volume:
        value = 8000 + (seed % 9000);
        display = value.toStringAsFixed(0);
        break;
      case _TrainingMetric.prCount:
        value = 2 + (seed % 12);
        display = value.toStringAsFixed(0);
        break;
    }
    rows.add(_TrainingRow(name, value, 0, display));
  }
  rows.sort((a, b) => b.value.compareTo(a.value));
  for (var i = 0; i < rows.length; i++) {
    rows[i] = _TrainingRow(rows[i].name, rows[i].value, i + 1, rows[i].displayValue);
  }
  return rows;
}

int _hash(String input) {
  var h = 0;
  for (final code in input.codeUnits) {
    h = (h * 31 + code) & 0x7fffffff;
  }
  return h;
}

class MathHelper {
  static double nthRoot(double value, int n) {
    if (value <= 0) return 0;
    return value == 0 ? 0 : math.pow(value, 1 / n).toDouble();
  }
}
