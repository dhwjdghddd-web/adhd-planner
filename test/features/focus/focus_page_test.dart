import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/completion.dart';
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

  testWidgets('shows the current routine with its countdown', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      durationMin: 30,
    ));

    await openFocusPage(tester, repo);

    expect(find.text('약 먹기'), findsOneWidget);
    expect(find.textContaining('남음'), findsOneWidget);
  });

  testWidgets('shows "다음 루틴까지 N분" when only a future routine exists',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '나중 할 일',
      startMinute: (_currentMinuteOfNow() + 60) % (24 * 60),
      durationMin: 30,
    ));

    await openFocusPage(tester, repo);

    expect(find.textContaining('다음 루틴까지'), findsOneWidget);
    expect(find.text('나중 할 일'), findsOneWidget);
  });

  testWidgets('shows the empty state when there are no routines', (tester) async {
    await openFocusPage(tester, FakePlannerRepository());

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
      durationMin: 30,
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
      durationMin: 30,
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);
    expect(find.byType(FocusPage), findsOneWidget);

    await tester.tap(find.text('완료'));
    await tester.pumpAndSettle();

    expect(snapshots.last.any((c) => c.routineId == 'r1'), true);
    expect(find.byType(FocusPage), findsNothing);
  });

  testWidgets('다음 할 일 closes the screen without recording a completion',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      durationMin: 30,
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('다음 할 일'));
    await tester.pumpAndSettle();

    expect(find.byType(FocusPage), findsNothing);
    expect(snapshots.last, isEmpty);
  });

  testWidgets('스누즈 shows a snackbar and records no completion', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      durationMin: 30,
    ));
    final snapshots = <List<Completion>>[];
    repo.watchCompletions().listen(snapshots.add);

    await openFocusPage(tester, repo);

    await tester.tap(find.text('스누즈'));
    await tester.pump();

    expect(find.textContaining('STEP 8'), findsOneWidget);
    expect(find.byType(FocusPage), findsOneWidget);
    expect(snapshots.last, isEmpty);
  });

  testWidgets('checking a micro-step toggles its checkbox', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertRoutine(Routine(
      id: 'r1',
      segmentId: 's1',
      title: '약 먹기',
      startMinute: _currentMinuteOfNow(),
      durationMin: 30,
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
}
