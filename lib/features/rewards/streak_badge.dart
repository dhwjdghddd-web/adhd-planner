import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import 'daily_achievement.dart';
import 'streak.dart';

/// Small, encouragement-first streak indicator shared by the home dial and
/// the focus screen. Emphasizes the best-ever streak; shows the current one
/// softly alongside it, and never shows a bare "0" — missing a day gets an
/// encouraging line instead of a number that could read as a scolding, and a
/// streak that just dropped to 0 (current == 0 but a best > 0 exists) gets a
/// warm "다시 시작해도 좋아요" cue rather than silently showing nothing. A day
/// counts toward the streak via [streakDateKeys]: past days come from the
/// permanent [AchievedDay] store (so editing a routine never restyles
/// history) and today is the live micro-step ratio -- see [DailyAchievement].
/// Note: [currentStreak]/[longestStreak] already forgive up to 2 missed days
/// (`freezeAllowance`) before actually breaking a streak -- that's the
/// "유예일" grace mechanism, implemented at that layer rather than here.
class StreakBadge extends ConsumerWidget {
  const StreakBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(segmentsProvider).value ?? const [];
    final achievedDays = ref.watch(achievedDaysProvider).value ?? const [];
    final completionsAsync = ref.watch(completionsProvider);
    final progress = ref.watch(microStepProgressProvider).value ?? const [];
    final restDays = ref.watch(restDaysProvider).value ?? const [];
    final theme = Theme.of(context);

    return completionsAsync.when(
      data: (completions) {
        final dateKeys = streakDateKeys(
          achievedDays: achievedDays,
          segments: segments,
          completions: completions,
          progress: progress,
          restDays: restDays,
        );
        final current = currentStreak(dateKeys);
        final best = longestStreak(dateKeys);

        // Never speak a bare "0" even in the accessible label -- a streak that
        // just dropped to 0 gets a warm "다시 시작" cue instead of a number that
        // could read as a scolding.
        final String label;
        if (best == 0) {
          label = '아직 연속 기록이 없어요';
        } else if (current > 0) {
          label = '최고 연속 $best일, 현재 연속 $current일';
        } else {
          label = '최고 연속 $best일, 다시 시작해도 좋아요';
        }

        return Semantics(
          label: label,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.local_fire_department,
                size: 16,
                color: theme.colorScheme.primary,
              ),
              const SizedBox(width: 4),
              if (best > 0)
                Text('최고 $best일', style: theme.textTheme.labelMedium)
              else
                Text('오늘 하나라도 했으면 충분해요', style: theme.textTheme.labelMedium),
              if (best > 0 && current > 0) ...[
                const SizedBox(width: 6),
                Text(
                  '· 현재 $current일',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ] else if (best > 0 && current == 0) ...[
                const SizedBox(width: 6),
                Text(
                  '· 다시 시작해도 좋아요',
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
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
