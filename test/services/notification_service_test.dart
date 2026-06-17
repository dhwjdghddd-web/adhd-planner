import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/services/notification_service.dart';

Routine _routine({
  required String id,
  int startMinute = 9 * 60,
  int leadWarningMin = 5,
  bool alarmEnabled = true,
  List<int> repeatDays = const [],
}) {
  return Routine(
    id: id,
    segmentId: 's1',
    title: 'title-$id',
    startMinute: startMinute,
    alarmEnabled: alarmEnabled,
    leadWarningMin: leadWarningMin,
    repeatDays: repeatDays,
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  group('buildSchedule', () {
    test('alarm-disabled routines produce no specs', () {
      final specs = buildSchedule([_routine(id: 'r1', alarmEnabled: false)]);
      expect(specs, isEmpty);
    });

    test('empty repeatDays expands to all 7 weekdays', () {
      final specs = buildSchedule([_routine(id: 'r1', leadWarningMin: 0)]);
      expect(specs.length, 7);
      expect(specs.map((s) => s.isoWeekday).toSet(), {1, 2, 3, 4, 5, 6, 7});
      expect(specs.every((s) => !s.isTransition), true);
    });

    test('non-empty repeatDays only schedules those weekdays', () {
      final specs =
          buildSchedule([_routine(id: 'r1', leadWarningMin: 0, repeatDays: const [1, 3])]);
      expect(specs.map((s) => s.isoWeekday).toSet(), {1, 3});
      expect(specs.length, 2);
    });

    test('leadWarningMin > 0 adds a transition spec per weekday', () {
      final specs = buildSchedule(
          [_routine(id: 'r1', leadWarningMin: 10, repeatDays: const [1])]);
      expect(specs.length, 2);
      expect(specs.where((s) => s.isTransition).length, 1);
      expect(specs.where((s) => !s.isTransition).length, 1);
    });

    test('leadWarningMin == 0 adds no transition spec', () {
      final specs =
          buildSchedule([_routine(id: 'r1', leadWarningMin: 0, repeatDays: const [1])]);
      expect(specs.length, 1);
      expect(specs.single.isTransition, false);
    });

    test('transition time wraps correctly past midnight', () {
      final specs = buildSchedule([
        _routine(id: 'r1', startMinute: 10, leadWarningMin: 20, repeatDays: const [1]),
      ]);
      final transition = specs.firstWhere((s) => s.isTransition);
      expect(transition.minuteOfDay, 24 * 60 - 10); // 10 - 20 wraps to 1430
    });

    test('main alarm body/title use the routine title', () {
      final specs = buildSchedule(
          [_routine(id: 'r1', leadWarningMin: 0, repeatDays: const [2])]);
      expect(specs.single.title, 'title-r1');
    });

    test('ids never collide across routines, weekdays, or slots', () {
      final specs = buildSchedule([
        _routine(id: 'r1', leadWarningMin: 5, repeatDays: const [1, 2, 3]),
        _routine(id: 'r2', leadWarningMin: 5, repeatDays: const [1, 2, 3]),
      ]);
      final ids = specs.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('notificationIdFor', () {
    test('is deterministic for the same inputs', () {
      expect(notificationIdFor('abc', 1, 0), notificationIdFor('abc', 1, 0));
    });

    test('differs across weekday and slot for the same routine', () {
      final a = notificationIdFor('abc', 1, 0);
      final b = notificationIdFor('abc', 2, 0);
      final c = notificationIdFor('abc', 1, 1);
      expect(a, isNot(b));
      expect(a, isNot(c));
    });
  });

  group('nextInstanceOf', () {
    test('result always lands on the requested weekday and time-of-day', () {
      for (var day = 1; day <= 7; day++) {
        final result = nextInstanceOf(day, 9 * 60 + 30);
        expect(result.weekday, day, reason: 'day $day');
        expect(result.hour, 9);
        expect(result.minute, 30);
      }
    });

    test('result is always strictly in the future', () {
      final now = tz.TZDateTime.now(tz.local);
      final result = nextInstanceOf(now.weekday, now.hour * 60 + now.minute);
      expect(result.isAfter(now), true);
    });
  });
}
