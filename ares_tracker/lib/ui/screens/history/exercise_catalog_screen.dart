import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/exercise_repo.dart';
import 'history_screen.dart';

class ExerciseCatalogScreen extends StatefulWidget {
  const ExerciseCatalogScreen({super.key});

  @override
  State<ExerciseCatalogScreen> createState() => _ExerciseCatalogScreenState();
}

class _ExerciseCatalogScreenState extends State<ExerciseCatalogScreen> {
  late final ExerciseRepo _exerciseRepo;
  final _controller = TextEditingController();
  List<Map<String, Object?>> _results = [];

  @override
  void initState() {
    super.initState();
    _exerciseRepo = ExerciseRepo(AppDatabase.instance);
    _loadAll();
  }

  Future<void> _loadAll() async {
    final all = await _exerciseRepo.getAll();
    setState(() {
      _results = all;
    });
  }

  Future<void> _search(String query) async {
    if (query.trim().isEmpty) {
      await _loadAll();
      return;
    }
    final results = await _exerciseRepo.search(query, limit: 200);
    setState(() {
      _results = results;
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Exercise Catalog'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: 'Search exercises',
                border: OutlineInputBorder(),
              ),
              onChanged: _search,
            ),
          ),
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: _results.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final item = _results[index];
                return ListTile(
                  title: Text(item['canonical_name'] as String),
                  subtitle: Text(item['equipment_type'] as String),
                  trailing: IconButton(
                    icon: const Icon(Icons.show_chart),
                    onPressed: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HistoryScreen(initialExerciseId: item['id'] as int),
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
