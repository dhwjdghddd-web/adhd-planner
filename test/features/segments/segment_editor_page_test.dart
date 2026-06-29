import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/mit.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/segments/segment_editor_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        // Creating/deleting a segment reschedules alarms (SegmentsController) --
        // swap in the no-op service so that doesn't reach a platform channel.
        notificationServiceProvider.overrideWithValue(FakeNotificationService()),
      ],
      child: const MaterialApp(home: SegmentEditorPage()),
    );
  }

  testWidgets('empty state shows add-segment prompt', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.textContaining('아직 구간이 없어요'), findsOneWidget);
  });

  // SegmentFormPage's visible body area got shrunk by a bottom Padding (so
  // its 저장 button never sits under the global quick-add FAB) -- on the
  // default test surface that pushes 저장 below the fold, where
  // ListView's Sliver virtualization won't even build it. Same fix
  // routine_form_page_test.dart already uses for the same reason.
  Future<void> growSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 2400));
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
      tester.binding.setSurfaceSize(null);
    });
  }

  testWidgets('creating a segment through the form shows it in the list',
      (tester) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '구간 추가'));
    await tester.pumpAndSettle();

    // The form now has several TextFields (이름/메모/루틴 입력); 이름 is first.
    await tester.enterText(find.byType(TextField).first, '오전');
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '저장');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);

    await tester.tap(saveButton);
    await tester.pumpAndSettle();

    expect(find.text('오전'), findsOneWidget);
  });

  testWidgets('deleting a segment removes it after confirmation',
      (tester) async {
    await growSurface(tester);
    final repo = FakePlannerRepository();
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FloatingActionButton, '구간 추가'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '오후');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.text('오후'), findsOneWidget);

    await tester.tap(find.widgetWithIcon(IconButton, Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('오후'), findsNothing);
    expect(find.textContaining('아직 구간이 없어요'), findsOneWidget);
  });

  group('T7 -- 오늘의 MIT star toggle', () {
    Segment block({String id = 's1', String name = '오전'}) {
      return Segment(
        id: id,
        name: name,
        colorValue: 0xFF000000,
        iconKey: 'wb_sunny',
        startMinute: 9 * 60,
        endMinute: 10 * 60,
        order: 0,
      );
    }

    testWidgets('starts unmarked, and tapping the star marks it as today\'s MIT',
        (tester) async {
      final repo = FakePlannerRepository();
      await repo.upsertSegment(block());

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.star_border), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.star), findsNothing);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.star_border));
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.star), findsOneWidget);
      expect(find.widgetWithIcon(IconButton, Icons.star_border), findsNothing);

      final mits = await repo.watchMits().first;
      expect(mits.single.segmentId, 's1');
    });

    testWidgets('tapping an already-marked star unmarks it', (tester) async {
      final repo = FakePlannerRepository();
      await repo.upsertSegment(block());
      await repo.saveMit(Mit.today('s1'));

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.star), findsOneWidget);

      await tester.tap(find.widgetWithIcon(IconButton, Icons.star));
      await tester.pumpAndSettle();

      expect(find.widgetWithIcon(IconButton, Icons.star), findsNothing);
      expect(find.widgetWithIcon(IconButton, Icons.star_border), findsOneWidget);

      final mits = await repo.watchMits().first;
      expect(mits, isEmpty);
    });

    testWidgets('no cap -- multiple blocks can all be marked at once', (tester) async {
      final repo = FakePlannerRepository();
      await repo.upsertSegment(block(id: 's1', name: '오전'));
      await repo.upsertSegment(block(id: 's2', name: '오후'));
      await repo.upsertSegment(block(id: 's3', name: '저녁'));

      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      for (final _ in [0, 1, 2]) {
        await tester.tap(find.widgetWithIcon(IconButton, Icons.star_border).first);
        await tester.pumpAndSettle();
      }

      final mits = await repo.watchMits().first;
      expect(mits.map((m) => m.segmentId).toSet(), {'s1', 's2', 's3'});
    });
  });
}
