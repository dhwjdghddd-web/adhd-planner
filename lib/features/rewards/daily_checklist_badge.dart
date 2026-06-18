import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/providers.dart';

/// "오늘 체크리스트 N/M" — every today-applicable routine's micro-step
/// count summed as the denominator, today's checked indices (from
/// [microStepProgressProvider]) summed as the numerator. Shown on the home
/// dial rather than the Focus screen, which deliberately only ever shows
/// one routine at a time.
class DailyChecklistBadge extends ConsumerWidget {
  const DailyChecklistBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(routinesProvider);
    final progressAsync = ref.watch(microStepProgressProvider);
    final theme = Theme.of(context);

    final routines = routinesAsync.value;
    final progress = progressAsync.value;
    if (routines == null || progress == null) return const SizedBox.shrink();

    final today = DateTime.now().weekday;
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final todaysRoutineIds = <String>{};
    var total = 0;
    for (final routine in routines) {
      if (routine.microSteps.isEmpty || !routine.occursOn(today)) continue;
      todaysRoutineIds.add(routine.id);
      total += routine.microSteps.length;
    }
    if (total == 0) return const SizedBox.shrink();

    var done = 0;
    for (final p in progress) {
      if (p.dateKey == dateKey && todaysRoutineIds.contains(p.routineId)) {
        done += p.checkedIndices.length;
      }
    }

    return Semantics(
      label: '오늘 체크리스트 $done / $total 완료',
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.checklist_rtl, size: 16, color: theme.colorScheme.primary),
          const SizedBox(width: 4),
          Text('오늘 체크리스트 $done/$total', style: theme.textTheme.labelMedium),
        ],
      ),
    );
  }
}
