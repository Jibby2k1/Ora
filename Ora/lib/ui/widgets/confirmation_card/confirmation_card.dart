import 'package:flutter/material.dart';

import '../../../domain/models/last_logged_set.dart';
import '../glass/glass_card.dart';

class ConfirmationCard extends StatelessWidget {
  const ConfirmationCard({
    super.key,
    required this.lastLogged,
    required this.onUndo,
    required this.onRedo,
    required this.onStartRest,
    required this.undoCount,
    required this.redoCount,
  });

  final LastLoggedSet lastLogged;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onStartRest;
  final int undoCount;
  final int redoCount;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lastLogged.exerciseName,
            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text('Set: ${lastLogged.reps} reps @ ${lastLogged.weight ?? '-'} lb'),
          Text('Role: ${lastLogged.role}${lastLogged.isAmrap ? ' (AMRAP)' : ''}'),
          Text('Today so far: ${lastLogged.sessionSetCount} sets'),
          const SizedBox(height: 8),
          Row(
            children: [
              TextButton(
                onPressed: onStartRest,
                child: const Text('Start Timer'),
              ),
              IconButton(
                onPressed: undoCount > 0 ? onUndo : null,
                icon: const Icon(Icons.undo),
              ),
              Text(undoCount.toString()),
              const SizedBox(width: 12),
              IconButton(
                onPressed: redoCount > 0 ? onRedo : null,
                icon: const Icon(Icons.redo),
              ),
              Text(redoCount.toString()),
            ],
          ),
        ],
      ),
    );
  }
}
