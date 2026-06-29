import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/features/focus/block_remaining.dart';

Segment _block(int startMinute, int endMinute) {
  return Segment(
    id: 's1',
    name: 'test',
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
  );
}

void main() {
  group('blockRemainingMinutes', () {
    test('a same-day block partway through', () {
      // 09:00~10:00, now 09:30 -- 30분 left.
      expect(blockRemainingMinutes(_block(9 * 60, 10 * 60), 9 * 60 + 30), 30);
    });

    test('right at the start of a same-day block', () {
      expect(blockRemainingMinutes(_block(9 * 60, 10 * 60), 9 * 60), 60);
    });

    test('a midnight-wrapping block before midnight', () {
      // 22:00~02:00, now 23:00 -- 3시간(180분) left, through midnight.
      expect(blockRemainingMinutes(_block(22 * 60, 2 * 60), 23 * 60), 180);
    });

    test('a midnight-wrapping block after midnight', () {
      // 22:00~02:00, now 01:00 -- 1시간(60분) left.
      expect(blockRemainingMinutes(_block(22 * 60, 2 * 60), 60), 60);
    });
  });

  group('formatRemaining', () {
    test('under an hour shows minutes only', () {
      expect(formatRemaining(20), '20분 남음');
    });

    test('exactly an hour collapses to just the hour, no "0분"', () {
      expect(formatRemaining(60), '1시간 남음');
    });

    test('over an hour shows both hours and minutes', () {
      expect(formatRemaining(80), '1시간 20분 남음');
    });
  });

  group('blockProgressFraction', () {
    test('0.0 right at the start', () {
      expect(blockProgressFraction(_block(9 * 60, 10 * 60), 9 * 60), 0.0);
    });

    test('0.5 halfway through', () {
      expect(blockProgressFraction(_block(9 * 60, 10 * 60), 9 * 60 + 30), 0.5);
    });

    test('approaches 1.0 right before the end', () {
      final fraction = blockProgressFraction(_block(9 * 60, 10 * 60), 10 * 60 - 1);
      expect(fraction, closeTo(1.0, 0.02));
    });

    test('a midnight-wrapping block', () {
      // 22:00~02:00 (4시간), now 23:00 -- 1시간 in, 25%.
      expect(blockProgressFraction(_block(22 * 60, 2 * 60), 23 * 60), 0.25);
    });
  });
}
