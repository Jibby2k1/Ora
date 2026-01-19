import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/program_repo.dart';
import '../day_picker/day_picker_screen.dart';
import 'program_editor_screen.dart';

class ProgramsScreen extends StatefulWidget {
  const ProgramsScreen({super.key});

  @override
  State<ProgramsScreen> createState() => _ProgramsScreenState();
}

class _ProgramsScreenState extends State<ProgramsScreen> {
  late final ProgramRepo _programRepo;

  @override
  void initState() {
    super.initState();
    _programRepo = ProgramRepo(AppDatabase.instance);
  }

  Future<void> _createProgram() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('New Program'),
          content: TextField(
            controller: controller,
            decoration: const InputDecoration(labelText: 'Program name'),
            autofocus: true,
          ),
          actions: [
            TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(controller.text.trim()),
              child: const Text('Create'),
            ),
          ],
        );
      },
    );

    final name = result ?? '';
    if (name.isEmpty) return;
    final programId = await _programRepo.createProgram(name: name);
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ProgramEditorScreen(programId: programId)),
    );
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Programs'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: _createProgram,
          ),
        ],
      ),
      body: FutureBuilder<List<Map<String, Object?>>>(
        future: _programRepo.getPrograms(),
        builder: (context, snapshot) {
          if (snapshot.connectionState != ConnectionState.done) {
            return const Center(child: CircularProgressIndicator());
          }
          final programs = snapshot.data ?? [];
          if (programs.isEmpty) {
            return const Center(child: Text('Create your first program.'));
          }
          return ListView.separated(
            padding: const EdgeInsets.all(16),
            itemCount: programs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final program = programs[index];
              final id = program['id'] as int;
              return ListTile(
                tileColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                title: Text(program['name'] as String),
                subtitle: const Text('Tap to start or edit days'),
                onTap: () async {
                  await Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => DayPickerScreen(programId: id)),
                  );
                  setState(() {});
                },
                trailing: IconButton(
                  icon: const Icon(Icons.edit),
                  onPressed: () async {
                    await Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => ProgramEditorScreen(programId: id)),
                    );
                    setState(() {});
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
