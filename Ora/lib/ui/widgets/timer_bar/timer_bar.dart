import 'package:flutter/material.dart';

class TimerBar extends StatelessWidget {
  const TimerBar({
    super.key,
    required this.remainingSeconds,
    required this.onStop,
  });

  final int remainingSeconds;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    if (remainingSeconds <= 0) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: Row(
        children: [
          Text('Rest: $remainingSeconds s'),
          const Spacer(),
          TextButton(onPressed: onStop, child: const Text('Stop')),
        ],
      ),
    );
  }
}
