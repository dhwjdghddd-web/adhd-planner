import '../../data/models/completion.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/routine.dart';
import '../../data/models/routine_skip.dart';

/// A single calendar day's progress toward "achieved" status, counted from
/// micro-steps rather than whole-routine completion. [total]/[checked] only
/// cover routines that occurred that weekday and weren't 넘기기'd that day --
/// a skipped routine's steps don't drag the day down, but they also can't
/// help it.
class DailyAchievement {
  const DailyAchievement({
    required this.checked,
    required this.total,
    required this.hasAnyCompletion,
  });

  final int checked;
  final int total;
  final bool hasAnyCompletion;

  /// Half or more of the day's (non-skipped) micro-steps checked counts as
  /// achieved. Days with no micro-steps to count at all (nothing scheduled
  /// used them, or everything that did was skipped) fall back to the old,
  /// whole-routine rule -- any completion that day -- so routines that don't
  /// use micro-steps never become impossible to build a streak with.
  bool get isAchieved => total == 0 ? hasAnyCompletion : checked / total >= 0.5;
}

DailyAchievement dailyAchievementFor({
  required String dateKey,
  required List<Routine> routines,
  required List<RoutineSkip> skips,
  required List<Completion> completions,
  required List<MicroStepProgress> progress,
}) {
  final isoWeekday = DateTime.parse(dateKey).weekday;
  final skippedIds = {
    for (final s in skips) if (s.dateKey == dateKey) s.routineId,
  };
  final considered = {
    for (final r in routines)
      if (r.occursOn(isoWeekday) && !skippedIds.contains(r.id)) r.id: r,
  };

  var total = 0;
  for (final r in considered.values) {
    total += r.microSteps.length;
  }

  var checked = 0;
  for (final p in progress) {
    if (p.dateKey != dateKey) continue;
    final r = considered[p.routineId];
    if (r == null) continue;
    checked += p.checkedIndices.where((i) => i >= 0 && i < r.microSteps.length).length;
  }

  final hasAnyCompletion = completions.any((c) => c.dateKey == dateKey);
  return DailyAchievement(checked: checked, total: total, hasAnyCompletion: hasAnyCompletion);
}

/// Every calendar day (by [Completion]/[MicroStepProgress] date-key) that
/// counts as achieved under [DailyAchievement.isAchieved] -- the set streaks
/// are built from.
Set<String> achievedDateKeys({
  required List<Routine> routines,
  required List<RoutineSkip> skips,
  required List<Completion> completions,
  required List<MicroStepProgress> progress,
}) {
  final candidates = {
    ...completions.map((c) => c.dateKey),
    ...progress.map((p) => p.dateKey),
  };
  return candidates.where((dateKey) {
    return dailyAchievementFor(
      dateKey: dateKey,
      routines: routines,
      skips: skips,
      completions: completions,
      progress: progress,
    ).isAchieved;
  }).toSet();
}
