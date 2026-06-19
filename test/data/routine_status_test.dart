import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/routine_status.dart';

Routine _routine({
  required String id,
  required int startMinute,
  List<int> repeatDays = const [],
}) {
  return Routine(
    id: id,
    segmentId: 's1',
    title: id,
    startMinute: startMinute,
    repeatDays: repeatDays,
  );
}

void main() {
  group('findRoutineStatus', () {
    test('a routine that already started stays current, with no remaining-minutes countdown',
        () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final status = findRoutineStatus([r], 9 * 60 + 10, 1);

      expect(status.routine, r);
      expect(status.isCurrent, true);
      expect(status.remainingMinutes, 0);
    });

    test('stays current arbitrarily long after its start -- no expiry', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final status = findRoutineStatus([r], 9 * 60 + 500, 1);

      expect(status.routine, r);
      expect(status.isCurrent, true);
    });

    test('the most recently started routine wins when several have already started', () {
      final earlier = _routine(id: 'earlier', startMinute: 8 * 60);
      final later = _routine(id: 'later', startMinute: 9 * 60);
      final status = findRoutineStatus([earlier, later], 9 * 60 + 30, 1);

      expect(status.routine, later);
      expect(status.isCurrent, true);
    });

    test('falls back to the soonest upcoming routine when none has started yet', () {
      final soon = _routine(id: 'soon', startMinute: 10 * 60);
      final later = _routine(id: 'later', startMinute: 14 * 60);
      final status = findRoutineStatus([later, soon], 9 * 60, 1);

      expect(status.routine, soon);
      expect(status.isCurrent, false);
      expect(status.remainingMinutes, 60);
    });

    test('skips a routine whose repeatDays excludes today (current pass)', () {
      final weekdaysOnly = _routine(
        id: 'weekdays',
        startMinute: 9 * 60,
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
        repeatDays: const [1, 2, 3, 4, 5],
      );
      final everyday = _routine(id: 'everyday', startMinute: 12 * 60);
      // Saturday = isoWeekday 6: weekdaysOnly must be skipped even though it
      // starts sooner than everyday.
      final status = findRoutineStatus([weekdaysOnly, everyday], 9 * 60, 6);

      expect(status.routine, everyday);
      expect(status.isCurrent, false);
    });

    test('empty repeatDays always matches', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
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

  group('applyTodaysPostponements', () {
    final today = DateTime(2026, 6, 19);

    test('shifts startMinute by today\'s offset for a postponed routine', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final result = applyTodaysPostponements(
        [r],
        [RoutinePostponement.today('r1', 5, at: today)],
        now: today,
      );

      expect(result.single.startMinute, 9 * 60 + 5);
    });

    test('leaves routines with no postponement untouched (same instance)', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final result = applyTodaysPostponements([r], const [], now: today);

      expect(result.single, same(r));
    });

    test('ignores a postponement from a different day', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final yesterday = today.subtract(const Duration(days: 1));
      final result = applyTodaysPostponements(
        [r],
        [RoutinePostponement.today('r1', 5, at: yesterday)],
        now: today,
      );

      expect(result.single.startMinute, 9 * 60);
    });

    test('wraps past midnight', () {
      final r = _routine(id: 'r1', startMinute: 23 * 60 + 50);
      final result = applyTodaysPostponements(
        [r],
        [RoutinePostponement.today('r1', 20, at: today)],
        now: today,
      );

      expect(result.single.startMinute, 10); // 23:50 + 20min wraps to 00:10
    });

    test('only affects the routine the postponement is for', () {
      final a = _routine(id: 'a', startMinute: 9 * 60);
      final b = _routine(id: 'b', startMinute: 10 * 60);
      final result = applyTodaysPostponements(
        [a, b],
        [RoutinePostponement.today('a', 5, at: today)],
        now: today,
      );

      expect(result.firstWhere((r) => r.id == 'a').startMinute, 9 * 60 + 5);
      expect(result.firstWhere((r) => r.id == 'b').startMinute, 10 * 60);
    });
  });
}
