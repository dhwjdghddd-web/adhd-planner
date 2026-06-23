import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';

Segment _segment({
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
  group('Segment block fields', () {
    test('defaults: no note/items, alarm on, no notification ids', () {
      final s = _segment(startMinute: 0, endMinute: 60);
      expect(s.note, '');
      expect(s.microSteps, isEmpty);
      expect(s.alarmEnabled, true);
      expect(s.notificationIds, isEmpty);
    });

    test('toMap/fromMap round-trips the block fields', () {
      final s = _segment(startMinute: 0, endMinute: 60).copyWith(
        note: 'memo',
        microSteps: ['a', 'b'],
        alarmEnabled: false,
        notificationIds: [1, 2, 3],
      );
      final restored = Segment.fromMap(s.toMap());
      expect(restored.note, 'memo');
      expect(restored.microSteps, ['a', 'b']);
      expect(restored.alarmEnabled, false);
      expect(restored.notificationIds, [1, 2, 3]);
    });

    test('fromMap tolerates a legacy doc missing the new fields', () {
      final restored = Segment.fromMap({
        'id': 's1',
        'name': 'test',
        'colorValue': 0xFF000000,
        'iconKey': 'wb_sunny',
        'startMinute': 0,
        'endMinute': 60,
        'order': 0,
      });
      expect(restored.note, '');
      expect(restored.microSteps, isEmpty);
      expect(restored.alarmEnabled, true);
      expect(restored.notificationIds, isEmpty);
    });

    test('copyWith leaves untouched fields as they were', () {
      final s = _segment(startMinute: 0, endMinute: 60)
          .copyWith(microSteps: ['x'], alarmEnabled: false);
      expect(s.copyWith(note: 'n').microSteps, ['x']);
      expect(s.copyWith(note: 'n').alarmEnabled, false);
    });
  });

  group('Segment.containsMinute', () {
    test('same-day range contains minutes inside it', () {
      final s = _segment(startMinute: 6 * 60, endMinute: 12 * 60);
      expect(s.containsMinute(6 * 60), true);
      expect(s.containsMinute(9 * 60), true);
      expect(s.containsMinute(12 * 60), false); // end is exclusive
      expect(s.containsMinute(5 * 60 + 59), false);
    });

    test('midnight-wrapping range contains minutes on both sides', () {
      final s = _segment(startMinute: 18 * 60, endMinute: 0); // 18:00~00:00
      expect(s.containsMinute(23 * 60), true);
      expect(s.containsMinute(0), false); // end exclusive
      expect(s.containsMinute(17 * 60 + 59), false);
    });

    test('zero-length range contains nothing', () {
      final s = _segment(startMinute: 6 * 60, endMinute: 6 * 60);
      expect(s.containsMinute(6 * 60), false);
    });
  });

  group('Segment.overlaps', () {
    test('non-overlapping same-day ranges', () {
      final a = _segment(id: 'a', startMinute: 6 * 60, endMinute: 12 * 60);
      final b = _segment(id: 'b', startMinute: 12 * 60, endMinute: 18 * 60);
      expect(a.overlaps(b), false);
      expect(b.overlaps(a), false);
    });

    test('overlapping same-day ranges', () {
      final a = _segment(id: 'a', startMinute: 6 * 60, endMinute: 12 * 60);
      final b = _segment(id: 'b', startMinute: 10 * 60, endMinute: 14 * 60);
      expect(a.overlaps(b), true);
      expect(b.overlaps(a), true);
    });

    test('midnight-wrapping range overlapping a same-day range', () {
      final a = _segment(id: 'a', startMinute: 22 * 60, endMinute: 2 * 60); // 22:00~02:00
      final b = _segment(id: 'b', startMinute: 0, endMinute: 6 * 60); // 00:00~06:00
      expect(a.overlaps(b), true);
      expect(b.overlaps(a), true);
    });

    test('midnight-wrapping range not overlapping a disjoint range', () {
      final a = _segment(id: 'a', startMinute: 22 * 60, endMinute: 2 * 60); // 22:00~02:00
      final b = _segment(id: 'b', startMinute: 8 * 60, endMinute: 16 * 60);
      expect(a.overlaps(b), false);
      expect(b.overlaps(a), false);
    });
  });
}
