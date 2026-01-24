import 'package:flutter/material.dart';

import '../../../data/db/db.dart';
import '../../../data/repositories/program_repo.dart';
import '../../../data/repositories/workout_repo.dart';
import '../../../domain/services/session_service.dart';
import '../session/session_screen.dart';
import '../../widgets/glass/glass_background.dart';
import '../../widgets/glass/glass_card.dart';

class DayPickerScreen extends StatefulWidget {
  const DayPickerScreen({super.key, required this.programId});

  final int programId;

  @override
  State<DayPickerScreen> createState() => _DayPickerScreenState();
}

class _DayPickerScreenState extends State<DayPickerScreen> {
  late final ProgramRepo _programRepo;
  late final WorkoutRepo _workoutRepo;
  late final SessionService _sessionService;

  @override
  void initState() {
    super.initState();
    final db = AppDatabase.instance;
    _programRepo = ProgramRepo(db);
    _workoutRepo = WorkoutRepo(db);
    _sessionService = SessionService(db);
  }

  Future<void> _startSession(int programDayId) async {
    final contextData = await _sessionService.startSessionForProgramDay(
      programId: widget.programId,
      programDayId: programDayId,
    );
    if (!mounted) return;
    await Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => SessionScreen(contextData: contextData)),
    );
  }

  Future<void> _startSmartDay(List<Map<String, Object?>> days) async {
    if (days.isEmpty) return;
    final lastIndex = await _workoutRepo.getLastCompletedDayIndex(widget.programId);
    final nextIndex = lastIndex == null ? 0 : (lastIndex + 1) % days.length;
    final day = days.firstWhere((d) => d['day_index'] == nextIndex, orElse: () => days.first);
    await _startSession(day['id'] as int);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Pick Day'),
      ),
      body: Stack(
        children: [
          const GlassBackground(),
          FutureBuilder<List<Map<String, Object?>>>(
            future: _programRepo.getProgramDays(widget.programId),
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Center(child: CircularProgressIndicator());
              }
              final days = snapshot.data ?? [];
              if (days.isEmpty) {
                return const Center(child: Text('No days yet. Add one in the program editor.'));
              }
              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: GlassCard(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Row(
                        children: [
                          const Icon(Icons.auto_awesome),
                          const SizedBox(width: 12),
                          const Expanded(child: Text('Start Smart Day')),
                          TextButton(
                            onPressed: () => _startSmartDay(days),
                            child: const Text('Start'),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      itemCount: days.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 12),
                      itemBuilder: (context, index) {
                        final day = days[index];
                        return GlassCard(
                          padding: EdgeInsets.zero,
                          child: ListTile(
                            title: Text(day['day_name'] as String),
                            subtitle: Text("Day ${(day['day_index'] as int) + 1}"),
                            trailing: const Icon(Icons.chevron_right),
                            onTap: () => _startSession(day['id'] as int),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
