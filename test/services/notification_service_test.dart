import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
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
  TestWidgetsFlutterBinding.ensureInitialized();

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

    test(
      'leadWarning on adds a second, lead-warning spec for the same block',
      () {
        final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
        expect(specs.length, 2);
        expect(specs.where((s) => s.isLeadWarning).length, 1);
      },
    );

    test('the lead-warning fires leadMinutes before the block start', () {
      final specs = buildSchedule([
        _block(id: 's1', startMinute: 9 * 60, leadWarning: true),
      ], leadMinutes: 10);
      final lead = specs.firstWhere((s) => s.isLeadWarning);
      expect(lead.minuteOfDay, 9 * 60 - 10);
    });

    test(
      'the lead-warning wraps past midnight for a very early block start',
      () {
        final specs = buildSchedule([
          _block(id: 's1', startMinute: 5, leadWarning: true),
        ], leadMinutes: 10);
        final lead = specs.firstWhere((s) => s.isLeadWarning);
        expect(lead.minuteOfDay, 1435); // 23:55 the previous night
      },
    );

    test(
      'the lead-warning payload is tagged lead, not block, so a tap is a no-op',
      () {
        final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
        final lead = specs.firstWhere((s) => s.isLeadWarning);
        expect(lead.payload, 'lead:s1');
      },
    );

    test(
      'the main alarm and its lead-warning never share a notification id',
      () {
        final specs = buildSchedule([_block(id: 's1', leadWarning: true)]);
        final ids = specs.map((s) => s.id).toSet();
        expect(ids.length, specs.length);
      },
    );

    test('buildSchedule always keeps all active blocks armed with their scheduleTarget preserved', () {
      final workBlock = _block(id: 'w1').copyWith(
        scheduleTarget: SegmentScheduleTarget.workDaysOnly,
      );
      final restBlock = _block(id: 'r1').copyWith(
        scheduleTarget: SegmentScheduleTarget.restDaysOnly,
      );
      final everyBlock = _block(id: 'e1').copyWith(
        scheduleTarget: SegmentScheduleTarget.everyday,
      );

      final specs = buildSchedule([workBlock, restBlock, everyBlock]);
      final ids = specs.map((s) => s.segmentId).toList();
      expect(ids, contains('w1'));
      expect(ids, contains('r1'));
      expect(ids, contains('e1'));

      expect(specs.firstWhere((s) => s.segmentId == 'w1').scheduleTarget, SegmentScheduleTarget.workDaysOnly);
      expect(specs.firstWhere((s) => s.segmentId == 'r1').scheduleTarget, SegmentScheduleTarget.restDaysOnly);
      expect(specs.firstWhere((s) => s.segmentId == 'e1').scheduleTarget, SegmentScheduleTarget.everyday);
    });

    test('gentle and hapticOnly alarmTypes are passed correctly to ScheduledSpec', () {
      final gentleBlock = _block(id: 'g1').copyWith(
        alarmType: SegmentAlarmType.gentle,
      );
      final hapticBlock = _block(id: 'h1').copyWith(
        alarmType: SegmentAlarmType.hapticOnly,
      );

      final specs = buildSchedule([gentleBlock, hapticBlock]);
      expect(specs.firstWhere((s) => s.segmentId == 'g1').alarmType, SegmentAlarmType.gentle);
      expect(specs.firstWhere((s) => s.segmentId == 'h1').alarmType, SegmentAlarmType.hapticOnly);
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

    test(
      'presets differ from each other (picking one actually changes something)',
      () {
        final patterns = AlarmVibrationPattern.values
            .map(vibrationPatternFor)
            .toList();
        for (var i = 0; i < patterns.length; i++) {
          for (var j = i + 1; j < patterns.length; j++) {
            expect(patterns[i], isNot(patterns[j]), reason: '$i vs $j');
          }
        }
      },
    );
  });

  group('handleNotificationResponse', () {
    const channel = MethodChannel('com.adhdplanner.adhd_planner/alarm_sound');

    setUp(() {
      pendingAlarmAlert.value = null;
    });
    tearDown(() {
      pendingAlarmAlert.value = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test(
      'opening the alarm screen (a real tap or the system auto-launching it) '
      "queues the pending alert WITHOUT silencing the ring/vibration -- only "
      "AlarmScreen's own actions (or the power-button guard, or the 60s "
      'timeout) do that (regression: a past version silenced it the instant '
      'the screen turned on, before the user had any chance to notice or '
      'respond)',
      () async {
        final calls = <MethodCall>[];
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              calls.add(call);
              return null;
            });

        handleNotificationResponse(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: 123,
            payload: 'block:s1',
          ),
        );
        // Let the (intentionally absent) silencing have a chance to run if it
        // existed -- nothing here is awaited inside the handler, so a microtask
        // pump is enough to surface a regression.
        await Future<void>.delayed(Duration.zero);

        expect(pendingAlarmAlert.value?.notificationId, 123);
        expect(pendingAlarmAlert.value?.segmentId, 's1');
        expect(calls.where((c) => c.method == 'cancelVibrationAlarm'), isEmpty);
      },
    );

    test(
      'a non-block payload (e.g. the lead-warning notification) is ignored',
      () async {
        handleNotificationResponse(
          const NotificationResponse(
            notificationResponseType:
                NotificationResponseType.selectedNotification,
            id: 999,
            payload: 'lead:s1',
          ),
        );

        expect(pendingAlarmAlert.value, isNull);
      },
    );

    test('tapping the daily check-in reminder queues pendingCheckinAlert', () {
      addTearDown(() => pendingCheckinAlert.value = false);

      handleNotificationResponse(
        const NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotification,
          id: -2,
          payload: 'checkin',
        ),
      );

      expect(pendingCheckinAlert.value, true);
      // Distinct from the block-alarm path -- a checkin tap never sets this.
      expect(pendingAlarmAlert.value, isNull);
    });
  });

  group('rest-day suppression', () {
    // A fixed evening "now" (local zone is UTC here, see setUpAll) so these
    // never depend on when the suite happens to run -- offsets from the real
    // clock go wrong near midnight, where +5 minutes is already tomorrow.
    //
    // A function, not a `final` in the group body: group bodies run while the
    // suite is still being collected, before setUpAll has called
    // setLocalLocation, so touching tz.local out here throws
    // "Field '_local' has not been initialized".
    tz.TZDateTime bedtime() => tz.TZDateTime(tz.local, 2026, 6, 18, 23, 0);
    const morningAlarm = 7 * 60; // 07:00 -- already passed, next fire tomorrow
    const lateTonight = 23 * 60 + 30; // 23:30 -- still ahead today

    test("firesLaterToday separates today's alarms from tomorrow's", () {
      expect(firesLaterToday(lateTonight, now: bedtime()), isTrue);
      expect(firesLaterToday(morningAlarm, now: bedtime()), isFalse);
    });

    test('nothing is suppressed when neither day is a rest day', () {
      for (final m in [lateTonight, morningAlarm]) {
        expect(
          restDaySuppresses(
            m,
            restToday: false,
            restTomorrow: false,
            now: bedtime(),
          ),
          isFalse,
        );
      }
    });

    test('오늘은 쉬기 drops only what is still ahead today', () {
      expect(
        restDaySuppresses(
          lateTonight,
          restToday: true,
          restTomorrow: false,
          now: bedtime(),
        ),
        isTrue,
      );
      // The morning alarm already passed today, so its next fire is tomorrow --
      // not a rest day here, so it stays armed as usual.
      expect(
        restDaySuppresses(
          morningAlarm,
          restToday: true,
          restTomorrow: false,
          now: bedtime(),
        ),
        isFalse,
      );
    });

    test('내일 쉬기 drops tomorrow morning while tonight carries on', () {
      // The whole point of the feature: set at bedtime, the morning alarm never
      // fires. "오늘은 쉬기" cannot do this -- 07:00 already passed today.
      expect(
        restDaySuppresses(
          morningAlarm,
          restToday: false,
          restTomorrow: true,
          now: bedtime(),
        ),
        isTrue,
      );
      expect(
        restDaySuppresses(
          lateTonight,
          restToday: false,
          restTomorrow: true,
          now: bedtime(),
        ),
        isFalse,
      );
    });

    test('both days off suppresses every alarm', () {
      for (final m in [lateTonight, morningAlarm]) {
        expect(
          restDaySuppresses(
            m,
            restToday: true,
            restTomorrow: true,
            now: bedtime(),
          ),
          isTrue,
        );
      }
    });
  });

  group('nextValidTriggerAt', () {
    tz.TZDateTime fixedNow() => tz.TZDateTime(tz.local, 2026, 6, 18, 10, 0); // 10:00 AM on 2026-06-18
    const afternoonMinute = 14 * 60; // 14:00 (ahead today)
    const morningMinute = 7 * 60; // 07:00 (already passed today)

    test('workDaysOnly triggers today when today is not a rest day', () {
      final trigger = nextValidTriggerAt(
        minuteOfDay: afternoonMinute,
        scheduleTarget: SegmentScheduleTarget.workDaysOnly,
        restDateKeys: {},
        now: fixedNow(),
      );
      expect(trigger, tz.TZDateTime(tz.local, 2026, 6, 18, 14, 0));
    });

    test('workDaysOnly skips today when today is a rest day', () {
      final trigger = nextValidTriggerAt(
        minuteOfDay: afternoonMinute,
        scheduleTarget: SegmentScheduleTarget.workDaysOnly,
        restDateKeys: {'2026-06-18'}, // today is rest day
        now: fixedNow(),
      );
      expect(trigger, tz.TZDateTime(tz.local, 2026, 6, 19, 14, 0));
    });

    test('workDaysOnly skips multiple consecutive rest days', () {
      final trigger = nextValidTriggerAt(
        minuteOfDay: morningMinute,
        scheduleTarget: SegmentScheduleTarget.workDaysOnly,
        restDateKeys: {'2026-06-19', '2026-06-20'}, // tomorrow and day after are rest days
        now: fixedNow(),
      );
      expect(trigger, tz.TZDateTime(tz.local, 2026, 6, 21, 7, 0));
    });

    test('restDaysOnly skips work days and lands on next rest day', () {
      final trigger = nextValidTriggerAt(
        minuteOfDay: afternoonMinute,
        scheduleTarget: SegmentScheduleTarget.restDaysOnly,
        restDateKeys: {'2026-06-20'}, // Saturday is rest day
        now: fixedNow(),
      );
      expect(trigger, tz.TZDateTime(tz.local, 2026, 6, 20, 14, 0));
    });

    test('everyday triggers at next occurrence regardless of rest days', () {
      final trigger = nextValidTriggerAt(
        minuteOfDay: afternoonMinute,
        scheduleTarget: SegmentScheduleTarget.everyday,
        restDateKeys: {'2026-06-18'},
        now: fixedNow(),
      );
      expect(trigger, tz.TZDateTime(tz.local, 2026, 6, 18, 14, 0));
    });
  });
}
