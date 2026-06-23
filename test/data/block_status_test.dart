import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/block_status.dart';
import 'package:adhd_planner/data/models/segment.dart';

Segment _block({
  required String id,
  required int startMinute,
  required int endMinute,
}) {
  return Segment(
    id: id,
    name: id,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
  );
}

void main() {
  group('findBlockStatus', () {
    test('the block whose range covers now is current', () {
      final blocks = [
        _block(id: 'morning', startMinute: 6 * 60, endMinute: 12 * 60),
        _block(id: 'work', startMinute: 12 * 60, endMinute: 18 * 60),
      ];
      final status = findBlockStatus(blocks, 9 * 60);
      expect(status.isCurrent, true);
      expect(status.segment?.id, 'morning');
    });

    test('overlapping blocks: the most recently started one wins', () {
      final blocks = [
        _block(id: 'morning', startMinute: 6 * 60, endMinute: 12 * 60),
        _block(id: 'work', startMinute: 7 * 60, endMinute: 18 * 60),
      ];
      // Both cover 08:00; 'work' started more recently (07:00 vs 06:00).
      final status = findBlockStatus(blocks, 8 * 60);
      expect(status.isCurrent, true);
      expect(status.segment?.id, 'work');
    });

    test('in a gap, the soonest upcoming block is next (not current)', () {
      final blocks = [
        _block(id: 'morning', startMinute: 6 * 60, endMinute: 9 * 60),
        _block(id: 'evening', startMinute: 18 * 60, endMinute: 22 * 60),
      ];
      final status = findBlockStatus(blocks, 12 * 60);
      expect(status.isCurrent, false);
      expect(status.segment?.id, 'evening');
      expect(status.remainingMinutes, 6 * 60);
    });

    test('a midnight-wrapping block covers the small hours', () {
      final blocks = [
        _block(id: 'sleep', startMinute: 23 * 60, endMinute: 6 * 60),
      ];
      final status = findBlockStatus(blocks, 2 * 60);
      expect(status.isCurrent, true);
      expect(status.segment?.id, 'sleep');
    });

    test('no blocks yields an empty status', () {
      final status = findBlockStatus(const [], 9 * 60);
      expect(status.segment, isNull);
      expect(status.isCurrent, false);
    });
  });
}
