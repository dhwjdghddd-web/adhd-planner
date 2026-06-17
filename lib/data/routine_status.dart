import '../core/time_geometry.dart';
import 'models/routine.dart';

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

/// Finds the routine covering [nowMinute] on [isoWeekday] (1=Mon..7=Sun), or
/// failing that, the soonest upcoming routine that occurs on [isoWeekday].
/// Routines whose `repeatDays` excludes [isoWeekday] are skipped entirely.
RoutineStatus findRoutineStatus(List<Routine> routines, int nowMinute, int isoWeekday) {
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
    if (routine.containsMinute(nowMinute)) {
      final remaining = TimeGeometry.lengthMinutes(nowMinute, routine.endMinute);
      return RoutineStatus(routine: routine, isCurrent: true, remainingMinutes: remaining);
    }
  }

  Routine? next;
  var bestDelta = TimeGeometry.minutesPerDay + 1;
  for (final routine in routines) {
    if (!routine.occursOn(isoWeekday)) continue;
    final delta = TimeGeometry.lengthMinutes(nowMinute, routine.startMinute);
    if (delta < bestDelta) {
      bestDelta = delta;
      next = routine;
    }
  }
  if (next == null) return const RoutineStatus();
  return RoutineStatus(routine: next, isCurrent: false, remainingMinutes: bestDelta);
}
