import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/segments/brain_dump_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        // upsertAll reschedules alarms on save -- swap in the no-op service
        // so that doesn't reach the (absent) platform channel.
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      ],
      child: const MaterialApp(home: BrainDumpPage()),
    );
  }

  Future<void> addItem(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.tap(find.widgetWithText(FilledButton, '추가'));
    await tester.pump();
  }

  testWidgets("시각 자동 배치 is disabled with no items, enabled once one's added",
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    final disabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '시각 자동 배치'));
    expect(disabled.onPressed, isNull);

    await addItem(tester, '병원 예약');

    final enabled =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, '시각 자동 배치'));
    expect(enabled.onPressed, isNotNull);
  });

  testWidgets('added items show in the list and can be removed', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await addItem(tester, '병원 예약');
    await addItem(tester, '청소');
    expect(find.text('병원 예약'), findsOneWidget);
    expect(find.text('청소'), findsOneWidget);

    // Remove via the row's own delete button.
    final removeButton = find.descendant(
      of: find.ancestor(of: find.text('병원 예약'), matching: find.byType(ListTile)),
      matching: find.byIcon(Icons.close),
    );
    await tester.tap(removeButton);
    await tester.pumpAndSettle();

    expect(find.text('병원 예약'), findsNothing);
    expect(find.text('청소'), findsOneWidget);
  });

  testWidgets(
      'suggesting times previews each item with a time range, and 추가하기 '
      'creates all of them as real blocks', (tester) async {
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await addItem(tester, '병원 예약');
    await addItem(tester, '청소');

    await tester.tap(find.widgetWithText(FilledButton, '시각 자동 배치'));
    await tester.pumpAndSettle();

    // Preview phase: both items still listed, each with a time-range subtitle.
    expect(find.text('병원 예약'), findsOneWidget);
    expect(find.text('청소'), findsOneWidget);
    expect(find.textContaining('–'), findsNWidgets(2));

    await tester.tap(find.widgetWithText(FilledButton, '추가하기'));
    await tester.pumpAndSettle();

    final saved = await repo.watchSegments().first;
    expect(saved.map((s) => s.name).toSet(), {'병원 예약', '청소'});
  });

  testWidgets("목록으로 returns to the list phase without losing the items",
      (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await addItem(tester, '병원 예약');
    await tester.tap(find.widgetWithText(FilledButton, '시각 자동 배치'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(OutlinedButton, '목록으로'));
    await tester.pumpAndSettle();

    // Back in the list phase: the text field (only present there) is back,
    // and the item survived the round trip.
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('병원 예약'), findsOneWidget);
  });
}
