import 'package:intl/intl.dart';

import '../../data/models/achieved_day.dart';
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
/// counts as achieved under [DailyAchievement.isAchieved], computed from the
/// *current* routine list. Used only to seed [AchievedDay] records the first
/// time the streak store is populated (a one-off backfill of pre-existing
/// history) -- ongoing streaks read the persisted records via [streakDateKeys]
/// instead, so later routine edits can't shift a day that was already earned.
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

/// The day-key set streaks are actually built from: every day already
/// recorded as achieved (permanent -- see [AchievedDay]), plus today if it
/// meets the bar *right now*. Today is always recomputed live so crossing the
/// 50% mark updates the streak immediately, before the recorder's write has
/// round-tripped through storage -- and so that un-checking back below the bar
/// before the day is over is still reflected, since today hasn't been
/// permanently banked yet. Every *past* day comes only from [achievedDays],
/// never recomputed, which is the whole point: a routine edited or deleted
/// today can't reach back and undo a day that was already earned.
Set<String> streakDateKeys({
  required List<AchievedDay> achievedDays,
  required List<Routine> routines,
  required List<RoutineSkip> skips,
  required List<Completion> completions,
  required List<MicroStepProgress> progress,
  DateTime? now,
}) {
  final todayKey = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
  final keys = {
    // Past days only: today is governed by the live check below, not by a
    // record that may have been banked earlier today and since fallen back.
    for (final d in achievedDays)
      if (d.dateKey != todayKey) d.dateKey,
  };
  final todayAchieved = dailyAchievementFor(
    dateKey: todayKey,
    routines: routines,
    skips: skips,
    completions: completions,
    progress: progress,
  ).isAchieved;
  if (todayAchieved) keys.add(todayKey);
  return keys;
}
