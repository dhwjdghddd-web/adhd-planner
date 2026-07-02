import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/micro_step_layout.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_move.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';

Segment _block(String id, List<String> steps, {int start = 0}) => Segment(
  id: id,
  name: id,
  colorValue: 0xFF000000,
  iconKey: 'wb_sunny',
  startMinute: start,
  endMinute: start + 60,
  order: start,
  microSteps: steps,
);

void main() {
  final now = DateTime(2026, 7, 2, 9);
  const dateKey = '2026-07-02';

  MicroStepProgress checked(String segId, List<int> idx) => MicroStepProgress(
    dateKey: dateKey,
    segmentId: segId,
    checkedIndices: idx,
  );

  test('all items checked -> block should be completed', () {
    final plan = reconcileBlockCompletions(
      segments: [
        _block('am', const ['a', 'b']),
      ],
      progress: [
        checked('am', const [0, 1]),
      ],
      moves: const [],
      completions: const [],
      now: now,
    );
    expect(plan.toComplete, {'am'});
    expect(plan.toUncomplete, isEmpty);
  });

  test('un-checking an item clears an existing completion (bug 2)', () {
    final plan = reconcileBlockCompletions(
      segments: [
        _block('am', const ['a', 'b']),
      ],
      progress: [
        checked('am', const [0]),
      ], // one unchecked now
      moves: const [],
      completions: const [
        Completion(dateKey: dateKey, segmentId: 'am', completedAtIso: ''),
      ],
      now: now,
    );
    expect(plan.toUncomplete, {'am'});
    expect(plan.toComplete, isEmpty);
  });

  test(
    'moving the last unchecked item away completes the source, not the target '
    '(bug 1)',
    () {
      // am has [a✓, b(unchecked)]; b is moved to pm. Source am now shows only
      // a✓ -> should complete. pm now shows b (unchecked) -> must NOT complete.
      final plan = reconcileBlockCompletions(
        segments: [
          _block('am', const ['a', 'b']),
          _block('pm', const ['x'], start: 600),
        ],
        progress: [
          checked('am', const [0]), // a checked, b (index 1) not
          checked('pm', const [0]), // x checked
        ],
        moves: const [
          MicroStepMove(
            dateKey: dateKey,
            homeSegmentId: 'am',
            stepIndex: 1,
            targetSegmentId: 'pm',
          ),
        ],
        completions: const [],
        now: now,
      );
      expect(plan.toComplete, {'am'}); // source is now all-checked
      expect(plan.toComplete, isNot(contains('pm')));
    },
  );

  test('checklist-less block is never auto-touched', () {
    final plan = reconcileBlockCompletions(
      segments: [_block('rest', const [])],
      progress: const [],
      moves: const [],
      completions: const [
        Completion(dateKey: dateKey, segmentId: 'rest', completedAtIso: ''),
      ],
      now: now,
    );
    expect(plan.toComplete, isEmpty);
    expect(plan.toUncomplete, isEmpty);
  });
}
