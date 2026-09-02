import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/segments/segment_form_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
import '../../fakes/fake_planner_repository.dart';

Segment _block({
  String id = 's1',
  List<String> microSteps = const [],
  bool alarmEnabled = true,
}) {
  return Segment(
    id: id,
    name: '오전',
    colorValue: 0xFF112233,
    iconKey: 'wb_sunny',
    startMinute: 6 * 60,
    endMinute: 12 * 60,
    order: 0,
    microSteps: microSteps,
    alarmEnabled: alarmEnabled,
  );
}

void main() {
  // The form is a long scrolling ListView; a tall surface keeps every section
  // (including the 루틴 list near the bottom) built and findable without
  // scrolling, the same approach settings_page_test uses.
  setUp(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.physicalSize = const Size(1080, 4000);
    view.devicePixelRatio = 1.0;
  });
  tearDown(() {
    final view = TestWidgetsFlutterBinding.ensureInitialized().platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Widget wrap(FakePlannerRepository repo, {Segment? existing}) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        // SegmentsController.upsert reschedules alarms on save -- swap in the
        // no-op service so that doesn't reach the (absent) platform channel.
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      ],
      child: MaterialApp(home: SegmentFormPage(existing: existing)),
    );
  }

  testWidgets('adding a 루틴 item and saving persists it on the block', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block());

    await tester.pumpWidget(wrap(repo, existing: _block()));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, '예: 책상에 앉기'), '물 마시기');
    await tester.tap(find.byTooltip('루틴 추가'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchSegments().first).firstWhere((s) => s.id == 's1');
    expect(saved.microSteps, contains('물 마시기'));
  });

  testWidgets('selecting 알람 끔 and saving persists alarmType = none (alarmEnabled = false)',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(alarmEnabled: true));

    await tester.pumpWidget(wrap(repo, existing: _block(alarmEnabled: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('🚫 알람 끔'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchSegments().first).firstWhere((s) => s.id == 's1');
    expect(saved.alarmType, SegmentAlarmType.none);
    expect(saved.alarmEnabled, isFalse);
  });

  testWidgets('전환 예고 and scheduleTarget are hidden once 알람 끔 is selected', (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(alarmEnabled: true));

    await tester.pumpWidget(wrap(repo, existing: _block(alarmEnabled: true)));
    await tester.pumpAndSettle();

    expect(find.text('전환 예고'), findsOneWidget);
    expect(find.text('울리는 날짜 조건'), findsOneWidget);

    await tester.tap(find.text('🚫 알람 끔'));
    await tester.pumpAndSettle();

    expect(find.text('전환 예고'), findsNothing);
    expect(find.text('울리는 날짜 조건'), findsNothing);
  });

  testWidgets('selecting 예고 없음 and saving persists leadWarning = false (leadWarningMinutes = 0)',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(alarmEnabled: true));

    await tester.pumpWidget(wrap(repo, existing: _block(alarmEnabled: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('예고 없음'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchSegments().first).firstWhere((s) => s.id == 's1');
    expect(saved.leadWarningMinutes, 0);
    expect(saved.leadWarning, isFalse);
  });

  testWidgets('selecting 근무일에만 persists scheduleTarget = workDaysOnly',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.upsertSegment(_block(alarmEnabled: true));

    await tester.pumpWidget(wrap(repo, existing: _block(alarmEnabled: true)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('🏢 근무일에만'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final saved = (await repo.watchSegments().first).firstWhere((s) => s.id == 's1');
    expect(saved.scheduleTarget, SegmentScheduleTarget.workDaysOnly);
  });

  testWidgets('an existing block prefills its items', (tester) async {
    final repo = FakePlannerRepository();
    final block = _block(microSteps: const ['이미 있는 루틴']);
    await repo.upsertSegment(block);

    await tester.pumpWidget(wrap(repo, existing: block));
    await tester.pumpAndSettle();

    expect(find.text('이미 있는 루틴'), findsOneWidget);
  });
}
