import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/alarm_alert_dialog.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  // AlarmAlertDialog is always popped via showDialog over the existing
  // Navigator (see app.dart's _AlarmAlertLauncher) -- never as
  // MaterialApp.home directly -- so wrap it the same way here.
  Widget wrap(FakePlannerRepository repo, {String routineId = 'r1', int notificationId = 42}) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
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
    expect(find.text('완료'), findsNothing);
  });

  testWidgets('완료 records a completion and closes the dialog', (tester) async {
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

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.routineId == 'r1'), true);
    expect(find.byType(AlarmAlertDialog), findsNothing);
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

    expect(completions.last, isEmpty);
    expect(find.byType(AlarmAlertDialog), findsNothing);
    final saved = postponements.last.firstWhere((p) => p.routineId == 'r1');
    expect(saved.offsetMinutes, 5);
  });
}
