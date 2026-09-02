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

/// One concrete alarm that should exist on the device.
class ScheduledSpec {
  const ScheduledSpec({
    required this.id,
    required this.segmentId,
    required this.minuteOfDay,
    required this.title,
    required this.body,
    this.alarmType = SegmentAlarmType.fullScreen,
    this.isLeadWarning = false,
  });

  final int id;
  final String segmentId;
  final int minuteOfDay;
  final String title;
  final String body;
  final SegmentAlarmType alarmType;
  // False for the main start-of-block alarm; true for the quiet "전환 예고" heads-up.
  final bool isLeadWarning;

  String get payload => isLeadWarning ? 'lead:$segmentId' : 'block:$segmentId';
}

/// Deterministic notification id for a block's alarm.
int notificationIdFor(String segmentId, int slot) {
  final base = segmentId.hashCode.abs() % 100000;
  return base * 10 + slot;
}

const _leadWarningSlot = 1;

/// Pure: turns the current block list into the exact set of alarms that should
/// exist on the device.
/// Filters by [isRestDay] against each segment's [scheduleTarget].
List<ScheduledSpec> buildSchedule(
  List<Segment> segments, {
  bool isRestDay = false,
  int leadMinutes = 10,
}) {
  final specs = <ScheduledSpec>[];
  for (final segment in segments) {
    if (segment.alarmType == SegmentAlarmType.none) continue;

    // Check rest/work day filter
    if (isRestDay && segment.scheduleTarget == SegmentScheduleTarget.workDaysOnly) {
      continue;
    }
    if (!isRestDay && segment.scheduleTarget == SegmentScheduleTarget.restDaysOnly) {
      continue;
    }

    specs.add(ScheduledSpec(
      id: notificationIdFor(segment.id, 0),
      segmentId: segment.id,
      minuteOfDay: segment.startMinute,
      title: segment.name,
      body: '지금 시작할 시간이에요',
      alarmType: segment.alarmType,
    ));

    final effectiveLead = segment.leadWarningMinutes > 0
        ? segment.leadWarningMinutes
        : (segment.leadWarning ? leadMinutes : 0);

    if (effectiveLead > 0) {
      final leadMinuteOfDay = (segment.startMinute - effectiveLead) % 1440;
      specs.add(ScheduledSpec(
        id: notificationIdFor(segment.id, _leadWarningSlot),
        segmentId: segment.id,
        minuteOfDay: leadMinuteOfDay,
        title: segment.name,
        body: '$effectiveLead분 후 시작해요',
        alarmType: SegmentAlarmType.gentle,
        isLeadWarning: true,
      ));
    }
  }
  return specs;
}

/// Next moment (today if it's still ahead, otherwise tomorrow) at [minuteOfDay]
/// in the local timezone. Used as the anchor for a daily recurring
/// `zonedSchedule`.
/// [now] defaults to the current moment; pass it only to make a test
/// independent of the wall clock (offsets from a real "now" go wrong near
/// midnight, where +5 minutes is already tomorrow).
tz.TZDateTime nextInstanceOf(int minuteOfDay, {tz.TZDateTime? now}) {
  final from = now ?? tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local, from.year, from.month, from.day, minuteOfDay ~/ 60, minuteOfDay % 60,
  );
  if (!scheduled.isAfter(from)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

/// Whether [minuteOfDay]'s next occurrence lands later TODAY (as opposed to
/// having already passed, so its next fire is tomorrow) — i.e. which calendar
/// day [nextInstanceOf] just picked.
bool firesLaterToday(int minuteOfDay, {tz.TZDateTime? now}) {
  final from = now ?? tz.TZDateTime.now(tz.local);
  final trigger = nextInstanceOf(minuteOfDay, now: from);
  return trigger.year == from.year &&
      trigger.month == from.month &&
      trigger.day == from.day;
}

/// Whether an alarm at [minuteOfDay] must be left **unscheduled** because its
/// next fire lands on a rest day.
///
/// A daily alarm's next fire is either later today or tomorrow, so those two
/// flags between them cover every alarm: "오늘은 쉬기" silences the ones still
/// ahead today, and "내일 쉬기" — set the night before, when today's alarms
/// have all passed already — silences exactly the ones that would next fire
/// tomorrow morning.
///
/// Suppression has to mean *not scheduled at all*: the `matchDateTimeComponents
/// .time` daily repeat re-anchors to the next matching *time* regardless of the
/// scheduled date, so a would-be rest-day alarm can't simply be pushed to the
/// day after. It's left off the device and re-armed by the next reschedule
/// (see app.dart's _DayRolloverAlarmSync, which runs on every date change).
bool restDaySuppresses(
  int minuteOfDay, {
  required bool restToday,
  required bool restTomorrow,
  tz.TZDateTime? now,
}) => firesLaterToday(minuteOfDay, now: now) ? restToday : restTomorrow;
