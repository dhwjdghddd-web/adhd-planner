import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/achieved_day.dart';

void main() {
  test('id is the dateKey, so each day maps to exactly one record', () {
    const day = AchievedDay(dateKey: '2026-06-18');
    expect(day.id, '2026-06-18');
  });

  test('forDay formats the calendar day as a yyyy-MM-dd key', () {
    final day = AchievedDay.forDay(DateTime(2026, 6, 8, 23, 59));
    expect(day.dateKey, '2026-06-08');
  });

  test('round-trips through toMap/fromMap', () {
    const day = AchievedDay(dateKey: '2026-06-18');
    final restored = AchievedDay.fromMap(day.toMap());
    expect(restored.dateKey, day.dateKey);
  });
}
