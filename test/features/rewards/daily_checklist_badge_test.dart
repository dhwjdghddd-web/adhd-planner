import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/rewards/daily_checklist_badge.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: Scaffold(body: DailyChecklistBadge())),
    );
  }

  Routine routine(String id, List<String> microSteps, {List<int> repeatDays = const []}) {
    return Routine(
      id: id,
      segmentId: null,
      title: id,
      startMinute: 0,
      microSteps: microSteps,
      repeatDays: repeatDays,
    );
  }

  testWidgets('shows a plain label when a today-applicable routine has no micro-steps',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(routine('r1', const []));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // No counts to show, but the badge still has to stay tappable as the
    // entry point into the full today-checklist screen.
    expect(find.text('오늘 체크리스트'), findsOneWidget);
  });

  testWidgets('shows nothing when no routine at all is scheduled for today', (tester) async {
    final repo = FakePlannerRepository();
    final today = DateTime.now().weekday;
    final notToday = [1, 2, 3, 4, 5, 6, 7].where((d) => d != today).toList();
    await repo.upsertRoutine(routine('r1', const ['a'], repeatDays: notToday));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('체크리스트'), findsNothing);
  });

  testWidgets('sums micro-steps across every today-applicable routine', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(routine('r1', const ['a', 'b']));
    await repo.upsertRoutine(routine('r2', const ['c', 'd', 'e']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('r1', const [0]));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 1/5'), findsOneWidget);
  });

  testWidgets('excludes a routine not scheduled for today', (tester) async {
    final repo = FakePlannerRepository();
    final today = DateTime.now().weekday;
    final notToday = [1, 2, 3, 4, 5, 6, 7].where((d) => d != today).toList();
    await repo.upsertRoutine(routine('r1', const ['a', 'b']));
    await repo.upsertRoutine(routine('r2', const ['c'], repeatDays: notToday));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 0/2'), findsOneWidget);
  });

  testWidgets("excludes yesterday's checked progress from today's count", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(routine('r1', const ['a', 'b']));
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    await repo.saveMicroStepProgress(MicroStepProgress.today('r1', const [0], at: yesterday));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 0/2'), findsOneWidget);
  });

  testWidgets("excludes a routine skipped today from the count, even fully checked",
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(routine('skipped', const ['a', 'b']));
    await repo.upsertRoutine(routine('kept', const ['c', 'd']));
    await repo.saveRoutineSkip(RoutineSkip.today('skipped'));
    await repo.saveMicroStepProgress(MicroStepProgress.today('skipped', const [0, 1]));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 체크리스트 0/2'), findsOneWidget);
  });

  testWidgets('switches to the streak flame icon once half of today is checked',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(routine('r1', const ['a', 'b']));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.checklist_rtl);

    await repo.saveMicroStepProgress(MicroStepProgress.today('r1', const [0]));
    await tester.pumpAndSettle();

    expect(tester.widget<Icon>(find.byType(Icon)).icon, Icons.local_fire_department);
  });
}
