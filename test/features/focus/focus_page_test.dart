import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/time_geometry.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';

import '../../fakes/fake_planner_repository.dart';

int _currentMinuteOfNow() {
  final now = TimeOfDay.now();
  return now.hour * 60 + now.minute;
}

/// A block whose range reliably contains "now" (so it reads as current),
/// with a margin so a clock tick mid-test can't push now outside it.
Segment _currentBlock({
  String id = 's1',
  String name = '약 먹기',
  List<String> microSteps = const [],
}) {
  final now = _currentMinuteOfNow();
  final start = now >= 30 ? now - 30 : 0;
  final end = (now + 30) > 1440 ? 1440 : now + 30;
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: start,
    endMinute: end,
    order: 0,
    microSteps: microSteps,
  );
}

/// A block strictly in the future with no overlap of now (reads as "next").
Segment _futureBlock({String id = 's1', String name = '나중 일', List<String> microSteps = const []}) {
  final now = _currentMinuteOfNow();
  final start = (now + 60) > 1380 ? 1380 : now + 60;
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: start,
    endMinute: start + 30,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FocusPage()),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openFocusPage(WidgetTester tester, FakePlannerRepository repo) async {
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the current block', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(name: '오전', microSteps: const ['아무거나']));

    await openFocusPage(tester, repo);

    expect(find.text('오전'), findsOneWidget);
  });

  testWidgets(
      'a current block with no checklist defers to the next block instead of '
      'showing a completion screen', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(id: 's1', name: '회의'));
    await repo.upsertSegment(_futureBlock(id: 's2', name: '저녁', microSteps: const ['저녁 먹기']));

    await openFocusPage(tester, repo);

    expect(find.text('회의'), findsNothing);
    expect(find.text('모두 완료'), findsNothing);
    expect(find.text('다음: 저녁'), findsOneWidget);
  });

  testWidgets('a pinned block with no items stays horizontally centered '
      '(regression: body Column used to shrink-wrap and hug the left edge)',
      (tester) async {
    final repo = FakePlannerRepository();
    final block = Segment(
      id: 's1',
      name: '오전',
      colorValue: 0xFF000000,
      iconKey: 'wb_sunny',
      startMinute: 0,
      endMinute: 60,
      order: 0,
    );
    await repo.upsertSegment(block);

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(home: FocusPage.forBlock(block)),
    ));
    await tester.pumpAndSettle();

    final screenCenterX = tester.view.physicalSize.width / tester.view.devicePixelRatio / 2;
    final titleCenterX = tester.getCenter(find.text('오전')).dx;
    expect(titleCenterX, closeTo(screenCenterX, 1.0));
  });

  testWidgets('shows the next block and its start time when only a future block exists',
      (tester) async {
    final repo = FakePlannerRepository();
    final block = _futureBlock(name: '저녁');
    await repo.upsertSegment(block);

    await openFocusPage(tester, repo);

    // WaitingIllustration renders each line of the message as its own Text.
    expect(find.text('다음: 저녁'), findsOneWidget);
    expect(find.text(TimeGeometry.formatMinute(block.startMinute)), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no blocks', (tester) async {
    await openFocusPage(tester, FakePlannerRepository());

    expect(find.textContaining('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('완료 records a completion and closes the screen', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(name: '오전', microSteps: const ['아무거나']));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);
    expect(find.byType(FocusPage), findsOneWidget);

    await tester.tap(find.text('모두 완료'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.segmentId == 's1'), true);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('the 닫기 back button closes the screen without recording a completion',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock());
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsNothing);
    expect(snapshots.last, isEmpty);
  });

  testWidgets('checking an item toggles its checkbox', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(microSteps: const ['손 씻기', '물 준비']));

    await openFocusPage(tester, repo);

    final before = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '손 씻기'),
    );
    expect(before.value, false);

    await tester.tap(find.text('손 씻기'));
    await tester.pumpAndSettle();

    final after = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '손 씻기'),
    );
    expect(after.value, true);
  });

  testWidgets('checking the last remaining item auto-completes the block', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(microSteps: const ['손 씻기', '물 준비']));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('손 씻기'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusPage), findsOneWidget, reason: 'one item left unchecked');

    await tester.tap(find.text('물 준비'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.segmentId == 's1'), true);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('모두 완료 marks every item as checked', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(microSteps: const ['손 씻기', '물 준비']));
    final snapshots = <List<MicroStepProgress>>[];
    repo.watchMicroStepProgress().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('모두 완료'));
    await tester.pumpAndSettle();

    final saved = snapshots.last.firstWhere((p) => p.segmentId == 's1');
    expect(saved.checkedIndices.toSet(), {0, 1});
  });

  testWidgets('the 빠른 메모 button opens the quick-add sheet from this screen',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock());

    await openFocusPage(tester, repo);

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();

    expect(find.text('빠른 메모'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a checked item is still checked after leaving and reopening the screen',
      (tester) async {
    final repo = FakePlannerRepository();
    // Two items: checking just the first shouldn't auto-complete and close.
    await repo.upsertSegment(_currentBlock(microSteps: const ['퇴근준비하기', '책상 정리하기']));

    await openFocusPage(tester, repo);
    await tester.tap(find.text('퇴근준비하기'));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '퇴근준비하기'),
    );
    expect(checkbox.value, true);
  });

  group('FocusPage.forBlock (dial arc review mode)', () {
    Widget wrapForBlock(FakePlannerRepository repo, Segment block) {
      return ProviderScope(
        overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(home: FocusPage.forBlock(block)),
      );
    }

    testWidgets('shows the pinned block and its checklist even when its time has passed',
        (tester) async {
      final repo = FakePlannerRepository();
      final block = Segment(
        id: 's1',
        name: '아침',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
        microSteps: const ['물 마시기', '식후 30분 확인'],
      );
      await repo.upsertSegment(block);

      await tester.pumpWidget(wrapForBlock(repo, block));
      await tester.pumpAndSettle();

      expect(find.text('아침'), findsOneWidget);
      expect(find.widgetWithText(CheckboxListTile, '물 마시기'), findsOneWidget);
      expect(find.text('모두 완료'), findsOneWidget);
    });

    testWidgets('checking an item in review mode persists it', (tester) async {
      final repo = FakePlannerRepository();
      final block = Segment(
        id: 's1',
        name: '아침',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
        microSteps: const ['물 마시기', '식후 30분 확인'],
      );
      await repo.upsertSegment(block);
      final snapshots = <List<MicroStepProgress>>[];
      repo.watchMicroStepProgress().listen(snapshots.add);

      await tester.pumpWidget(wrapForBlock(repo, block));
      await tester.pumpAndSettle();

      await tester.tap(find.text('물 마시기'));
      await tester.pumpAndSettle();

      final saved = snapshots.last.firstWhere((p) => p.segmentId == 's1');
      expect(saved.checkedIndices, [0]);
    });

    testWidgets('모두 완료 in review mode records a completion and closes the screen',
        (tester) async {
      final repo = FakePlannerRepository();
      final block = Segment(
        id: 's1',
        name: '아침',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
        microSteps: const ['물 마시기'],
      );
      await repo.upsertSegment(block);
      final snapshots = <List<Completion>>[];
      repo.watchCompletions().listen(snapshots.add);

      await tester.pumpWidget(wrapForBlock(repo, block));
      await tester.pumpAndSettle();

      await tester.tap(find.text('모두 완료'));
      await tester.pumpAndSettle();

      expect(snapshots.last.any((c) => c.segmentId == 's1'), true);
      expect(find.byType(FocusPage), findsNothing);
    });

    testWidgets('a block with no checklist has no 모두 완료 button in review mode '
        "either (nothing to complete -- doesn't move the streak ratio at all)",
        (tester) async {
      final repo = FakePlannerRepository();
      final block = Segment(
        id: 's1',
        name: '퇴근',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
      );
      await repo.upsertSegment(block);

      await tester.pumpWidget(wrapForBlock(repo, block));
      await tester.pumpAndSettle();

      expect(find.text('퇴근'), findsOneWidget);
      expect(find.text('모두 완료'), findsNothing);
    });

    testWidgets('a block with no checklist shows the calm waiting illustration '
        'instead of a blank body', (tester) async {
      final repo = FakePlannerRepository();
      final block = Segment(
        id: 's1',
        name: '퇴근',
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 0,
        endMinute: 60,
        order: 0,
      );
      await repo.upsertSegment(block);

      await tester.pumpWidget(wrapForBlock(repo, block));
      await tester.pumpAndSettle();

      expect(find.text('퇴근'), findsOneWidget);
      expect(find.textContaining('체크할 항목이 없어요'), findsOneWidget);
    });
  });

  testWidgets("yesterday's checked items don't carry over to today", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_currentBlock(microSteps: const ['퇴근준비하기']));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', [0], at: yesterday));

    await openFocusPage(tester, repo);

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '퇴근준비하기'),
    );
    expect(checkbox.value, false);
  });
}
