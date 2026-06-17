import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/routines/routine_form_page.dart';

import '../../fakes/fake_planner_repository.dart';

const _segment = Segment(
  id: 's1',
  name: '오전',
  colorValue: 0xFF2E7D8C,
  iconKey: 'wb_sunny',
  startMinute: 6 * 60,
  endMinute: 12 * 60,
  order: 0,
);

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: RoutineFormPage()),
    );
  }

  Future<FakePlannerRepository> repoWithSegment() async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_segment);
    return repo;
  }

  String? durationText(WidgetTester tester) =>
      tester.widget<Text>(find.byKey(const Key('routineDurationValue'))).data;

  // The form is taller than the default test surface, which would leave
  // ListView children below the fold un-inflated. Growing the surface so
  // the whole form fits avoids fighting Sliver virtualization in finders.
  Future<void> growSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('duration stepper increases and decreases by 5 minutes',
      (tester) async {
    final repo = await repoWithSegment();
    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(durationText(tester), '30분');

    await tester.tap(find.bySemanticsLabel('길이 5분 늘리기'));
    await tester.pumpAndSettle();
    expect(durationText(tester), '35분');

    await tester.tap(find.bySemanticsLabel('길이 5분 줄이기'));
    await tester.pumpAndSettle();
    await tester.tap(find.bySemanticsLabel('길이 5분 줄이기'));
    await tester.pumpAndSettle();
    expect(durationText(tester), '25분');
  });

  testWidgets('duration preset chip jumps straight to that length',
      (tester) async {
    final repo = await repoWithSegment();
    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '60분'));
    await tester.pumpAndSettle();

    expect(durationText(tester), '60분');
  });

  testWidgets('turning off the alarm hides lead-warning and snooze fields',
      (tester) async {
    final repo = await repoWithSegment();
    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('전환 예고'), findsOneWidget);
    expect(find.text('스누즈'), findsOneWidget);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();

    expect(find.text('전환 예고'), findsNothing);
    expect(find.text('스누즈'), findsNothing);
  });

  testWidgets('adding a microstep shows it in the list', (tester) async {
    final repo = await repoWithSegment();
    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).last, '책상에 앉기');
    await tester.tap(find.byTooltip('단계 추가'));
    await tester.pumpAndSettle();

    expect(find.text('책상에 앉기'), findsOneWidget);
  });

  testWidgets('save is disabled without a title', (tester) async {
    final repo = await repoWithSegment();
    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '저장');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField).first, '약 먹기');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
  });
}
