import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/micro_step_layout.dart';
import 'package:adhd_planner/data/models/micro_step_move.dart';
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
  final now = DateTime(2026, 6, 30, 9, 0);
  final dateKey = '2026-06-30';

  final morning = _block('am', ['약', '물'], start: 0);
  final afternoon = _block('pm', ['운동'], start: 600);
  final all = [morning, afternoon];

  List<DisplayedStep> displayed(Segment block, List<MicroStepMove> moves) =>
      displayedStepsFor(block: block, allSegments: all, moves: moves, now: now);

  test('with no moves, a block shows exactly its own items', () {
    final steps = displayed(morning, const []);
    expect(steps.map((s) => s.text), ['약', '물']);
    expect(steps.every((s) => s.homeSegmentId == 'am'), true);
    expect(steps.every((s) => !s.movedHere), true);
  });

  test('a moved item disappears from its home block', () {
    final moves = [
      MicroStepMove(
        dateKey: dateKey,
        homeSegmentId: 'am',
        stepIndex: 0,
        targetSegmentId: 'pm',
      ),
    ];
    expect(displayed(morning, moves).map((s) => s.text), ['물']);
  });

  test('a moved item appears under the target block, flagged movedHere', () {
    final moves = [
      MicroStepMove(
        dateKey: dateKey,
        homeSegmentId: 'am',
        stepIndex: 0,
        targetSegmentId: 'pm',
      ),
    ];
    final pm = displayed(afternoon, moves);
    expect(pm.map((s) => s.text), ['운동', '약']);
    final movedIn = pm.firstWhere((s) => s.text == '약');
    expect(movedIn.homeSegmentId, 'am'); // progress still tracked under home
    expect(movedIn.index, 0);
    expect(movedIn.movedHere, true);
  });

  test('moves from another day are ignored', () {
    final moves = [
      const MicroStepMove(
        dateKey: '2026-06-29',
        homeSegmentId: 'am',
        stepIndex: 0,
        targetSegmentId: 'pm',
      ),
    ];
    expect(displayed(morning, moves).map((s) => s.text), ['약', '물']);
    expect(displayed(afternoon, moves).map((s) => s.text), ['운동']);
  });

  test('a stale move (index past end of edited home block) is dropped', () {
    final moves = [
      MicroStepMove(
        dateKey: dateKey,
        homeSegmentId: 'am',
        stepIndex: 9, // am only has 2 items
        targetSegmentId: 'pm',
      ),
    ];
    // Not added to pm, and am is unaffected (index 9 isn't one of its items).
    expect(displayed(afternoon, moves).map((s) => s.text), ['운동']);
    expect(displayed(morning, moves).map((s) => s.text), ['약', '물']);
  });
}
