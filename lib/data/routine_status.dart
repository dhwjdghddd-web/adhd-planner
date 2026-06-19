import 'package:intl/intl.dart';

import '../core/time_geometry.dart';
import 'models/routine.dart';
import 'models/routine_postponement.dart';

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
/// recently at or before [nowMinute] -- it stays "current" for the rest of
/// the day, however long that actually takes, rather than expiring after
/// some fixed duration: there's no length to set on a [Routine] for exactly
/// this reason, since "ran out of time" isn't a state this app wants to put
/// anyone in. Falls back to the soonest routine still ahead today if none
/// has started yet. Routines whose `repeatDays` excludes [isoWeekday] are
/// skipped entirely.
RoutineStatus findRoutineStatus(List<Routine> routines, int nowMinute, int isoWeekday) {
  Routine? current;
  var latestStart = -1;
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
    if (routine.startMinute <= nowMinute && routine.startMinute > latestStart) {
      latestStart = routine.startMinute;
      current = routine;
    }
  }
  if (current != null) {
    return RoutineStatus(routine: current, isCurrent: true);
  }

  Routine? next;
  var bestDelta = TimeGeometry.minutesPerDay + 1;
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
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
