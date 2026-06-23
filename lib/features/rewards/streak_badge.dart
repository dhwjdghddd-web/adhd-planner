import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'daily_achievement.dart';
import 'streak.dart';

/// Small, encouragement-first streak indicator shared by the home dial and
/// the focus screen. Emphasizes the best-ever streak; shows the current one
/// softly alongside it, and never shows a bare "0" — missing a day gets an
/// encouraging line instead of a number that could read as a scolding. A day
/// counts toward the streak via [streakDateKeys]: past days come from the
/// permanent [AchievedDay] store (so editing a routine never restyles
/// history) and today is the live micro-step ratio -- see [DailyAchievement].
class StreakBadge extends ConsumerWidget {
  const StreakBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(segmentsProvider).value ?? const [];
    final achievedDays = ref.watch(achievedDaysProvider).value ?? const [];
    final completionsAsync = ref.watch(completionsProvider);
    final progress = ref.watch(microStepProgressProvider).value ?? const [];
    final theme = Theme.of(context);

    return completionsAsync.when(
      data: (completions) {
        final dateKeys = streakDateKeys(
          achievedDays: achievedDays,
          segments: segments,
          completions: completions,
          progress: progress,
        );
        final current = currentStreak(dateKeys);
        final best = longestStreak(dateKeys);

        return Semantics(
          label: best > 0 ? '최고 연속 $best일, 현재 연속 $current일' : '아직 연속 기록이 없어요',
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.local_fire_department, size: 16, color: theme.colorScheme.primary),
              const SizedBox(width: 4),
              if (best > 0)
                Text('최고 $best일', style: theme.textTheme.labelMedium)
              else
                Text('오늘 하나라도 했으면 충분해요', style: theme.textTheme.labelMedium),
              if (best > 0 && current > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '· 현재 $current일',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ],
          ),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, _) => const SizedBox.shrink(),
    );
  }
}
