import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/routines/routine_editor_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
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
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      ],
      child: const MaterialApp(home: RoutineEditorPage()),
    );
  }

  testWidgets('prompts to create a segment first when none exist',
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('먼저 구간을 만들어주세요'), findsOneWidget);
  });

  testWidgets('shows empty-routine prompt when a segment exists but no routines',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_segment);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 루틴이 없어요'), findsOneWidget);
  });

  testWidgets('creating a routine through the form shows it in the list',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_segment);

    await tester.binding.setSurfaceSize(const Size(800, 2400));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '루틴 추가'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, '약 먹기');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '저장');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('약 먹기'), findsOneWidget);
  });

  testWidgets('deleting a routine removes it after confirmation',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_segment);
    await repo.upsertRoutine(const Routine(
      id: 'r1',
      segmentId: 's1',
      title: '운동',
      startMinute: 7 * 60,
    ));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('운동'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('운동'), findsNothing);
    expect(find.textContaining('아직 루틴이 없어요'), findsOneWidget);
  });
}
