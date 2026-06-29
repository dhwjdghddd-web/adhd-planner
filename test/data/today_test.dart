import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/alarm_skip.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/mit.dart';
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

  test('skippedBlockIdsOn keeps only the given day, ignoring other days', () {
    final skips = [
      const AlarmSkip(dateKey: '2026-06-18', segmentId: 'a'),
      const AlarmSkip(dateKey: '2026-06-18', segmentId: 'b'),
      const AlarmSkip(dateKey: '2026-06-17', segmentId: 'c'),
    ];
    expect(
      skippedBlockIdsOn(skips, now: DateTime(2026, 6, 18)),
      {'a', 'b'},
    );
  });

  test('a block not skipped today is absent even if skipped on another day', () {
    final skips = [const AlarmSkip(dateKey: '2026-06-17', segmentId: 'a')];
    expect(skippedBlockIdsOn(skips, now: DateTime(2026, 6, 18)), isEmpty);
  });

  test('mitBlockIdsOn keeps only the given day, ignoring other days', () {
    final mits = [
      const Mit(dateKey: '2026-06-18', segmentId: 'a'),
      const Mit(dateKey: '2026-06-18', segmentId: 'b'),
      const Mit(dateKey: '2026-06-17', segmentId: 'c'),
    ];
    expect(mitBlockIdsOn(mits, now: DateTime(2026, 6, 18)), {'a', 'b'});
  });

  test('a block not marked MIT today is absent even if marked on another day', () {
    final mits = [const Mit(dateKey: '2026-06-17', segmentId: 'a')];
    expect(mitBlockIdsOn(mits, now: DateTime(2026, 6, 18)), isEmpty);
  });
}
