import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/today.dart';
import '../checklist/today_checklist_page.dart';
import 'daily_achievement.dart';

/// "오늘 체크리스트 N/M" — today's (non-skipped) routines' micro-step count
/// as the denominator, today's checked indices as the numerator, via the
/// same [dailyAchievementFor] used by `StreakBadge`'s streak math -- so
/// crossing N/M's halfway point is exactly what makes today count toward
/// the streak, and the icon switches to match `StreakBadge`'s flame the
/// moment it does. Shown on the home dial rather than the Focus screen,
/// which deliberately only ever shows one routine at a time. Tapping it
/// opens [TodayChecklistPage] -- the catch-up surface for routines whose
/// own moment has already passed.
class DailyChecklistBadge extends ConsumerWidget {
  const DailyChecklistBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routinesAsync = ref.watch(routinesProvider);
    final skips = ref.watch(routineSkipsProvider).value ?? const [];
    final completions = ref.watch(completionsProvider).value ?? const [];
    final progressAsync = ref.watch(microStepProgressProvider);
    final theme = Theme.of(context);

    final routines = routinesAsync.value;
    final progress = progressAsync.value;
    if (routines == null || progress == null) return const SizedBox.shrink();

    final today = DateTime.now().weekday;
    final dateKey = dayKeyFor();

    // Visibility is gated on "any routine today" rather than "any
    // micro-steps today" -- this badge is the only entry point to
    // TodayChecklistPage, which needs to stay reachable even for routines
    // that don't use micro-steps at all.
    final hasRoutineToday = routines.any((r) => r.occursOn(today));
    if (!hasRoutineToday) return const SizedBox.shrink();

    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: routines,
      skips: skips,
      completions: completions,
      progress: progress,
    );

    final label = achievement.total > 0
        ? '오늘 체크리스트 ${achievement.checked}/${achievement.total}'
        : '오늘 체크리스트';

    return Semantics(
      button: true,
      label: '$label, 눌러서 전체 목록 보기',
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const TodayChecklistPage()),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                achievement.isAchieved ? Icons.local_fire_department : Icons.checklist_rtl,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              Text(label, style: theme.textTheme.labelMedium),
            ],
          ),
        ),
      ),
    );
  }
}
