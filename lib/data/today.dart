import 'package:intl/intl.dart';

import 'models/completion.dart';
import 'models/routine_skip.dart';

/// Helpers for "what's true about a routine *today*", in one place so every
/// screen draws the day boundary and reads per-day records the same way.
/// [Completion], [MicroStepProgress], [RoutineSkip] and [AchievedDay] are all
/// keyed by this same "yyyy-MM-dd" local-time day key.

/// The "yyyy-MM-dd" key for [now] (defaults to right now), in local time.
String dayKeyFor([DateTime? now]) => DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

/// Routine ids with a completion recorded on [now]'s day (defaults to today).
Set<String> completedRoutineIdsOn(List<Completion> completions, {DateTime? now}) {
  final key = dayKeyFor(now);
  return {
    for (final c in completions)
      if (c.dateKey == key) c.routineId,
  };
}

/// Routine ids skipped ("넘기기") on [now]'s day (defaults to today).
Set<String> skippedRoutineIdsOn(List<RoutineSkip> skips, {DateTime? now}) {
  final key = dayKeyFor(now);
  return {
    for (final s in skips)
      if (s.dateKey == key) s.routineId,
  };
}
