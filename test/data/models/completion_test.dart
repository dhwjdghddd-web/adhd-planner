import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';

void main() {
  group('Completion.now', () {
    test('derives dateKey and completedAtIso from the given instant', () {
      final at = DateTime(2026, 6, 17, 21, 5);
      final c = Completion.now('r1', at: at);

      expect(c.dateKey, '2026-06-17');
      expect(c.routineId, 'r1');
      expect(c.completedAtIso, at.toIso8601String());
    });

    test('id combines dateKey and routineId', () {
      final c = Completion.now('r1', at: DateTime(2026, 6, 17));
      expect(c.id, '2026-06-17_r1');
    });
  });
}
