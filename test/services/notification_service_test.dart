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
  // Defaults to false here (unlike the model's own default of true) so the
  // pre-existing single-alarm tests below stay focused on the main alarm only
  // -- tests about the lead-warning itself pass true explicitly.
  bool leadWarning = false,
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
    leadWarning: leadWarning,
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

    test('an alarm-enabled block schedules exactly one daily start alarm', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.length, 1);
    });

    test('the spec fires at the block start minute', () {
      final specs = buildSchedule([_block(id: 's1', startMinute: 7 * 60 + 30)]);
      expect(specs.single.minuteOfDay, 7 * 60 + 30);
    });

    test('spec title uses the block name', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.first.title, 'name-s1');
    });

    test('payload identifies the block', () {
      final specs = buildSchedule([_block(id: 's1')]);
      expect(specs.first.payload, 'block:s1');
    });

    test('ids never collide across blocks', () {
      final specs = buildSchedule([_block(id: 's1'), _block(id: 's2')]);
      final ids = specs.map((s) => s.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('leadWarning off produces only the main alarm spec', () {
      final specs = buildSchedule([_block(id: 's1', leadWarning: false)]);
      expect(specs.length, 1);
      expect(specs.single.isLeadWarning, isFalse);
    });

    test('leadWarning on adds a second, lead-warning spec for the same block', () {
      final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
      expect(specs.length, 2);
      expect(specs.where((s) => s.isLeadWarning).length, 1);
    });

    test('the lead-warning fires leadMinutes before the block start', () {
      final specs = buildSchedule(
        [_block(id: 's1', startMinute: 9 * 60, leadWarning: true)],
        leadMinutes: 10,
      );
      final lead = specs.firstWhere((s) => s.isLeadWarning);
      expect(lead.minuteOfDay, 9 * 60 - 10);
    });

    test('the lead-warning wraps past midnight for a very early block start', () {
      final specs = buildSchedule(
        [_block(id: 's1', startMinute: 5, leadWarning: true)],
        leadMinutes: 10,
      );
      final lead = specs.firstWhere((s) => s.isLeadWarning);
      expect(lead.minuteOfDay, 1435); // 23:55 the previous night
    });

    test('the lead-warning payload is tagged lead, not block, so a tap is a no-op', () {
      final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
      final lead = specs.firstWhere((s) => s.isLeadWarning);
      expect(lead.payload, 'lead:s1');
    });

    test('the main alarm and its lead-warning never share a notification id', () {
      final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
      final ids = specs.map((s) => s.id).toSet();
      expect(ids.length, specs.length);
    });
  });

  group('notificationIdFor', () {
    test('is deterministic for the same inputs', () {
      expect(notificationIdFor('abc', 0), notificationIdFor('abc', 0));
    });

    test('differs across blocks for the same slot', () {
      expect(notificationIdFor('abc', 0), isNot(notificationIdFor('xyz', 0)));
    });
  });

  group('nextInstanceOf', () {
    test('result lands on the requested time-of-day', () {
      final result = nextInstanceOf(9 * 60 + 30);
      expect(result.hour, 9);
      expect(result.minute, 30);
    });

    test('result is always strictly in the future', () {
      final now = tz.TZDateTime.now(tz.local);
      final result = nextInstanceOf(now.hour * 60 + now.minute);
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
