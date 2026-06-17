import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/routine_status.dart';

Routine _routine({
  required String id,
  required int startMinute,
  required int durationMin,
  List<int> repeatDays = const [],
}) {
  return Routine(
    id: id,
    segmentId: 's1',
    title: id,
    startMinute: startMinute,
    durationMin: durationMin,
    repeatDays: repeatDays,
  );
}

void main() {
  group('findRoutineStatus', () {
    test('returns the routine covering nowMinute as current', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60, durationMin: 30);
      final status = findRoutineStatus([r], 9 * 60 + 10, 1);

      expect(status.routine, r);
      expect(status.isCurrent, true);
      expect(status.remainingMinutes, 20);
    });

    test('falls back to the soonest upcoming routine when none is current', () {
      final soon = _routine(id: 'soon', startMinute: 10 * 60, durationMin: 30);
      final later = _routine(id: 'later', startMinute: 14 * 60, durationMin: 30);
      final status = findRoutineStatus([later, soon], 9 * 60, 1);

      expect(status.routine, soon);
      expect(status.isCurrent, false);
      expect(status.remainingMinutes, 60);
    });

    test('skips a routine whose repeatDays excludes today (current pass)', () {
      final weekdaysOnly = _routine(
        id: 'weekdays',
        startMinute: 9 * 60,
        durationMin: 30,
        repeatDays: const [1, 2, 3, 4, 5],
      );
      // Saturday = isoWeekday 6, routine does not occur.
      final status = findRoutineStatus([weekdaysOnly], 9 * 60 + 10, 6);

      expect(status.routine, isNull);
    });

    test('skips a routine whose repeatDays excludes today (next pass)', () {
      final weekdaysOnly = _routine(
        id: 'weekdays',
        startMinute: 10 * 60,
        durationMin: 30,
        repeatDays: const [1, 2, 3, 4, 5],
      );
      final everyday = _routine(id: 'everyday', startMinute: 12 * 60, durationMin: 30);
      // Saturday = isoWeekday 6: weekdaysOnly must be skipped even though it
      // starts sooner than everyday.
      final status = findRoutineStatus([weekdaysOnly, everyday], 9 * 60, 6);

      expect(status.routine, everyday);
      expect(status.isCurrent, false);
    });

    test('empty repeatDays always matches', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60, durationMin: 30);
      for (var day = 1; day <= 7; day++) {
        final status = findRoutineStatus([r], 9 * 60 + 5, day);
        expect(status.routine, r, reason: 'day $day');
      }
    });

    test('no routines returns the default status', () {
      final status = findRoutineStatus(const [], 9 * 60, 1);
      expect(status.routine, isNull);
      expect(status.isCurrent, false);
      expect(status.remainingMinutes, 0);
    });
  });
}
