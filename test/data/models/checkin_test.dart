import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/checkin.dart';

void main() {
  group('Checkin.today', () {
    test('derives dateKey and createdAtIso from the given instant', () {
      final c = Checkin.today(
        mood: 4,
        energy: 3,
        at: DateTime(2026, 6, 17, 21, 5),
      );

      expect(c.dateKey, '2026-06-17');
      expect(c.mood, 4);
      expect(c.energy, 3);
      expect(c.note, isNull);
      expect(c.id, isNotEmpty);
      expect(c.createdAtIso, '2026-06-17T21:05:00.000');
    });

    test('supports custom id', () {
      final c = Checkin.today(id: 'custom-id', mood: 5, energy: 5, at: DateTime(2026, 6, 17));
      expect(c.id, 'custom-id');
      expect(c.dateKey, '2026-06-17');
    });
  });

  test('toMap/fromMap round-trips including id and optional note', () {
    final c = Checkin(
      id: 'checkin-1',
      dateKey: '2026-06-17',
      mood: 2,
      energy: 1,
      note: '피곤한 날',
      createdAtIso: '2026-06-17T14:30:00.000',
    );
    final restored = Checkin.fromMap(c.toMap());

    expect(restored.id, 'checkin-1');
    expect(restored.dateKey, '2026-06-17');
    expect(restored.mood, 2);
    expect(restored.energy, 1);
    expect(restored.note, '피곤한 날');
    expect(restored.createdAtIso, '2026-06-17T14:30:00.000');
  });

  test('fromMap handles legacy map without id or createdAtIso', () {
    final legacyMap = {
      'dateKey': '2026-06-17',
      'mood': 3,
      'energy': 3,
    };
    final restored = Checkin.fromMap(legacyMap);
    expect(restored.id, '2026-06-17');
    expect(restored.dateKey, '2026-06-17');
    expect(restored.note, isNull);
    expect(restored.createdAtIso, '2026-06-17T12:00:00.000Z');
  });
}
