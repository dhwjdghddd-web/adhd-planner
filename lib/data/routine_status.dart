import 'package:intl/intl.dart';

import '../core/time_geometry.dart';
import 'models/routine.dart';
import 'models/routine_postponement.dart';
import 'models/routine_skip.dart';

/// Whatever the home dial and the focus screen agree is "happening now" (or
/// coming up next), for a given moment in time. Both screens must call
/// [findRoutineStatus] rather than keep their own copy, so they never
/// disagree about which routine is current.
class RoutineStatus {
  const RoutineStatus({this.routine, this.isCurrent = false, this.remainingMinutes = 0});

  final Routine? routine;
  final bool isCurrent;
  final int remainingMinutes;
}

/// Finds whichever routine on [isoWeekday] (1=Mon..7=Sun) started most
/// recently at or before [nowMinute] — it stays "current" for the rest of
/// the day, unless it has been completed. Falls back to the soonest routine
/// still ahead today if none has started yet (or if the most recent one was
/// already completed). Routines whose `repeatDays` excludes [isoWeekday] are
/// skipped entirely.
///
/// [completedRoutineIds]: today's completed routine ids (filtered by dateKey).
/// Only the single most-recently-started routine is checked against this set:
/// if it's completed we fall straight through to the "next" search rather
/// than walking backwards through earlier past routines. That prevents the
/// wrong behaviour where completing a routine causes an even earlier one to
/// appear as "지금" instead of the next upcoming one.
RoutineStatus findRoutineStatus(
  List<Routine> routines,
  int nowMinute,
  int isoWeekday, {
  Set<String> completedRoutineIds = const {},
}) {
  // 1. Find the single most-recently-started routine (completed or not).
  Routine? mostRecent;
  var latestStart = -1;
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
    if (routine.startMinute <= nowMinute && routine.startMinute > latestStart) {
      latestStart = routine.startMinute;
      mostRecent = routine;
    }
  }

  // 2. Return it as current only if the user hasn't finished it yet.
  //    If it's already done, fall through — treat the slot as over.
  if (mostRecent != null && !completedRoutineIds.contains(mostRecent.id)) {
    return RoutineStatus(routine: mostRecent, isCurrent: true);
  }

  // 3. No active current routine: find the next upcoming one.
  //    Also skip completed routines here — a completed routine with delta=0
  //    (started exactly at nowMinute) must not reappear as "0분 후 시작".
  Routine? next;
  var bestDelta = TimeGeometry.minutesPerDay + 1;
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
    if (completedRoutineIds.contains(routine.id)) continue;
    final delta = routine.startMinute - nowMinute;
    if (delta >= 0 && delta < bestDelta) {
      bestDelta = delta;
      next = routine;
    }
  }
  if (next == null) return const RoutineStatus();
  return RoutineStatus(routine: next, isCurrent: false, remainingMinutes: bestDelta);
}

/// Overlays today's "미루기" (postpone) offset, if any, onto each routine's
/// `startMinute` — a purely *display* transformation for whatever currently
/// reads "what's happening today" (the home dial, [findRoutineStatus]).
/// Never mutates or re-saves the routine itself; the permanent recurring
/// schedule a [RoutineFormPage] edit would show is untouched. Returns
/// [routines] unchanged (same instances) when nothing today has been
/// postponed, so this is cheap to call on every rebuild.
List<Routine> applyTodaysPostponements(
  List<Routine> routines,
  List<RoutinePostponement> postponements, {
  DateTime? now,
}) {
  final dateKey = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
  final offsetByRoutineId = <String, int>{};
  for (final p in postponements) {
    if (p.dateKey == dateKey) offsetByRoutineId[p.routineId] = p.offsetMinutes;
  }
  if (offsetByRoutineId.isEmpty) return routines;

  return [
    for (final routine in routines)
      if (offsetByRoutineId[routine.id] case final offset?)
        routine.copyWith(
          startMinute: (routine.startMinute + offset) % TimeGeometry.minutesPerDay,
        )
      else
        routine,
  ];
}

/// Removes routines explicitly skipped ("넘기기") for today via
/// [RoutineSkip] from consideration entirely. Unlike postponement (shifts
/// time) or completion (only affects the "지금" pass -- see
/// [findRoutineStatus]'s `completedRoutineIds`), a skip means "don't show
/// this to me today at all": it must not appear as either 지금 or 다음,
/// and reappears normally tomorrow (or its next scheduled day) since
/// [RoutineSkip] is dateKey-scoped. Returns [routines] unchanged when
/// nothing today has been skipped, so this is cheap to call on every
/// rebuild.
List<Routine> excludeTodaysSkips(
  List<Routine> routines,
  List<RoutineSkip> skips, {
  DateTime? now,
}) {
  final dateKey = DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());
  final skippedIds = {
    for (final s in skips)
      if (s.dateKey == dateKey) s.routineId,
  };
  if (skippedIds.isEmpty) return routines;
  return routines.where((r) => !skippedIds.contains(r.id)).toList();
}
