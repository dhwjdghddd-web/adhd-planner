import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/features/rewards/daily_achievement.dart';

void main() {
  const dateKey = '2026-06-18';
  final isoWeekday = DateTime.parse(dateKey).weekday;
  final notToday = [1, 2, 3, 4, 5, 6, 7].where((d) => d != isoWeekday).toList();

  Routine routine(String id, List<String> microSteps, {List<int> repeatDays = const []}) {
    return Routine(
      id: id,
      segmentId: null,
      title: id,
      startMinute: 0,
      microSteps: microSteps,
      repeatDays: repeatDays,
    );
  }

  test('achieved once at least half of today\'s micro-steps are checked', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [routine('r1', const ['a', 'b', 'c', 'd'])],
      skips: const [],
      completions: const [],
      progress: [MicroStepProgress(dateKey: dateKey, routineId: 'r1', checkedIndices: const [0, 1])],
    );

    expect(achievement.checked, 2);
    expect(achievement.total, 4);
    expect(achievement.isAchieved, isTrue);
  });

  test('not achieved when under half are checked', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [routine('r1', const ['a', 'b', 'c', 'd'])],
      skips: const [],
      completions: const [],
      progress: [MicroStepProgress(dateKey: dateKey, routineId: 'r1', checkedIndices: const [0])],
    );

    expect(achievement.isAchieved, isFalse);
  });

  test("a skipped routine's micro-steps don't count toward the total or the checked count", () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [
        routine('skipped', const ['a', 'b']),
        routine('kept', const ['c', 'd']),
      ],
      skips: const [RoutineSkip(dateKey: dateKey, routineId: 'skipped')],
      completions: const [],
      progress: [
        // Fully checked, but skipped -- should not rescue the day.
        MicroStepProgress(dateKey: dateKey, routineId: 'skipped', checkedIndices: const [0, 1]),
      ],
    );

    expect(achievement.total, 2);
    expect(achievement.checked, 0);
    expect(achievement.isAchieved, isFalse);
  });

  test('falls back to whole-day completion when there are no micro-steps to count', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [routine('r1', const [])],
      skips: const [],
      completions: const [Completion(dateKey: dateKey, routineId: 'r1', completedAtIso: '')],
      progress: const [],
    );

    expect(achievement.total, 0);
    expect(achievement.isAchieved, isTrue);
  });

  test('no micro-steps and no completion is not achieved', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [routine('r1', const [])],
      skips: const [],
      completions: const [],
      progress: const [],
    );

    expect(achievement.isAchieved, isFalse);
  });

  test("a routine that doesn't occur on that weekday is excluded from the total", () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      routines: [routine('other-day', const ['a', 'b'], repeatDays: notToday)],
      skips: const [],
      completions: const [],
      progress: const [],
    );

    expect(achievement.total, 0);
  });

  group('achievedDateKeys', () {
    test('only includes days that meet the achievement bar', () {
      final routines = [routine('r1', const ['a', 'b'])];
      final result = achievedDateKeys(
        routines: routines,
        skips: const [],
        completions: const [],
        progress: [
          MicroStepProgress(dateKey: '2026-06-17', routineId: 'r1', checkedIndices: const [0, 1]),
          MicroStepProgress(dateKey: '2026-06-18', routineId: 'r1', checkedIndices: const []),
        ],
      );

      expect(result, {'2026-06-17'});
    });
  });

  group('streakDateKeys', () {
    // A past day is identified relative to "now"; use a fixed now so the
    // banked day below is unambiguously in the past.
    final now = DateTime(2026, 6, 18, 10);
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    test('a banked past day counts even when current routines no longer would', () {
      // No routines/progress/completions at all today -- the only reason this
      // day counts is that it was already recorded as achieved. This is the
      // whole point: deleting the routine behind it must not erase the day.
      final result = streakDateKeys(
        achievedDays: const [AchievedDay(dateKey: '2026-06-15')],
        routines: const [],
        skips: const [],
        completions: const [],
        progress: const [],
        now: now,
      );

      expect(result, contains('2026-06-15'));
    });

    test('today is included when it meets the bar live, without a stored record', () {
      final result = streakDateKeys(
        achievedDays: const [],
        routines: [routine('r1', const ['a', 'b'])],
        skips: const [],
        completions: const [],
        progress: [
          MicroStepProgress(dateKey: todayKey, routineId: 'r1', checkedIndices: const [0, 1]),
        ],
        now: now,
      );

      expect(result, contains(todayKey));
    });

    test('today is excluded when it no longer meets the bar, even if banked earlier', () {
      // A record exists for today (banked when it briefly crossed 50%), but the
      // user has since un-checked back below the bar. Today is governed by the
      // live check, not the stale same-day record, so it must drop out again.
      final result = streakDateKeys(
        achievedDays: [AchievedDay(dateKey: todayKey)],
        routines: [routine('r1', const ['a', 'b', 'c', 'd'])],
        skips: const [],
        completions: const [],
        progress: [
          MicroStepProgress(dateKey: todayKey, routineId: 'r1', checkedIndices: const [0]),
        ],
        now: now,
      );

      expect(result, isNot(contains(todayKey)));
    });
  });
}
