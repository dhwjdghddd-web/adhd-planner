import 'dart:typed_data';

import 'package:timezone/timezone.dart' as tz;

import '../core/time_geometry.dart';
import '../data/models/app_settings.dart';
import '../data/models/routine.dart';

/// Pure, plugin-free scheduling logic for [NotificationService]: turning
/// routines into the exact alarms that should exist, deterministic ids,
/// vibration patterns, and next-occurrence time math. Kept apart from the
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
/// occurrence of either a routine's main alarm or its transition warning.
/// Kept as a plain value (rather than calling the plugin while iterating
/// routines) so [buildSchedule] — the "which alarms should exist" logic —
/// is unit-testable without a real Android runtime.
class ScheduledSpec {
  const ScheduledSpec({
    required this.id,
    required this.routineId,
    required this.isTransition,
    required this.isoWeekday,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final String routineId;
  final bool isTransition;
  final int isoWeekday;
  final int minuteOfDay;
  final String title;
  final String body;

  String get payload => '${isTransition ? 'transition' : 'main'}:$routineId';
}

/// Deterministic notification id for a (routine, weekday, slot) triple, so a
/// later `cancelAll` + reschedule always replaces exactly what it created
/// before. slot 0 = main alarm, 1 = transition warning, 2 = one-off 미루기
/// reschedule of the main alarm, 3 = one-off 미루기 reschedule of the
/// transition warning.
int notificationIdFor(String routineId, int isoWeekday, int slot) {
  final base = routineId.hashCode.abs() % 100000;
  return base * 100 + isoWeekday * 10 + slot;
}

/// Pure: turns the current routine list into the exact set of alarms that
/// should exist on the device. No plugin calls here — [NotificationService
/// .rescheduleAll] is the thin layer that applies this via
/// `flutter_local_notifications`.
List<ScheduledSpec> buildSchedule(List<Routine> routines) {
  final specs = <ScheduledSpec>[];
  for (final routine in routines) {
    if (!routine.alarmEnabled) continue;
    final days = routine.repeatDays.isEmpty
        ? const [1, 2, 3, 4, 5, 6, 7]
        : routine.repeatDays;
    for (final day in days) {
      specs.add(ScheduledSpec(
        id: notificationIdFor(routine.id, day, 0),
        routineId: routine.id,
        isTransition: false,
        isoWeekday: day,
        minuteOfDay: routine.startMinute,
        title: routine.title,
        body: '지금 시작할 시간이에요',
      ));
      if (routine.leadWarningMin > 0) {
        specs.add(ScheduledSpec(
          id: notificationIdFor(routine.id, day, 1),
          routineId: routine.id,
          isTransition: true,
          isoWeekday: day,
          minuteOfDay:
              (routine.startMinute - routine.leadWarningMin) % TimeGeometry.minutesPerDay,
          title: '곧 전환: ${routine.title}',
          body: '${routine.leadWarningMin}분 후 시작해요',
        ));
      }
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
