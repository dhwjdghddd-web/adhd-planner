import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/services/notification_service.dart';

Segment _block({
  required String id,
  int startMinute = 9 * 60,
  bool alarmEnabled = true,
}) {
  return Segment(
    id: id,
    name: 'name-$id',
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: startMinute + 60,
    order: 0,
    alarmEnabled: alarmEnabled,
  );
}

void main() {
  setUpAll(() {
    tz_data.initializeTimeZones();
    tz.setLocalLocation(tz.UTC);
  });

  group('buildSchedule', () {
    test('alarm-disabled blocks produce no specs', () {
      final specs = buildSchedule([_block(id: 's1', alarmEnabled: false)]);
      expect(specs, isEmpty);
    });

    test('an alarm-enabled block schedules one start alarm on every weekday', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.length, 7);
      expect(specs.map((s) => s.isoWeekday).toSet(), {1, 2, 3, 4, 5, 6, 7});
    });

    test('every spec fires at the block start minute', () {
      final specs = buildSchedule([_block(id: 's1', startMinute: 7 * 60 + 30)]);
      expect(specs.every((s) => s.minuteOfDay == 7 * 60 + 30), true);
    });

    test('spec title uses the block name', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.first.title, 'name-s1');
    });

    test('payload identifies the block', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.first.payload, 'block:s1');
    });

    test('ids never collide across blocks or weekdays', () {
      final specs = buildSchedule([_block(id: 's1'), _block(id: 's2')]);
      final ids = specs.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });
  });

  group('notificationIdFor', () {
    test('is deterministic for the same inputs', () {
      expect(notificationIdFor('abc', 1, 0), notificationIdFor('abc', 1, 0));
    });

    test('differs across weekday for the same block', () {
      expect(notificationIdFor('abc', 1, 0), isNot(notificationIdFor('abc', 2, 0)));
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

  group('vibrationPatternFor', () {
    test('every preset starts with a zero delay and is non-empty', () {
      for (final preset in AlarmVibrationPattern.values) {
        final pattern = vibrationPatternFor(preset);
        expect(pattern, isNotEmpty, reason: preset.name);
        expect(pattern.first, 0, reason: preset.name);
      }
    });

    test('presets differ from each other (picking one actually changes something)', () {
      final patterns = AlarmVibrationPattern.values.map(vibrationPatternFor).toList();
      for (var i = 0; i < patterns.length; i++) {
        for (var j = i + 1; j < patterns.length; j++) {
          expect(patterns[i], isNot(patterns[j]), reason: '$i vs $j');
        }
      }
    });
  });
}
