import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/time_geometry.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/planner/dial_painter.dart';
import 'package:adhd_planner/features/planner/planner_page.dart';
import 'package:adhd_planner/features/routines/routine_editor_page.dart';
import 'package:adhd_planner/features/segments/segment_editor_page.dart';
import 'package:adhd_planner/features/segments/segment_form_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: PlannerPage()),
    );
  }

  testWidgets('shows empty-schedule message when there are no routines',
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.byType(CustomPaint), findsWidgets);
    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('tapping the dial on a segment opens its editor', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(const Segment(
      id: 's1',
      name: '오전',
      colorValue: 0xFF2E7D8C,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 24 * 60,
      order: 0,
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final dialFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DialPainter,
    );
    final dialCenter = tester.getCenter(dialFinder);
    final side = tester.getSize(dialFinder).width;
    final outerR = DialGeometry.outerRadius(side);
    final laneR = DialGeometry.laneRadius(outerR, 0);
    final ringOffset = TimeGeometry.pointOnCircle(Offset.zero, laneR, 0);

    await tester.tapAt(dialCenter + ringOffset);
    await tester.pumpAndSettle();

    expect(find.byType(SegmentFormPage), findsOneWidget);
  });

  testWidgets(
      "a routine completed today is passed to DialPainter's badge set, "
      'an incomplete one is not', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(const Segment(
      id: 's1',
      name: '오전',
      colorValue: 0xFF2E7D8C,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 24 * 60,
      order: 0,
    ));
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '완료한 루틴',
      startMinute: 60,
    ));
    await repo.upsertRoutine(Routine(
      id: 'r2',
      segmentId: 's1',
      title: '안 한 루틴',
      startMinute: 120,
    ));
    await repo.setCompletion(Completion.now('r1'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final painter = tester
        .widget<CustomPaint>(
          find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
        )
        .painter as DialPainter;

    expect(painter.completedRoutineIds, {'r1'});
  });

  testWidgets('app bar action opens the segment editor', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('구간 관리'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentEditorPage), findsOneWidget);
  });

  testWidgets('app bar action opens the routine editor', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('루틴 관리'));
    await tester.pumpAndSettle();

    expect(find.byType(RoutineEditorPage), findsOneWidget);
  });

  testWidgets(
      'tapping a routine marker on the dial opens it in Focus for review, '
      'regardless of whether it is actually current right now',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(const Segment(
      id: 's1',
      name: '하루',
      colorValue: 0xFF2E7D8C,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 24 * 60,
      order: 0,
    ));
    // startMinute: 0 (midnight) -- almost certainly not the real current
    // time the test runs at, so this also proves the tap doesn't depend on
    // the clock to decide whether to show it.
    await repo.upsertRoutine(const Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 0,
      microSteps: ['물 마시기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final dialFinder = find.byWidgetPredicate(
      (w) => w is CustomPaint && w.painter is DialPainter,
    );
    final dialCenter = tester.getCenter(dialFinder);
    final side = tester.getSize(dialFinder).width;
    final outerR = DialGeometry.outerRadius(side);
    final markerOffset = TimeGeometry.pointOnCircle(Offset.zero, outerR, 0);

    await tester.tapAt(dialCenter + markerOffset);
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsOneWidget);
    expect(find.text('약 먹기'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '물 마시기'), findsOneWidget);
    expect(find.text('모두 완료'), findsOneWidget);
  });

  testWidgets("the dial's semantics label reads out today's routines for screen readers",
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(const Segment(
      id: 's1', name: '하루', colorValue: 0xFF2E7D8C, iconKey: 'wb_sunny',
      startMinute: 0, endMinute: 24 * 60, order: 0,
    ));
    await repo.upsertRoutine(const Routine(
      id: 'r1', segmentId: 's1', title: '약 먹기', startMinute: 7 * 60,
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // The painted markers aren't individually focusable, so the routine has
    // to surface in the dial's own spoken label (time + title).
    expect(
      find.bySemanticsLabel(RegExp('07:00 약 먹기')),
      findsOneWidget,
    );
  });

  testWidgets("'지금' button opens FocusPage when there is a current routine",
      (tester) async {
    final repo = FakePlannerRepository();
    final nowMinute = _currentMinuteOfNow();
    await repo.upsertSegment(const Segment(
      id: 's1',
      name: '하루',
      colorValue: 0xFF2E7D8C,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 24 * 60,
      order: 0,
    ));
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: nowMinute,
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('지금'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsOneWidget);
  });

  testWidgets("'지금' button opens FocusPage even with no routines at all",
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('지금'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsOneWidget);
  });
}

int _currentMinuteOfNow() {
  final now = TimeOfDay.now();
  return now.hour * 60 + now.minute;
}
