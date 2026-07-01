import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/rest_day.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/features/rewards/daily_achievement.dart';

void main() {
  const dateKey = '2026-06-18';

  Segment block(String id, List<String> microSteps) {
    return Segment(
      id: id,
      name: id,
      colorValue: 0xFF000000,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 60,
      order: 0,
      microSteps: microSteps,
    );
  }

  test('achieved once at least half of today\'s items are checked', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      segments: [
        block('s1', const ['a', 'b', 'c', 'd']),
      ],
      completions: const [],
      progress: [
        MicroStepProgress(
          dateKey: dateKey,
          segmentId: 's1',
          checkedIndices: const [0, 1],
        ),
      ],
    );

    expect(achievement.checked, 2);
    expect(achievement.total, 4);
    expect(achievement.isAchieved, isTrue);
  });

  test('not achieved when under half are checked', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      segments: [
        block('s1', const ['a', 'b', 'c', 'd']),
      ],
      completions: const [],
      progress: [
        MicroStepProgress(
          dateKey: dateKey,
          segmentId: 's1',
          checkedIndices: const [0],
        ),
      ],
    );

    expect(achievement.isAchieved, isFalse);
  });

  test('counts items across all blocks', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      segments: [
        block('s1', const ['a', 'b']),
        block('s2', const ['c', 'd']),
      ],
      completions: const [],
      progress: [
        MicroStepProgress(
          dateKey: dateKey,
          segmentId: 's1',
          checkedIndices: const [0, 1],
        ),
      ],
    );

    expect(achievement.total, 4);
    expect(achievement.checked, 2);
    expect(achievement.isAchieved, isTrue);
  });

  test(
    'falls back to whole-day completion when there are no items to count',
    () {
      final achievement = dailyAchievementFor(
        dateKey: dateKey,
        segments: [block('s1', const [])],
        completions: const [
          Completion(dateKey: dateKey, segmentId: 's1', completedAtIso: ''),
        ],
        progress: const [],
      );

      expect(achievement.total, 0);
      expect(achievement.isAchieved, isTrue);
    },
  );

  test('no items and no completion is not achieved', () {
    final achievement = dailyAchievementFor(
      dateKey: dateKey,
      segments: [block('s1', const [])],
      completions: const [],
      progress: const [],
    );

    expect(achievement.isAchieved, isFalse);
  });

  group('achievedDateKeys', () {
    test('only includes days that meet the achievement bar', () {
      final segments = [
        block('s1', const ['a', 'b']),
      ];
      final result = achievedDateKeys(
        segments: segments,
        completions: const [],
        progress: [
          MicroStepProgress(
            dateKey: '2026-06-17',
            segmentId: 's1',
            checkedIndices: const [0, 1],
          ),
          MicroStepProgress(
            dateKey: '2026-06-18',
            segmentId: 's1',
            checkedIndices: const [],
          ),
        ],
      );

      expect(result, {'2026-06-17'});
    });
  });

  group('streakDateKeys', () {
    // A past day is identified relative to "now"; use a fixed now so the banked
    // day below is unambiguously in the past.
    final now = DateTime(2026, 6, 18, 10);
    final todayKey = DateFormat('yyyy-MM-dd').format(now);

    test('a rest day counts toward the streak (never a miss)', () {
      // No completions/progress on the rest day at all -- it counts purely
      // because it was deliberately marked "오늘은 쉬기".
      final result = streakDateKeys(
        achievedDays: const [],
        segments: const [],
        completions: const [],
        progress: const [],
        restDays: const [RestDay(dateKey: '2026-06-16')],
        now: now,
      );

      expect(result, contains('2026-06-16'));
    });

    test('a banked past day counts even when current blocks no longer would', () {
      // No blocks/progress/completions at all today -- the only reason this day
      // counts is that it was already recorded as achieved. Deleting the block
      // behind it must not erase the day.
      final result = streakDateKeys(
        achievedDays: const [AchievedDay(dateKey: '2026-06-15')],
        segments: const [],
        completions: const [],
        progress: const [],
        now: now,
      );

      expect(result, contains('2026-06-15'));
    });

    test(
      'today is included when it meets the bar live, without a stored record',
      () {
        final result = streakDateKeys(
          achievedDays: const [],
          segments: [
            block('s1', const ['a', 'b']),
          ],
          completions: const [],
          progress: [
            MicroStepProgress(
              dateKey: todayKey,
              segmentId: 's1',
              checkedIndices: const [0, 1],
            ),
          ],
          now: now,
        );

        expect(result, contains(todayKey));
      },
    );

    test(
      'today is excluded when it no longer meets the bar, even if banked earlier',
      () {
        final result = streakDateKeys(
          achievedDays: [AchievedDay(dateKey: todayKey)],
          segments: [
            block('s1', const ['a', 'b', 'c', 'd']),
          ],
          completions: const [],
          progress: [
            MicroStepProgress(
              dateKey: todayKey,
              segmentId: 's1',
              checkedIndices: const [0],
            ),
          ],
          now: now,
        );

        expect(result, isNot(contains(todayKey)));
      },
    );
  });
}
