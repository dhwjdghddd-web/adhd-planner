import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/alarm_skip.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/mit.dart';
import 'package:adhd_planner/data/models/rest_day.dart';
import 'package:adhd_planner/data/today.dart';

void main() {
  test('dayKeyFor formats the given moment as a yyyy-MM-dd local key', () {
    expect(dayKeyFor(DateTime(2026, 6, 8, 23, 59)), '2026-06-08');
  });

  test('completedBlockIdsOn keeps only the given day, ignoring other days', () {
    final completions = [
      const Completion(dateKey: '2026-06-18', segmentId: 'a', completedAtIso: ''),
      const Completion(dateKey: '2026-06-18', segmentId: 'b', completedAtIso: ''),
      const Completion(dateKey: '2026-06-17', segmentId: 'c', completedAtIso: ''),
    ];
    expect(
      completedBlockIdsOn(completions, now: DateTime(2026, 6, 18)),
      {'a', 'b'},
    );
  });

  test('skippedBlockIdsOn keeps only the given day, ignoring other days', () {
    final skips = [
      const AlarmSkip(dateKey: '2026-06-18', segmentId: 'a'),
      const AlarmSkip(dateKey: '2026-06-18', segmentId: 'b'),
      const AlarmSkip(dateKey: '2026-06-17', segmentId: 'c'),
    ];
    expect(
      skippedBlockIdsOn(skips, now: DateTime(2026, 6, 18)),
      {'a', 'b'},
    );
  });

  test('a block not skipped today is absent even if skipped on another day', () {
    final skips = [const AlarmSkip(dateKey: '2026-06-17', segmentId: 'a')];
    expect(skippedBlockIdsOn(skips, now: DateTime(2026, 6, 18)), isEmpty);
  });

  test('mitBlockIdsOn keeps only the given day, ignoring other days', () {
    final mits = [
      const Mit(dateKey: '2026-06-18', segmentId: 'a'),
      const Mit(dateKey: '2026-06-18', segmentId: 'b'),
      const Mit(dateKey: '2026-06-17', segmentId: 'c'),
    ];
    expect(mitBlockIdsOn(mits, now: DateTime(2026, 6, 18)), {'a', 'b'});
  });

  test('a block not marked MIT today is absent even if marked on another day', () {
    final mits = [const Mit(dateKey: '2026-06-17', segmentId: 'a')];
    expect(mitBlockIdsOn(mits, now: DateTime(2026, 6, 18)), isEmpty);
  });

  group('tomorrowOf', () {
    test('is the next calendar day', () {
      expect(dayKeyFor(tomorrowOf(DateTime(2026, 6, 18, 23, 30))), '2026-06-19');
    });

    test('rolls over a month end', () {
      expect(dayKeyFor(tomorrowOf(DateTime(2026, 6, 30, 22, 0))), '2026-07-01');
    });

    test('rolls over a year end', () {
      expect(dayKeyFor(tomorrowOf(DateTime(2026, 12, 31, 22, 0))), '2027-01-01');
    });

    test('handles a leap day', () {
      expect(dayKeyFor(tomorrowOf(DateTime(2028, 2, 28, 22, 0))), '2028-02-29');
    });
  });

  group('rest days', () {
    const restDays = [
      RestDay(dateKey: '2026-06-19'),
    ];

    test('isRestDayOn is false for a day with no mark', () {
      expect(isRestDayOn(restDays, now: DateTime(2026, 6, 18, 9)), isFalse);
    });

    test('isRestDayOn is true on the marked day', () {
      expect(isRestDayOn(restDays, now: DateTime(2026, 6, 19, 9)), isTrue);
    });

    test('isRestDayTomorrow sees a mark set the night before', () {
      // 6/18 밤에 "내일 쉬기"를 켜둔 상태.
      expect(
        isRestDayTomorrow(restDays, now: DateTime(2026, 6, 18, 23, 30)),
        isTrue,
      );
    });

    test("tomorrow's mark simply becomes today's once the date rolls over", () {
      final justAfterMidnight = DateTime(2026, 6, 19, 0, 1);
      expect(isRestDayOn(restDays, now: justAfterMidnight), isTrue);
      expect(isRestDayTomorrow(restDays, now: justAfterMidnight), isFalse);
    });
  });
}
