import 'dart:typed_data';

import 'package:intl/intl.dart';
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
    this.scheduleTarget = SegmentScheduleTarget.everyday,
    this.isLeadWarning = false,
    this.dateOverrides = const {},
  });

  final int id;
  final String segmentId;
  final int minuteOfDay;
  final String title;
  final String body;
  final SegmentAlarmType alarmType;
  final SegmentScheduleTarget scheduleTarget;
  // False for the main start-of-block alarm; true for the quiet "전환 예고" heads-up.
  final bool isLeadWarning;
  final Map<String, int> dateOverrides;

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
/// All alarm-enabled blocks stay always armed in the OS, so changing work/rest
/// days never causes missed alarms on subsequent work days.
List<ScheduledSpec> buildSchedule(
  List<Segment> segments, {
  int leadMinutes = 10,
}) {
  final specs = <ScheduledSpec>[];
  for (final segment in segments) {
    if (segment.alarmType == SegmentAlarmType.none) continue;

    specs.add(ScheduledSpec(
      id: notificationIdFor(segment.id, 0),
      segmentId: segment.id,
      minuteOfDay: segment.startMinute,
      title: segment.name,
      body: '지금 시작할 시간이에요',
      alarmType: segment.alarmType,
      scheduleTarget: segment.scheduleTarget,
      dateOverrides: segment.dateOverrides,
    ));

    final effectiveLead = segment.leadWarningMinutes > 0
        ? segment.leadWarningMinutes
        : (segment.leadWarning ? leadMinutes : 0);

    if (effectiveLead > 0) {
      final leadMinuteOfDay = (segment.startMinute - effectiveLead) % 1440;
      final leadOverrides = segment.dateOverrides.map(
        (k, v) => MapEntry(
          k,
          v == Segment.noAlarmMinute
              ? Segment.noAlarmMinute
              : (v - effectiveLead) % 1440,
        ),
      );
      specs.add(ScheduledSpec(
        id: notificationIdFor(segment.id, _leadWarningSlot),
        segmentId: segment.id,
        minuteOfDay: leadMinuteOfDay,
        title: segment.name,
        body: '$effectiveLead분 후 시작해요',
        alarmType: SegmentAlarmType.gentle,
        scheduleTarget: segment.scheduleTarget,
        isLeadWarning: true,
        dateOverrides: leadOverrides,
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

const leadWarningSlot = 1;

/// Whether an alarm firing at [minuteOfDay] has its next occurrence later today
/// (vs already passed, so its next fire is tomorrow).
bool firesLaterToday(int minuteOfDay, {tz.TZDateTime? now}) {
  final current = now ?? tz.TZDateTime.now(tz.local);
  final trigger = nextInstanceOf(minuteOfDay, now: current);
  return trigger.year == current.year &&
      trigger.month == current.month &&
      trigger.day == current.day;
}

/// Helper to test rest day suppression logic.
bool restDaySuppresses(
  int minuteOfDay, {
  required bool restToday,
  required bool restTomorrow,
  tz.TZDateTime? now,
}) {
  final firesToday = firesLaterToday(minuteOfDay, now: now);
  if (firesToday && restToday) return true;
  if (!firesToday && restTomorrow) return true;
  return false;
}

/// Computes the next valid trigger time for a block with [minuteOfDay] and
/// [scheduleTarget], automatically skipping calendar days where alarms are suppressed
/// and applying any specific [dateOverrides].
///
/// For `workDaysOnly`, skips any day whose "yyyy-MM-dd" dateKey is in [restDateKeys].
/// For `restDaysOnly`, skips any day whose "yyyy-MM-dd" dateKey is NOT in [restDateKeys].
/// For `everyday`, triggers at the next occurrence (today if still ahead, else tomorrow).
tz.TZDateTime nextValidTriggerAt({
  required int minuteOfDay,
  required SegmentScheduleTarget scheduleTarget,
  required Set<String> restDateKeys,
  Map<String, int> dateOverrides = const {},
  tz.TZDateTime? now,
}) {
  final current = now ?? tz.TZDateTime.now(tz.local);
  var calendarDay = tz.TZDateTime(tz.local, current.year, current.month, current.day);
  for (var i = 0; i < 365; i++) {
    final dateKey = DateFormat('yyyy-MM-dd').format(calendarDay);
    final isRest = restDateKeys.contains(dateKey);
    final isValid = switch (scheduleTarget) {
      SegmentScheduleTarget.everyday => true,
      SegmentScheduleTarget.workDaysOnly => !isRest,
      SegmentScheduleTarget.restDaysOnly => isRest,
    };
    final isSuppressedByOverride =
        dateOverrides[dateKey] == Segment.noAlarmMinute;
    if (isValid && !isSuppressedByOverride) {
      final effectiveMinute = dateOverrides[dateKey] ?? minuteOfDay;
      final candidate = calendarDay.add(Duration(minutes: effectiveMinute));
      if (candidate.isAfter(current)) {
        return candidate;
      }
    }
    calendarDay = calendarDay.add(const Duration(days: 1));
  }
  return current.add(const Duration(days: 1));
}
