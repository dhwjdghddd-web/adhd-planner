import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/checklist/today_checklist_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: TodayChecklistPage()),
    );
  }

  testWidgets('shows an empty state when nothing is scheduled today', (tester) async {
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('오늘 일정이 없어요'), findsOneWidget);
  });

  testWidgets('lists only routines scheduled for today, ordered by start time',
      (tester) async {
    final repo = FakePlannerRepository();
    final today = DateTime.now().weekday;
    final notToday = [1, 2, 3, 4, 5, 6, 7].where((d) => d != today).toList();
    await repo.upsertRoutine(Routine(id: 'late', segmentId: null, title: '늦은 일', startMinute: 600));
    await repo.upsertRoutine(Routine(id: 'early', segmentId: null, title: '이른 일', startMinute: 60));
    await repo.upsertRoutine(Routine(
      id: 'other-day',
      segmentId: null,
      title: '다른 날',
      startMinute: 0,
      repeatDays: notToday,
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('다른 날'), findsNothing);
    final earlyTop = tester.getTopLeft(find.text('이른 일'));
    final lateTop = tester.getTopLeft(find.text('늦은 일'));
    expect(earlyTop.dy, lessThan(lateTop.dy));
  });

  testWidgets('a routine skipped today still appears and stays checkable, labeled as skipped',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(
        Routine(id: 'r1', segmentId: null, title: '건너뜬 일', startMinute: 0));
    await repo.saveRoutineSkip(RoutineSkip.today('r1'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('건너뜀'), findsOneWidget);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(repo.watchCompletions(), emits(predicate<List<Completion>>(
        (list) => list.any((c) => c.routineId == 'r1'))));
  });

  testWidgets('tapping the checkbox marks a routine complete, and tapping again undoes it',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(
        Routine(id: 'r1', segmentId: null, title: '오늘 할 일', startMinute: 0));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isFalse);
  });

  testWidgets('shows the segment name next to each routine', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(const Segment(
      id: 's1',
      name: '아침',
      colorValue: 0xFF112233,
      iconKey: 'sun',
      startMinute: 0,
      endMinute: 300,
      order: 0,
    ));
    await repo.upsertRoutine(
        Routine(id: 'r1', segmentId: 's1', title: '아침 루틴', startMinute: 30));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아침'), findsWidgets);
  });

  testWidgets('reflects a today postponement in the displayed (sorted) order', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(
        Routine(id: 'pushed', segmentId: null, title: '밀린 일', startMinute: 60));
    await repo.upsertRoutine(
        Routine(id: 'fixed', segmentId: null, title: '고정 일', startMinute: 120));
    // Pushes "밀린 일" from 01:00 to 03:00, past "고정 일" at 02:00.
    await repo.saveRoutinePostponement(RoutinePostponement.today('pushed', 120));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final fixedTop = tester.getTopLeft(find.text('고정 일'));
    final pushedTop = tester.getTopLeft(find.text('밀린 일'));
    expect(fixedTop.dy, lessThan(pushedTop.dy));
  });

  testWidgets('shows a routine\'s micro-steps inline, with no expand step needed',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: null,
      title: '아침 루틴',
      startMinute: 0,
      microSteps: const ['세수하기', '옷 입기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('세수하기'), findsOneWidget);
    expect(find.text('옷 입기'), findsOneWidget);
    // routine checkbox + 2 micro-step checkboxes.
    expect(find.byType(Checkbox), findsNWidgets(3));
  });

  testWidgets('checking every micro-step also marks the routine complete', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: null,
      title: '아침 루틴',
      startMinute: 0,
      microSteps: const ['세수하기', '옷 입기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isFalse);

    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isTrue);
  });

  testWidgets('un-checking the routine clears every micro-step it had filled',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: null,
      title: '아침 루틴',
      startMinute: 0,
      microSteps: const ['세수하기', '옷 입기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    // Complete via the routine checkbox: fills both micro-steps.
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isTrue);

    // Un-check it again: both micro-steps must clear, not stay ticked.
    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isFalse);
  });

  testWidgets('marking a routine complete via its own checkbox checks every micro-step too',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: null,
      title: '아침 루틴',
      startMinute: 0,
      microSteps: const ['세수하기', '옷 입기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isTrue);
  });

  testWidgets(
      'unchecking a micro-step after full completion marks the routine incomplete again',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: null,
      title: '아침 루틴',
      startMinute: 0,
      microSteps: const ['세수하기', '옷 입기'],
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isTrue);

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();

    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isFalse);
  });
}
