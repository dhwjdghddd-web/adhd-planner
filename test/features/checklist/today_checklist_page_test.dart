import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/checklist/today_checklist_page.dart';

import '../../fakes/fake_planner_repository.dart';

Segment _block({
  required String id,
  required String name,
  required int startMinute,
  List<String> microSteps = const [],
  bool alarmEnabled = true,
}) {
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF112233,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: startMinute + 60,
    order: 0,
    microSteps: microSteps,
    alarmEnabled: alarmEnabled,
  );
}

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

  testWidgets('lists blocks ordered by start time', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 'late', name: '늦은 구간', startMinute: 600));
    await repo.upsertSegment(_block(id: 'early', name: '이른 구간', startMinute: 60));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final earlyTop = tester.getTopLeft(find.text('이른 구간'));
    final lateTop = tester.getTopLeft(find.text('늦은 구간'));
    expect(earlyTop.dy, lessThan(lateTop.dy));
  });

  testWidgets('an alarm-off block is labeled as such', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 's1', name: '수면', startMinute: 0, alarmEnabled: false));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('알람 꺼짐'), findsOneWidget);
  });

  testWidgets('tapping the checkbox marks a block complete, and tapping again undoes it',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(id: 's1', name: '오전', startMinute: 0));

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

  testWidgets("shows a block's items inline, with no expand step needed", (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(
        _block(id: 's1', name: '아침', startMinute: 0, microSteps: const ['세수하기', '옷 입기']));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('세수하기'), findsOneWidget);
    expect(find.text('옷 입기'), findsOneWidget);
    // block checkbox + 2 item checkboxes.
    expect(find.byType(Checkbox), findsNWidgets(3));
  });

  testWidgets('checking every item also marks the block complete', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(
        _block(id: 's1', name: '아침', startMinute: 0, microSteps: const ['세수하기', '옷 입기']));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(1));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isFalse);

    await tester.tap(find.byType(Checkbox).at(2));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(0)).value, isTrue);
  });

  testWidgets('un-checking the block clears every item it had filled', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(
        _block(id: 's1', name: '아침', startMinute: 0, microSteps: const ['세수하기', '옷 입기']));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isTrue);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isTrue);

    await tester.tap(find.byType(Checkbox).at(0));
    await tester.pumpAndSettle();
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(1)).value, isFalse);
    expect(tester.widget<Checkbox>(find.byType(Checkbox).at(2)).value, isFalse);
  });

  testWidgets('unchecking an item after full completion marks the block incomplete again',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(
        _block(id: 's1', name: '아침', startMinute: 0, microSteps: const ['세수하기', '옷 입기']));

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
