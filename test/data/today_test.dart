import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/data/today.dart';

void main() {
  test('dayKeyFor formats the given moment as a yyyy-MM-dd local key', () {
    expect(dayKeyFor(DateTime(2026, 6, 8, 23, 59)), '2026-06-08');
  });

  test('completedRoutineIdsOn keeps only the given day, ignoring other days', () {
    final completions = [
      const Completion(dateKey: '2026-06-18', routineId: 'a', completedAtIso: ''),
      const Completion(dateKey: '2026-06-18', routineId: 'b', completedAtIso: ''),
      const Completion(dateKey: '2026-06-17', routineId: 'c', completedAtIso: ''),
    ];
    expect(
      completedRoutineIdsOn(completions, now: DateTime(2026, 6, 18)),
      {'a', 'b'},
    );
  });

  test('skippedRoutineIdsOn keeps only the given day, ignoring other days', () {
    final skips = [
      const RoutineSkip(dateKey: '2026-06-18', routineId: 'a'),
      const RoutineSkip(dateKey: '2026-06-17', routineId: 'b'),
    ];
    expect(
      skippedRoutineIdsOn(skips, now: DateTime(2026, 6, 18)),
      {'a'},
    );
  });
}
