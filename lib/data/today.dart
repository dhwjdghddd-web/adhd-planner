import 'package:intl/intl.dart';

import 'models/alarm_skip.dart';
import 'models/completion.dart';

/// Helpers for "what's true about a block *today*", in one place so every
/// screen draws the day boundary and reads per-day records the same way.
/// [Completion], [MicroStepProgress] and [AchievedDay] are all keyed by this
/// same "yyyy-MM-dd" local-time day key.

/// The "yyyy-MM-dd" key for [now] (defaults to right now), in local time.
String dayKeyFor([DateTime? now]) => DateFormat('yyyy-MM-dd').format(now ?? DateTime.now());

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
