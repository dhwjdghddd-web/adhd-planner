import 'package:intl/intl.dart';

import 'models/alarm_skip.dart';
import 'models/completion.dart';
import 'models/mit.dart';
import 'models/rest_day.dart';

/// Helpers for "what's true about a block *today*", in one place so every
/// screen draws the day boundary and reads per-day records the same way.
/// [Completion], [MicroStepProgress] and [AchievedDay] are all keyed by this
/// same "yyyy-MM-dd" local-time day key.

/// The "yyyy-MM-dd" key for [now] (defaults to right now), in local time.
String dayKeyFor([DateTime? now]) =>
    DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

/// Block (segment) ids with a completion recorded on [now]'s day (defaults to
/// today).
Set<String> completedBlockIdsOn(List<Completion> completions, {DateTime? now}) {
  final key = dayKeyFor(now);
  return {
    for (final c in completions)
      if (c.dateKey == key) c.segmentId,
  };
}

/// Block (segment) ids whose alarm was explicitly skipped ("오늘은 건너뛰기")
/// on [now]'s day (defaults to today).
Set<String> skippedBlockIdsOn(List<AlarmSkip> skips, {DateTime? now}) {
  final key = dayKeyFor(now);
  return {
    for (final s in skips)
      if (s.dateKey == key) s.segmentId,
  };
}

/// Block (segment) ids marked "오늘의 MIT" (T7) on [now]'s day (defaults to
/// today).
Set<String> mitBlockIdsOn(List<Mit> mits, {DateTime? now}) {
  final key = dayKeyFor(now);
  return {
    for (final m in mits)
      if (m.dateKey == key) m.segmentId,
  };
}

/// Whether [now]'s day (defaults to today) is marked a rest day ("오늘은 쉬기").
bool isRestDayOn(List<RestDay> restDays, {DateTime? now}) {
  final key = dayKeyFor(now);
  return restDays.any((r) => r.dateKey == key);
}

/// The "yyyy-MM-dd" keys of all rest days -- unioned into the streak's achieved
/// set so a rest day never counts as a miss (see streakDateKeys).
Set<String> restDateKeys(List<RestDay> restDays) => {
  for (final r in restDays) r.dateKey,
};
