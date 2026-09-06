import 'package:intl/intl.dart';

import 'models/alarm_skip.dart';
import 'models/completion.dart';
import 'models/mit.dart';
import 'models/rest_day.dart';
import 'models/segment.dart';

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

/// Midnight of the day *after* [now] (defaults to today), in local time. Built
/// by incrementing the day field -- which DateTime normalises across month/year
/// ends -- rather than adding 24h, so it lands on the right calendar day even
/// on a DST shift (a 23h or 25h day).
DateTime tomorrowOf([DateTime? now]) {
  final n = now ?? DateTime.now();
  return DateTime(n.year, n.month, n.day + 1);
}

/// Whether [now]'s day (defaults to today) is marked a rest day ("오늘은 쉬기").
bool isRestDayOn(List<RestDay> restDays, {DateTime? now}) {
  final key = dayKeyFor(now);
  return restDays.any((r) => r.dateKey == key && r.presetId == 'rest');
}

/// Returns the assigned preset id for [now]'s day, defaulting to 'work'.
String effectivePresetIdOn(List<RestDay> restDays, {DateTime? now}) {
  final key = dayKeyFor(now);
  for (final r in restDays) {
    if (r.dateKey == key) return r.presetId;
  }
  return 'work';
}

/// Whether the day *after* [now] (defaults to tomorrow) is marked a rest day
/// ("내일 쉬기" -- set the night before so the morning's alarms stay silent).
/// Same records as [isRestDayOn]: a rest day is just a date key, so tomorrow's
/// mark simply becomes today's once the date rolls over.
bool isRestDayTomorrow(List<RestDay> restDays, {DateTime? now}) =>
    isRestDayOn(restDays, now: tomorrowOf(now));

/// The "yyyy-MM-dd" keys of all rest days -- unioned into the streak's achieved
/// set so a rest day never counts as a miss (see streakDateKeys).
Set<String> restDateKeys(List<RestDay> restDays) => {
  for (final r in restDays)
    if (r.presetId == 'rest') r.dateKey,
};

/// Filters segments applicable for [now]'s day based on preset or rest day state,
/// and applies any specific date overrides for start/end minutes.
List<Segment> todaySegments(
  List<Segment> allSegments, {
  bool? isRestDay,
  String? activePresetId,
  DateTime? now,
}) {
  final key = dayKeyFor(now);
  final targetPresetId = activePresetId ?? ((isRestDay ?? false) ? 'rest' : 'work');

  return allSegments.where((s) {
    if (s.presetId == targetPresetId) return true;

    // Backward compatibility for segments that haven't set presetId explicitly
    if (targetPresetId == 'rest') {
      return s.scheduleTarget == SegmentScheduleTarget.restDaysOnly;
    } else if (targetPresetId == 'work') {
      return s.scheduleTarget != SegmentScheduleTarget.restDaysOnly;
    }
    return false;
  }).map((s) {
    final ovStart = s.startMinuteFor(key);
    final ovEnd = s.endMinuteFor(key);
    if (ovStart != s.startMinute || ovEnd != s.endMinute) {
      return s.copyWith(startMinute: ovStart, endMinute: ovEnd);
    }
    return s;
  }).toList();
}
