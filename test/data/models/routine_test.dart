import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';

Routine _routine({
  required int startMinute,
  List<int> repeatDays = const [],
}) {
  return Routine(
    id: 'r1',
    segmentId: 's1',
    title: 'test',
    startMinute: startMinute,
    repeatDays: repeatDays,
  );
}

void main() {
  group('Routine segmentId', () {
    test('toMap/fromMap round-trips a null segmentId (auto-derived, gap between segments)', () {
      final r = Routine(
        id: 'r1',
        segmentId: null,
        title: 'test',
        startMinute: 0,
      );
      final restored = Routine.fromMap(r.toMap());
      expect(restored.segmentId, isNull);
    });

    test('toMap/fromMap round-trips a non-null segmentId', () {
      final r = _routine(startMinute: 0);
      final restored = Routine.fromMap(r.toMap());
      expect(restored.segmentId, 's1');
    });
  });

  group('Routine.occursOn', () {
    test('empty repeatDays matches every weekday', () {
      final r = _routine(startMinute: 0);
      for (var day = 1; day <= 7; day++) {
        expect(r.occursOn(day), true, reason: 'day $day');
      }
    });

    test('non-empty repeatDays matches only listed weekdays', () {
      final r = _routine(startMinute: 0, repeatDays: const [1, 3, 5]);
      expect(r.occursOn(1), true);
      expect(r.occursOn(3), true);
      expect(r.occursOn(5), true);
      expect(r.occursOn(2), false);
      expect(r.occursOn(4), false);
      expect(r.occursOn(6), false);
      expect(r.occursOn(7), false);
    });
  });
}
