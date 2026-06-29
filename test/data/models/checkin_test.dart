import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/checkin.dart';

void main() {
  group('Checkin.today', () {
    test('derives dateKey from the given instant', () {
      final c = Checkin.today(
        mood: 4,
        energy: 3,
        at: DateTime(2026, 6, 17, 21, 5),
      );

      expect(c.dateKey, '2026-06-17');
      expect(c.mood, 4);
      expect(c.energy, 3);
      expect(c.note, isNull);
    });

    test('id is the dateKey -- one per day', () {
      final c = Checkin.today(mood: 5, energy: 5, at: DateTime(2026, 6, 17));
      expect(c.id, '2026-06-17');
    });
  });

  test('toMap/fromMap round-trips including the optional note', () {
    const c = Checkin(dateKey: '2026-06-17', mood: 2, energy: 1, note: '피곤한 날');
    final restored = Checkin.fromMap(c.toMap());

    expect(restored.dateKey, '2026-06-17');
    expect(restored.mood, 2);
    expect(restored.energy, 1);
    expect(restored.note, '피곤한 날');
  });

  test('toMap/fromMap round-trips a null note', () {
    const c = Checkin(dateKey: '2026-06-17', mood: 3, energy: 3);
    final restored = Checkin.fromMap(c.toMap());
    expect(restored.note, isNull);
  });
}
