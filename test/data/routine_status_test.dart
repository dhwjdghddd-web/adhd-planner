import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
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

    test('completing the most-recent routine falls through to next -- does NOT go backwards', () {
      // This is the key regression: before the fix, completing C would show B
      // (an earlier routine) as "지금". After the fix it shows D (next future)
      // or nothing -- never a past routine.
      final a = _routine(id: 'a', startMinute: 20 * 60); // 20:00
      final b = _routine(id: 'b', startMinute: 21 * 60); // 21:00
      final c = _routine(id: 'c', startMinute: 22 * 60); // 22:00  ← most recent
      final d = _routine(id: 'd', startMinute: 23 * 60); // 23:00  ← not started yet

      // At 22:30, C is most recently started (not completed) → current.
      final before = findRoutineStatus([a, b, c, d], 22 * 60 + 30, 1);
      expect(before.routine, c);
      expect(before.isCurrent, true);

      // After completing C: most recent (C) is done → fall through to next.
      // D starts at 23:00 which is still in the future → shown as "next".
      // A or B (older past routines) must NOT appear as "지금".
      final after = findRoutineStatus(
        [a, b, c, d],
        22 * 60 + 30,
        1,
        completedRoutineIds: {'c'},
      );
      expect(after.routine, d);
      expect(after.isCurrent, false);
      expect(after.remainingMinutes, 30); // 23:00 - 22:30
    });

    test('completing the most-recent routine shows nothing when no future routines remain', () {
      final a = _routine(id: 'a', startMinute: 20 * 60);
      final b = _routine(id: 'b', startMinute: 21 * 60);
      final c = _routine(id: 'c', startMinute: 22 * 60); // ← most recent, no routines after

      // At 22:30, completing C: no future routines → null (오늘 일정 없어요).
      final status = findRoutineStatus(
        [a, b, c],
        22 * 60 + 30,
        1,
        completedRoutineIds: {'c'},
      );
      expect(status.routine, isNull);
      expect(status.isCurrent, false);
    });

    test('completed routine with delta=0 does not reappear as "0분 후 시작"', () {
      // Regression: completing A at exactly its startMinute (delta=0) used to
      // show A again in the next search as remainingMinutes=0 ("0분 후 시작").
      final a = _routine(id: 'a', startMinute: 10 * 60); // 10:00
      final b = _routine(id: 'b', startMinute: 11 * 60); // 11:00

      // At 10:00, A has just started (delta=0). After completing it,
      // A must NOT appear as "다음" — B should be shown instead.
      final status = findRoutineStatus(
        [a, b],
        10 * 60,
        1,
        completedRoutineIds: {'a'},
      );
      expect(status.routine, b);
      expect(status.isCurrent, false);
      expect(status.remainingMinutes, 60); // 11:00 - 10:00
    });

    test('completing the most-recent routine (when the previous is also completed) shows next', () {
      final done1 = _routine(id: 'done1', startMinute: 9 * 60);  // 09:00
      final done2 = _routine(id: 'done2', startMinute: 10 * 60); // 10:00 ← most recent
      final upcoming = _routine(id: 'next', startMinute: 11 * 60); // 11:00 (not started)
      // At 10:30, done2 is most recent and completed → fall through.
      // upcoming starts at 11:00, delta=30 → shown as next.
      final status = findRoutineStatus(
        [done1, done2, upcoming],
        10 * 60 + 30,
        1,
        completedRoutineIds: {'done1', 'done2'},
      );
      expect(status.routine, upcoming);
      expect(status.isCurrent, false);
      expect(status.remainingMinutes, 30);
    });

    test('completing the only started routine shows nothing current', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final status = findRoutineStatus(
        [r],
        9 * 60 + 10,
        1,
        completedRoutineIds: {'r1'},
      );
      expect(status.routine, isNull);
      expect(status.isCurrent, false);
    });

    test('empty completedRoutineIds behaves identically to the default', () {
      final r = _routine(id: 'r1', startMinute: 9 * 60);
      final withEmpty = findRoutineStatus([r], 9 * 60 + 10, 1, completedRoutineIds: {});
      final withDefault = findRoutineStatus([r], 9 * 60 + 10, 1);
      expect(withEmpty.routine, withDefault.routine);
      expect(withEmpty.isCurrent, withDefault.isCurrent);
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

  group('excludeTodaysSkips', () {
    final today = DateTime(2026, 6, 19);

    test('removes a routine skipped today entirely from the list', () {
      final a = _routine(id: 'a', startMinute: 9 * 60);
      final b = _routine(id: 'b', startMinute: 10 * 60);
      final result = excludeTodaysSkips(
        [a, b],
        [RoutineSkip.today('a', at: today)],
        now: today,
      );

      expect(result, [b]);
    });

    test('leaves the list unchanged (same instance) when nothing is skipped today', () {
      final a = _routine(id: 'a', startMinute: 9 * 60);
      final routines = [a];
      final result = excludeTodaysSkips(routines, const [], now: today);

      expect(result, same(routines));
    });

    test('ignores a skip from a different day', () {
      final a = _routine(id: 'a', startMinute: 9 * 60);
      final yesterday = today.subtract(const Duration(days: 1));
      final result = excludeTodaysSkips(
        [a],
        [RoutineSkip.today('a', at: yesterday)],
        now: today,
      );

      expect(result, [a]);
    });

    test('a skipped-then-excluded routine falls through to next in findRoutineStatus', () {
      final a = _routine(id: 'a', startMinute: 9 * 60);
      final b = _routine(id: 'b', startMinute: 11 * 60);
      final visible = excludeTodaysSkips(
        [a, b],
        [RoutineSkip.today('a', at: today)],
        now: today,
      );
      final status = findRoutineStatus(visible, 9 * 60 + 30, today.weekday);

      expect(status.routine, b);
      expect(status.isCurrent, false);
    });
  });
}
