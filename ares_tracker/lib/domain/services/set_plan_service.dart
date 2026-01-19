class SetPlanBlock {
  SetPlanBlock({
    required this.id,
    required this.orderIndex,
    required this.role,
    required this.setCount,
    required this.amrapLastSet,
  });

  final int id;
  final int orderIndex;
  final String role;
  final int setCount;
  final bool amrapLastSet;

  factory SetPlanBlock.fromRow(Map<String, Object?> row) {
    return SetPlanBlock(
      id: row['id'] as int,
      orderIndex: row['order_index'] as int,
      role: row['role'] as String,
      setCount: row['set_count'] as int,
      amrapLastSet: (row['amrap_last_set'] as int? ?? 0) == 1,
    );
  }
}

class SetPlanResult {
  SetPlanResult({required this.nextRole, required this.isAmrap});

  final String nextRole;
  final bool isAmrap;
}

class SetPlanService {
  SetPlanResult? nextExpected({
    required List<SetPlanBlock> blocks,
    required List<Map<String, Object?>> existingSets,
  }) {
    if (blocks.isEmpty) return null;
    final setsByRole = <String, int>{};
    for (final set in existingSets) {
      final role = set['set_role'] as String?;
      if (role == null) continue;
      setsByRole.update(role, (v) => v + 1, ifAbsent: () => 1);
    }

    final ordered = List<SetPlanBlock>.from(blocks)..sort((a, b) => a.orderIndex.compareTo(b.orderIndex));
    for (final block in ordered) {
      final completed = setsByRole[block.role] ?? 0;
      if (completed < block.setCount) {
        final isLastSet = completed == block.setCount - 1;
        return SetPlanResult(
          nextRole: block.role,
          isAmrap: block.amrapLastSet && isLastSet,
        );
      }
    }
    final last = ordered.last;
    return SetPlanResult(nextRole: last.role, isAmrap: false);
  }
}
