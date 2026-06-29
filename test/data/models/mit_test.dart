import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/mit.dart';

void main() {
  group('Mit.today', () {
    test('derives dateKey from the given instant', () {
      final m = Mit.today('s1', at: DateTime(2026, 6, 17, 21, 5));

      expect(m.dateKey, '2026-06-17');
      expect(m.segmentId, 's1');
    });

    test('id combines dateKey and segmentId', () {
      final m = Mit.today('s1', at: DateTime(2026, 6, 17));
      expect(m.id, '2026-06-17_s1');
    });
  });

  test('toMap/fromMap round-trips', () {
    const m = Mit(dateKey: '2026-06-17', segmentId: 's1');
    final restored = Mit.fromMap(m.toMap());

    expect(restored.dateKey, '2026-06-17');
    expect(restored.segmentId, 's1');
  });
}
