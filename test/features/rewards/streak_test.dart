import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/features/rewards/streak.dart';

String _key(DateTime d) => d.toIso8601String().split('T').first;

void main() {
  final today = DateTime(2026, 6, 18);

  group('currentStreak', () {
    test('no completions at all is 0', () {
      expect(currentStreak(const {}, today: today), 0);
    });

    test('completed today only is 1', () {
      final keys = {_key(today)};
      expect(currentStreak(keys, today: today), 1);
    });

    test('completed every day for 5 days counts all 5', () {
      final keys = {
        for (var i = 0; i < 5; i++) _key(today.subtract(Duration(days: i))),
      };
      expect(currentStreak(keys, today: today), 5);
    });

    test('missing a single day does not reset the streak to 0', () {
      // today and the day before yesterday are done; yesterday is skipped.
      final keys = {_key(today), _key(today.subtract(const Duration(days: 2)))};
      expect(currentStreak(keys, today: today), 2);
    });

    test('no completion yet today still counts the streak built through yesterday', () {
      final keys = {
        _key(today.subtract(const Duration(days: 1))),
        _key(today.subtract(const Duration(days: 2))),
      };
      expect(currentStreak(keys, today: today), 2);
    });

    test('a gap longer than the freeze allowance breaks the streak', () {
      // 3 consecutive missed days exceeds the default freeze allowance (2).
      final keys = {_key(today), _key(today.subtract(const Duration(days: 4)))};
      expect(currentStreak(keys, today: today), 1);
    });

    test('custom freeze allowance of 0 breaks on any missed day', () {
      final keys = {_key(today), _key(today.subtract(const Duration(days: 2)))};
      expect(currentStreak(keys, today: today, freezeAllowance: 0), 1);
    });
  });

  group('longestStreak', () {
    test('no completions is 0', () {
      expect(longestStreak(const {}), 0);
    });

    test('a single completion is a streak of 1', () {
      expect(longestStreak({_key(today)}), 1);
    });

    test('an earlier longer run is remembered even if the current run is shorter', () {
      final keys = {
        _key(today.subtract(const Duration(days: 10))),
        _key(today.subtract(const Duration(days: 9))),
        _key(today.subtract(const Duration(days: 8))),
        _key(today),
      };
      expect(longestStreak(keys), 3);
    });

    test('a single-day gap within a run does not shorten the best streak', () {
      final keys = {
        _key(today.subtract(const Duration(days: 4))),
        _key(today.subtract(const Duration(days: 3))),
        // day-2 skipped
        _key(today.subtract(const Duration(days: 1))),
        _key(today),
      };
      expect(longestStreak(keys), 4);
    });

    test('two isolated single-day completions separated by a big gap stay at best 1', () {
      final keys = {_key(today.subtract(const Duration(days: 10))), _key(today)};
      expect(longestStreak(keys), 1);
    });
  });
}
