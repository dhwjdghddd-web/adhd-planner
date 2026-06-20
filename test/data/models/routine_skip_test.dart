import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine_skip.dart';

void main() {
  group('RoutineSkip', () {
    test('today() stamps the given date and routine', () {
      final s = RoutineSkip.today('r1', at: DateTime(2026, 6, 19));
      expect(s.dateKey, '2026-06-19');
      expect(s.routineId, 'r1');
    });

    test('toMap/fromMap round-trips', () {
      final s = RoutineSkip.today('r1', at: DateTime(2026, 6, 19));
      final restored = RoutineSkip.fromMap(s.toMap());
      expect(restored.dateKey, s.dateKey);
      expect(restored.routineId, s.routineId);
    });

    test('id combines dateKey and routineId the same way Completion does', () {
      final s = RoutineSkip.today('r1', at: DateTime(2026, 6, 19));
      expect(s.id, '2026-06-19_r1');
      expect(RoutineSkip.keyFor('2026-06-19', 'r1'), s.id);
    });
  });
}
