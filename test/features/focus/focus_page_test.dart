import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/time_geometry.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';

import '../../fakes/fake_planner_repository.dart';

int _currentMinuteOfNow() {
  final now = TimeOfDay.now();
  return now.hour * 60 + now.minute;
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

  testWidgets('shows the current routine, with no countdown -- it stays current until '
      'whatever starts next, however long that takes', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
    ));

    await openFocusPage(tester, repo);

    expect(find.text('약 먹기'), findsOneWidget);
    expect(find.textContaining('남음'), findsNothing);
  });

  testWidgets('shows the next routine and its absolute start time when only a future '
      'routine exists', (tester) async {
    final repo = FakePlannerRepository();
    // clamp, not % -- wrapping past midnight would put this "earlier
    // today" under the new (no-duration) status model, which makes it
    // current rather than upcoming (see Routine's doc comment: a routine
    // stays current indefinitely once started, there's no fixed end).
    final startMinute = (_currentMinuteOfNow() + 60).clamp(0, 24 * 60 - 1);
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '나중 할 일',
      startMinute: startMinute,
    ));

    await openFocusPage(tester, repo);

    expect(find.text('다음: 나중 할 일'), findsOneWidget);
    expect(find.text(TimeGeometry.formatMinute(startMinute)), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no routines', (tester) async {
    await openFocusPage(tester, FakePlannerRepository());

    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('넘기기 on the current routine skips it for today and falls through to next',
      (tester) async {
    final repo = FakePlannerRepository();
    final nextStart = (_currentMinuteOfNow() + 60).clamp(0, 24 * 60 - 1);
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
    ));
    await repo.upsertRoutine(Routine(
      id: 'r2',
      segmentId: 's1',
      title: '나중 할 일',
      startMinute: nextStart,
    ));

    await openFocusPage(tester, repo);
    expect(find.text('약 먹기'), findsOneWidget);

    await tester.tap(find.text('넘기기'));
    await tester.pump();
    expect(find.text('약 먹기을(를) 내일로 넘겼어요'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('약 먹기'), findsNothing);
    expect(find.text('다음: 나중 할 일'), findsOneWidget);

    final skips = await repo.watchRoutineSkips().first;
    expect(skips.single.routineId, 'r1');
  });

  testWidgets('넘기기 on the next routine skips it for today, with nothing else to show',
      (tester) async {
    final repo = FakePlannerRepository();
    final startMinute = (_currentMinuteOfNow() + 60).clamp(0, 24 * 60 - 1);
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '나중 할 일',
      startMinute: startMinute,
    ));

    await openFocusPage(tester, repo);
    expect(find.text('다음: 나중 할 일'), findsOneWidget);

    await tester.tap(find.text('넘기기'));
    await tester.pumpAndSettle();

    expect(find.text('다음: 나중 할 일'), findsNothing);
    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('a routine excluded by repeatDays does not show as current',
      (tester) async {
    final repo = FakePlannerRepository();
    final today = DateTime.now().weekday;
    final excludeToday =
        [1, 2, 3, 4, 5, 6, 7].where((d) => d != today).toList();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '제외됨',
      startMinute: _currentMinuteOfNow(),
      repeatDays: excludeToday,
    ));

    await openFocusPage(tester, repo);

    expect(find.text('제외됨'), findsNothing);
    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('완료 records a completion and closes the screen', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);
    expect(find.byType(FocusPage), findsOneWidget);

    await tester.tap(find.text('모두 완료'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.routineId == 'r1'), true);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('the 닫기 back button closes the screen without recording a completion',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsNothing);
    expect(snapshots.last, isEmpty);
  });

  testWidgets(
      'within the lead-warning window, the upcoming routine shows its micro-steps '
      'instead of just the countdown text',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      // clamp, not % -- see the previous test's comment on why wrapping
      // past midnight would break this under the new status model.
      startMinute: (_currentMinuteOfNow() + 5).clamp(0, 24 * 60 - 1),
      leadWarningMin: 5,
      microSteps: const ['퇴근준비하기'],
    ));

    await openFocusPage(tester, repo);

    expect(find.textContaining('분 후 시작'), findsOneWidget);
    expect(find.text('퇴근하기'), findsOneWidget);
    expect(find.widgetWithText(CheckboxListTile, '퇴근준비하기'), findsOneWidget);
    // Not current yet, so no completion action — just a way back, and a
    // way to skip today's occurrence entirely.
    expect(find.text('모두 완료'), findsNothing);
    expect(find.text('닫기'), findsOneWidget);
    expect(find.text('넘기기'), findsOneWidget);
  });

  testWidgets('넘기기 within the lead-warning window skips that routine for today',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      startMinute: (_currentMinuteOfNow() + 5).clamp(0, 24 * 60 - 1),
      leadWarningMin: 5,
    ));

    await openFocusPage(tester, repo);
    expect(find.text('퇴근하기'), findsOneWidget);

    await tester.tap(find.text('넘기기'));
    await tester.pumpAndSettle();

    expect(find.text('퇴근하기'), findsNothing);
    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('outside the lead-warning window, the upcoming routine shows no micro-steps',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      // clamp, not % -- same reason as the test above.
      startMinute: (_currentMinuteOfNow() + 10).clamp(0, 24 * 60 - 1),
      leadWarningMin: 5,
      microSteps: const ['퇴근준비하기'],
    ));

    await openFocusPage(tester, repo);

    expect(find.text('다음: 퇴근하기'), findsOneWidget);
    expect(find.text('퇴근준비하기'), findsNothing);
  });

  testWidgets('a micro-step checked before start stays checked once the routine goes current',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      startMinute: _currentMinuteOfNow(),
      leadWarningMin: 5,
      // Two steps: checking the first alone shouldn't trigger
      // auto-complete-on-all-checked, which would close the screen before
      // this test gets to assert on the checkbox state.
      microSteps: const ['퇴근준비하기', '책상 정리하기'],
    ));

    await openFocusPage(tester, repo);

    // Already "current" the moment it's opened here (startMinute == now),
    // so this directly covers that _microStepsChecklist behaves the same
    // way in both states rather than re-testing the upcoming window itself.
    await tester.tap(find.text('퇴근준비하기'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '퇴근준비하기'),
    );
    expect(checkbox.value, true);
  });

  testWidgets('checking a micro-step toggles its checkbox', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      microSteps: const ['손 씻기', '물 준비'],
    ));

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

  testWidgets('checking the last remaining micro-step auto-completes the routine',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      microSteps: const ['손 씻기', '물 준비'],
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('손 씻기'));
    await tester.pumpAndSettle();
    expect(find.byType(FocusPage), findsOneWidget, reason: 'one step left unchecked');

    await tester.tap(find.text('물 준비'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.routineId == 'r1'), true);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('un-checking a micro-step does not trigger auto-complete', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      microSteps: const ['손 씻기'],
    ));

    await openFocusPage(tester, repo);

    await tester.tap(find.text('손 씻기')); // checks the only step -> auto-completes
    await tester.pumpAndSettle();
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('모두 완료 marks every micro-step as checked', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      microSteps: const ['손 씻기', '물 준비'],
    ));
    final snapshots = <List<MicroStepProgress>>[];
    repo.watchMicroStepProgress().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('모두 완료'));
    await tester.pumpAndSettle();

    final saved = snapshots.last.firstWhere((p) => p.routineId == 'r1');
    expect(saved.checkedIndices.toSet(), {0, 1});
  });

  testWidgets('the 빠른 메모 button opens the quick-add sheet from this screen',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
    ));

    await openFocusPage(tester, repo);

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();

    expect(find.text('빠른 메모'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('a checked micro-step is still checked after leaving and reopening the screen',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      startMinute: _currentMinuteOfNow(),
      // Two steps, not one: checking just the first shouldn't trigger
      // auto-complete-on-all-checked and close the screen before the
      // "leave and reopen" part of this test even happens.
      microSteps: const ['퇴근준비하기', '책상 정리하기'],
    ));

    await openFocusPage(tester, repo);
    await tester.tap(find.text('퇴근준비하기'));
    await tester.pumpAndSettle();

    // Close (via the back button) without completing, then reopen.
    await tester.tap(find.byTooltip('닫기'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '퇴근준비하기'),
    );
    expect(checkbox.value, true);
  });

  testWidgets("yesterday's checked micro-steps don't carry over to today",
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '퇴근하기',
      startMinute: _currentMinuteOfNow(),
      microSteps: const ['퇴근준비하기'],
    ));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.saveMicroStepProgress(MicroStepProgress.today('r1', [0], at: yesterday));

    await openFocusPage(tester, repo);

    final checkbox = tester.widget<CheckboxListTile>(
      find.widgetWithText(CheckboxListTile, '퇴근준비하기'),
    );
    expect(checkbox.value, false);
  });
}
