import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine_postponement.dart';

void main() {
  group('RoutinePostponement', () {
    test('today() stamps the given date and routine', () {
      final p = RoutinePostponement.today('r1', 5, at: DateTime(2026, 6, 19));
      expect(p.dateKey, '2026-06-19');
      expect(p.routineId, 'r1');
      expect(p.offsetMinutes, 5);
    });

    test('toMap/fromMap round-trips', () {
      final p = RoutinePostponement.today('r1', 10, at: DateTime(2026, 6, 19));
      final restored = RoutinePostponement.fromMap(p.toMap());
      expect(restored.dateKey, p.dateKey);
      expect(restored.routineId, p.routineId);
      expect(restored.offsetMinutes, p.offsetMinutes);
    });

    test('id combines dateKey and routineId the same way Completion does', () {
      final p = RoutinePostponement.today('r1', 5, at: DateTime(2026, 6, 19));
      expect(p.id, '2026-06-19_r1');
      expect(RoutinePostponement.keyFor('2026-06-19', 'r1'), p.id);
    });
  });
}
