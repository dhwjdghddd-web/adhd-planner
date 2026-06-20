import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/alarm_alert_dialog.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  // AlarmAlertDialog is always popped via showDialog over the existing
  // Navigator (see app.dart's _AlarmAlertLauncher) -- never as
  // MaterialApp.home directly -- so wrap it the same way here. 확인's
  // "open Focus" path specifically also needs the real app's
  // navigatorKey wired up, the same as app.dart does, since it reaches
  // the Navigator through that key rather than the dialog's own context.
  Widget wrap(FakePlannerRepository repo, {String routineId = 'r1', int notificationId = 42}) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) =>
                      AlarmAlertDialog(routineId: routineId, notificationId: notificationId),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> openAlarmAlert(WidgetTester tester, FakePlannerRepository repo) async {
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the routine title and start time', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 9 * 60 + 30,
    ));

    await openAlarmAlert(tester, repo);

    expect(find.text('약 먹기'), findsOneWidget);
    expect(find.text('09:30'), findsOneWidget);
  });

  testWidgets('shows a not-found state when the routine no longer exists', (tester) async {
    final repo = FakePlannerRepository();

    await openAlarmAlert(tester, repo);

    expect(find.text('루틴을 찾을 수 없어요'), findsOneWidget);
    expect(find.text('확인'), findsNothing);
  });

  testWidgets(
      '확인 on the main alarm just turns it off (no completion) and opens Focus',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 9 * 60,
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openAlarmAlert(tester, repo);

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(snapshots.last, isEmpty);
    expect(find.byType(AlarmAlertDialog), findsNothing);
    expect(find.byType(FocusPage), findsOneWidget);
  });

  testWidgets('확인 on a lead-warning just turns it off, without opening Focus',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 9 * 60,
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        navigatorKey: appNavigatorKey,
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  builder: (_) => const AlarmAlertDialog(
                    routineId: 'r1',
                    notificationId: 42,
                    isTransition: true,
                  ),
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('확인'));
    await tester.pumpAndSettle();

    expect(snapshots.last, isEmpty);
    expect(find.byType(AlarmAlertDialog), findsNothing);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('미루기 records a postponement, closes the dialog, and records no completion',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 9 * 60,
      snoozeMin: 5,
    ));
    final completions = <List<Completion>>[];
    repo.watchCompletions().listen(completions.add);
    final postponements = <List<RoutinePostponement>>[];
    repo.watchRoutinePostponements().listen(postponements.add);

    await openAlarmAlert(tester, repo);

    await tester.tap(find.text('미루기'));
    await tester.pumpAndSettle();
    // postpone() is fire-and-forget from the dialog's button handler and
    // awaits a real platform-channel call (timezone lookup) before saving
    // -- pump/pumpAndSettle only drive frames, not real async time, so
    // runAsync is needed to let that actually resolve.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();

    expect(completions.last, isEmpty);
    expect(find.byType(AlarmAlertDialog), findsNothing);
    final saved = postponements.last.firstWhere((p) => p.routineId == 'r1');
    expect(saved.offsetMinutes, 5);
  });

  testWidgets('넘기기 records a skip, closes the dialog, and records no completion',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: 9 * 60,
    ));
    final completions = <List<Completion>>[];
    repo.watchCompletions().listen(completions.add);
    final skips = <List<RoutineSkip>>[];
    repo.watchRoutineSkips().listen(skips.add);

    await openAlarmAlert(tester, repo);

    await tester.tap(find.text('넘기기'));
    await tester.pumpAndSettle();

    expect(completions.last, isEmpty);
    expect(find.byType(AlarmAlertDialog), findsNothing);
    expect(skips.last.single.routineId, 'r1');
  });
}
