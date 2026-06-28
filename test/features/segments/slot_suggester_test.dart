import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/features/segments/slot_suggester.dart';

Segment _block({
  String id = 's1',
  required int startMinute,
  required int endMinute,
}) {
  return Segment(
    id: id,
    name: 'test',
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
  );
}

void main() {
  group('anchorMinuteFor', () {
    test('rounds now up to the next half hour when there are no segments', () {
      expect(anchorMinuteFor(9 * 60 + 5, const []), 9 * 60 + 30);
      expect(anchorMinuteFor(9 * 60 + 31, const []), 10 * 60);
    });

    test('an exact half-hour now stays put', () {
      expect(anchorMinuteFor(9 * 60 + 30, const []), 9 * 60 + 30);
    });

    test("uses today's latest block end when it's later than rounded-now", () {
      final segments = [_block(startMinute: 9 * 60, endMinute: 11 * 60 + 17)];
      expect(anchorMinuteFor(9 * 60 + 5, segments), 11 * 60 + 17);
    });

    test('a midnight-wrapping block does not push the anchor forward', () {
      // 22:00~02:00 -- its "end" (02:00) is tomorrow morning, not later today.
      // now (9:00) is already on a half-hour boundary, so without the
      // wrapping block's (incorrect) influence the anchor stays exactly there.
      final segments = [_block(startMinute: 22 * 60, endMinute: 2 * 60)];
      expect(anchorMinuteFor(9 * 60, segments), 9 * 60);
    });

    test('never exceeds the end of the day', () {
      expect(anchorMinuteFor(23 * 60 + 59, const []), 1440);
    });
  });

  group('suggestSlots', () {
    test('places items back-to-back from the anchor, each kSuggestedSlotMinutes long',
        () {
      final slots = suggestSlots(['a', 'b', 'c'], const [], anchorMinute: 9 * 60);

      expect(slots.length, 3);
      expect(slots[0].startMinute, 9 * 60);
      expect(slots[0].endMinute, 9 * 60 + kSuggestedSlotMinutes);
      expect(slots[1].startMinute, 9 * 60 + kSuggestedSlotMinutes);
      expect(slots[2].startMinute, 9 * 60 + kSuggestedSlotMinutes * 2);
    });

    test('keeps each item\'s own text in its suggested slot', () {
      final slots = suggestSlots(['병원 예약', '청소'], const [], anchorMinute: 9 * 60);
      expect(slots[0].text, '병원 예약');
      expect(slots[1].text, '청소');
    });

    test('skips past an existing block instead of overlapping it', () {
      final existing = [_block(startMinute: 9 * 60, endMinute: 9 * 60 + 45)];
      final slots = suggestSlots(['a'], existing, anchorMinute: 9 * 60);

      expect(slots.single.startMinute, 9 * 60 + 45);
    });

    test('skips past two back-to-back existing blocks in one go', () {
      final existing = [
        _block(id: 's1', startMinute: 9 * 60, endMinute: 9 * 60 + 30),
        _block(id: 's2', startMinute: 9 * 60 + 30, endMinute: 10 * 60),
      ];
      final slots = suggestSlots(['a'], existing, anchorMinute: 9 * 60);

      expect(slots.single.startMinute, 10 * 60);
    });

    test('stops suggesting once a slot would run past midnight, dropping the rest',
        () {
      // Anchor 5 minutes before midnight -- the very first 30-minute slot
      // already runs past it, so nothing at all fits.
      final slots = suggestSlots(['a', 'b'], const [], anchorMinute: 1440 - 5);
      expect(slots, isEmpty);
    });

    test('places as many as fit and drops only the ones that do not', () {
      // Exactly room for one more 30-minute slot before midnight, not two.
      final slots = suggestSlots(['a', 'b'], const [], anchorMinute: 1440 - 30);
      expect(slots.length, 1);
      expect(slots.single.text, 'a');
    });

    test('an empty item list produces no slots', () {
      expect(suggestSlots(const [], const [], anchorMinute: 9 * 60), isEmpty);
    });
  });
}
