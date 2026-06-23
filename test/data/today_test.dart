import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/today.dart';

void main() {
  test('dayKeyFor formats the given moment as a yyyy-MM-dd local key', () {
    expect(dayKeyFor(DateTime(2026, 6, 8, 23, 59)), '2026-06-08');
  });

  test('completedBlockIdsOn keeps only the given day, ignoring other days', () {
    final completions = [
      const Completion(dateKey: '2026-06-18', segmentId: 'a', completedAtIso: ''),
      const Completion(dateKey: '2026-06-18', segmentId: 'b', completedAtIso: ''),
      const Completion(dateKey: '2026-06-17', segmentId: 'c', completedAtIso: ''),
    ];
    expect(
      completedBlockIdsOn(completions, now: DateTime(2026, 6, 18)),
      {'a', 'b'},
    );
  });
}
