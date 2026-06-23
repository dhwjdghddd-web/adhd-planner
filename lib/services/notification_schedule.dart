import 'dart:typed_data';

import 'package:timezone/timezone.dart' as tz;

import '../data/models/app_settings.dart';
import '../data/models/segment.dart';

/// Pure, plugin-free scheduling logic for [NotificationService]: turning
/// blocks (segments) into the exact alarms that should exist, deterministic
/// ids, vibration patterns, and next-occurrence time math. Kept apart from the
/// `flutter_local_notifications`/platform-channel side so all of this stays
/// unit-testable without a real Android runtime (see notification_service_test).

/// The actual millisecond vibration pattern for each named preset in
/// [AlarmVibrationPattern] — `[pause, on, off, on, off, ...]`, same
/// convention as `Vibrator.vibrate(long[])`.
Int64List vibrationPatternFor(AlarmVibrationPattern preset) {
  switch (preset) {
    case AlarmVibrationPattern.defaultPattern:
      return Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]);
    case AlarmVibrationPattern.short:
      return Int64List.fromList([0, 300, 200, 300, 200, 300, 200, 300, 200, 300]);
    case AlarmVibrationPattern.long:
      return Int64List.fromList([0, 2000, 1000, 2000, 1000, 2000]);
    case AlarmVibrationPattern.doublePulse:
      return Int64List.fromList([0, 250, 150, 250, 600, 250, 150, 250, 600]);
  }
}

/// Total length of one full [preset] cycle in ms — how long a single
/// vibration burst lasts before it would repeat.
int vibrationCycleMs(AlarmVibrationPattern preset) =>
    vibrationPatternFor(preset).fold(0, (sum, ms) => sum + ms);

/// One concrete alarm that should exist on the device: a single weekday
/// occurrence of a block's start-of-block alarm. Kept as a plain value (rather
/// than calling the plugin while iterating blocks) so [buildSchedule] — the
/// "which alarms should exist" logic — is unit-testable without a real Android
/// runtime.
class ScheduledSpec {
  const ScheduledSpec({
    required this.id,
    required this.segmentId,
    required this.isoWeekday,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final String segmentId;
  final int isoWeekday;
  final int minuteOfDay;
  final String title;
  final String body;

  String get payload => 'block:$segmentId';
}

/// Deterministic notification id for a (block, weekday) pair, so a later
/// `cancelAll` + reschedule always replaces exactly what it created before.
/// [slot] is kept (always 0 for the single start alarm) so the id shape stays
/// compatible with the device-side request-code tracking.
int notificationIdFor(String segmentId, int isoWeekday, int slot) {
  final base = segmentId.hashCode.abs() % 100000;
  return base * 100 + isoWeekday * 10 + slot;
}

/// Pure: turns the current block list into the exact set of alarms that should
/// exist on the device — one start-of-block alarm per alarm-enabled block, on
/// every weekday (blocks recur daily). No plugin calls here —
/// [NotificationService.rescheduleAll] is the thin layer that applies this.
List<ScheduledSpec> buildSchedule(List<Segment> segments) {
  final specs = <ScheduledSpec>[];
  for (final segment in segments) {
    if (!segment.alarmEnabled) continue;
    for (var day = 1; day <= 7; day++) {
      specs.add(ScheduledSpec(
        id: notificationIdFor(segment.id, day, 0),
        segmentId: segment.id,
        isoWeekday: day,
        minuteOfDay: segment.startMinute,
        title: segment.name,
        body: '지금 시작할 시간이에요',
      ));
    }
  }
  return specs;
}

/// Next moment (today or later) that lands on [isoWeekday] (1=Mon..7=Sun) at
/// [minuteOfDay], in the local timezone. Used as the anchor for a weekly
/// recurring `zonedSchedule`.
tz.TZDateTime nextInstanceOf(int isoWeekday, int minuteOfDay) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local, now.year, now.month, now.day, minuteOfDay ~/ 60, minuteOfDay % 60,
  );
  while (scheduled.weekday != isoWeekday || !scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}
