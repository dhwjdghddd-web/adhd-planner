import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';

Routine _routine({
  required int startMinute,
  required int durationMin,
  List<int> repeatDays = const [],
}) {
  return Routine(
    id: 'r1',
    segmentId: 's1',
    title: 'test',
    startMinute: startMinute,
    durationMin: durationMin,
    repeatDays: repeatDays,
  );
}

void main() {
  group('Routine.containsMinute', () {
    test('same-day routine contains minutes inside its span', () {
      final r = _routine(startMinute: 9 * 60, durationMin: 30); // 09:00~09:30
      expect(r.containsMinute(9 * 60), true);
      expect(r.containsMinute(9 * 60 + 29), true);
      expect(r.containsMinute(9 * 60 + 30), false); // end exclusive
      expect(r.containsMinute(8 * 60 + 59), false);
    });

    test('midnight-wrapping routine contains minutes on both sides', () {
      final r = _routine(startMinute: 23 * 60 + 45, durationMin: 30); // 23:45~00:15
      expect(r.containsMinute(23 * 60 + 50), true);
      expect(r.containsMinute(0), true);
      expect(r.containsMinute(10), true);
      expect(r.containsMinute(20), false);
    });

    test('zero-duration routine contains nothing', () {
      final r = _routine(startMinute: 9 * 60, durationMin: 0);
      expect(r.containsMinute(9 * 60), false);
    });
  });

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
      final r = _routine(startMinute: 0, durationMin: 30);
      final restored = Routine.fromMap(r.toMap());
      expect(restored.segmentId, 's1');
    });
  });

  group('Routine.occursOn', () {
    test('empty repeatDays matches every weekday', () {
      final r = _routine(startMinute: 0, durationMin: 30);
      for (var day = 1; day <= 7; day++) {
        expect(r.occursOn(day), true, reason: 'day $day');
      }
    });

    test('non-empty repeatDays matches only listed weekdays', () {
      final r = _routine(startMinute: 0, durationMin: 30, repeatDays: const [1, 3, 5]);
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
