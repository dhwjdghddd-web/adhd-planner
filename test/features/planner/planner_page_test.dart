import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/time_geometry.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/planner/dial_painter.dart';
import 'package:adhd_planner/features/planner/planner_page.dart';
import 'package:adhd_planner/features/rewards/streak_badge.dart';
import 'package:adhd_planner/features/segments/segment_editor_page.dart';
import 'package:adhd_planner/features/segments/segment_form_page.dart';

import '../../fakes/fake_planner_repository.dart';

Segment _block({
  String id = 's1',
  String name = '하루',
  int startMinute = 0,
  int endMinute = 24 * 60,
  List<String> microSteps = const [],
}) {
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF2E7D8C,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: endMinute,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  Widget wrap(FakePlannerRepository repo, {int? debugNowMinuteOfDay}) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: PlannerPage(debugNowMinuteOfDay: debugNowMinuteOfDay),
      ),
    );
  }

  testWidgets(
      'shows the starter-chip empty state (not the dial) when there are no blocks',
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    // No dial at all -- the empty state replaces it outright.
    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
        findsNothing);
    expect(find.text('기상'), findsOneWidget);
    expect(find.text('수면'), findsOneWidget);
  });

  testWidgets('tapping a starter chip adds exactly that block and the dial '
      'replaces the empty state', (tester) async {
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ActionChip, '기상'));
    await tester.pumpAndSettle();

    expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
        findsOneWidget);
    final saved = await repo.watchSegments().first;
    expect(saved.map((s) => s.name), ['기상']);
  });

  testWidgets('tapping the dial on a block opens it in Focus (review), not the editor',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(name: '하루', microSteps: const ['물 마시기']));

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

    expect(find.byType(FocusPage), findsOneWidget);
    expect(find.byType(SegmentFormPage), findsNothing);
    expect(find.widgetWithText(CheckboxListTile, '물 마시기'), findsOneWidget);
  });

  testWidgets("a block completed today is passed to DialPainter's badge set, "
      'an incomplete one is not', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 'done', name: '완료한 구간', startMinute: 60, endMinute: 120));
    await repo.upsertSegment(_block(id: 'todo', name: '안 한 구간', startMinute: 120, endMinute: 180));
    await repo.setCompletion(Completion.now('done'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final painter = tester
        .widget<CustomPaint>(
          find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
        )
        .painter as DialPainter;

    expect(painter.completedSegmentIds, {'done'});
  });

  testWidgets('app bar action opens the segment editor', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('구간 관리'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentEditorPage), findsOneWidget);
  });

  testWidgets('the 구간 추가 FAB opens a blank segment form', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.bySemanticsLabel('구간 추가'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentFormPage), findsOneWidget);
  });

  testWidgets("the dial's semantics label reads out today's blocks for screen readers",
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 's1', name: '아침', startMinute: 7 * 60, endMinute: 9 * 60));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // Scoped to the dial's own label ("오늘 일정: …"); the today-timeline strip
    // below now also reads each block out as its own tappable item.
    expect(find.bySemanticsLabel(RegExp('오늘 일정:.*07:00 아침')), findsOneWidget);
  });

  testWidgets("'지금' button opens FocusPage", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('지금'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsOneWidget);
  });

  // '지금' lives inside the dial's centre summary, which the empty state
  // (see above) replaces outright -- with no blocks at all there's no dial,
  // and the starter chips are the correct way in now, not a contentless Focus.

  group('T6 -- 다음 한 행동 (next action) mode', () {
    const dayMinute = 9 * 60; // pinned "now" -- 09:00.

    testWidgets('tapping the toggle switches from the dial to 다음 한 행동 and back',
        (tester) async {
      final repo = FakePlannerRepository();
      // ±60분 (not the whole day) -- start=0/end=24*60 wraps to lengthMinutes
      // 0 under findBlockStatus's modular math, which would skip it as
      // degenerate rather than read as "always current".
      await repo.upsertSegment(
        _block(startMinute: dayMinute - 60, endMinute: dayMinute + 60),
      );

      await tester.pumpWidget(wrap(repo, debugNowMinuteOfDay: dayMinute));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
          findsOneWidget);

      await tester.tap(find.byTooltip('다음 한 행동 보기'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
          findsNothing);
      expect(find.text('시작'), findsOneWidget);

      await tester.tap(find.byTooltip('다이얼 보기'));
      await tester.pumpAndSettle();

      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
          findsOneWidget);
    });

    testWidgets('shows the current block (지금) with no dial/badges/countdown',
        (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveSettings(
        const AppSettings.defaults().copyWith(homeViewMode: HomeViewMode.nextAction),
      );
      await repo.upsertSegment(
        _block(name: '아침', startMinute: dayMinute - 60, endMinute: dayMinute + 60),
      );

      await tester.pumpWidget(wrap(repo, debugNowMinuteOfDay: dayMinute));
      await tester.pumpAndSettle();

      expect(find.text('아침'), findsOneWidget);
      expect(find.text('지금'), findsOneWidget);
      expect(find.text('시작'), findsOneWidget);
      expect(find.byWidgetPredicate((w) => w is CustomPaint && w.painter is DialPainter),
          findsNothing);
      expect(find.byType(StreakBadge), findsNothing);
    });

    testWidgets('shows the next block with its start time when nothing is current',
        (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveSettings(
        const AppSettings.defaults().copyWith(homeViewMode: HomeViewMode.nextAction),
      );
      await repo.upsertSegment(_block(
        name: '오후 회의',
        startMinute: dayMinute + 60,
        endMinute: dayMinute + 120,
      ));

      await tester.pumpWidget(wrap(repo, debugNowMinuteOfDay: dayMinute));
      await tester.pumpAndSettle();

      expect(find.text('오후 회의'), findsOneWidget);
      expect(find.textContaining('다음'), findsOneWidget);
    });

    testWidgets('shows a calm empty message when there is nothing current or next',
        (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveSettings(
        const AppSettings.defaults().copyWith(homeViewMode: HomeViewMode.nextAction),
      );

      await tester.pumpWidget(wrap(repo, debugNowMinuteOfDay: dayMinute));
      await tester.pumpAndSettle();

      expect(find.textContaining('지금이나 다음 일정이 없어요'), findsOneWidget);
      expect(find.text('시작'), findsNothing);
      // The dial's own empty-state starter chips must not show here either --
      // 다음 한 행동 has its own, separate empty message.
      expect(find.text('아직 만든 구간이 없어요\n아래에서 하나 골라 시작해보세요'), findsNothing);
    });

    testWidgets('시작 opens FocusPage.forBlock for that exact segment', (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveSettings(
        const AppSettings.defaults().copyWith(homeViewMode: HomeViewMode.nextAction),
      );
      await repo.upsertSegment(_block(
        name: '아침',
        startMinute: dayMinute - 60,
        endMinute: dayMinute + 60,
        microSteps: const ['물 마시기'],
      ));

      await tester.pumpWidget(wrap(repo, debugNowMinuteOfDay: dayMinute));
      await tester.pumpAndSettle();

      await tester.tap(find.text('시작'));
      await tester.pumpAndSettle();

      expect(find.byType(FocusPage), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, '물 마시기'), findsOneWidget);
    });
  });
}
