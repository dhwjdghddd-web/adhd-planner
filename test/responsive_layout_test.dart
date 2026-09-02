import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/checkin/checkin_page.dart';
import 'package:adhd_planner/features/checklist/today_checklist_page.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/memos/memo_inbox_page.dart';
import 'package:adhd_planner/features/memos/quick_add_sheet.dart';
import 'package:adhd_planner/features/onboarding/onboarding_page.dart';
import 'package:adhd_planner/features/planner/planner_page.dart';
import 'package:adhd_planner/features/segments/brain_dump_page.dart';
import 'package:adhd_planner/features/segments/segment_editor_page.dart';
import 'package:adhd_planner/features/segments/segment_form_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes/fake_planner_repository.dart';

void main() {
  late FakePlannerRepository repository;

  setUp(() async {
    repository = FakePlannerRepository();
    await repository.upsertSegment(
      const Segment(
        id: 'seg-1',
        name: '오전 루틴',
        colorValue: 0xFF4A90E2,
        iconKey: 'wb_sunny',
        startMinute: 9 * 60,
        endMinute: 12 * 60,
        order: 0,
        microSteps: ['물 마시기', '비타민 챙기기', '계획 점검'],
      ),
    );
    await repository.upsertSegment(
      const Segment(
        id: 'seg-2',
        name: '오후 집중 업무',
        colorValue: 0xFF50E3C2,
        iconKey: 'work',
        startMinute: 13 * 60,
        endMinute: 18 * 60,
        order: 1,
        microSteps: ['이메일 확인', '보고서 작성'],
      ),
    );
    await repository.upsertSegment(
      const Segment(
        id: 'seg-3',
        name: '저녁 휴식 및 수면',
        colorValue: 0xFFB8E986,
        iconKey: 'bedtime',
        startMinute: 22 * 60,
        endMinute: 24 * 60,
        order: 2,
      ),
    );
  });

  Widget createTestWidget(
    Widget child, {
    required Size screenSize,
    double textScale = 1.0,
  }) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repository),
      ],
      child: MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(
            size: screenSize,
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24, bottom: 24),
          ),
          child: child,
        ),
      ),
    );
  }

  group('Galaxy Fold 8 and multi-device responsive layout tests', () {
    // 1. Galaxy Z Fold 8 Unfolded Main Screen (Wide square-ish: ~884 x 768 dp)
    testWidgets('PlannerPage renders without overflow on Galaxy Fold 8 unfolded screen', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const PlannerPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlannerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 2. Galaxy Z Fold 8 Unfolded with 1.5x font scale
    testWidgets('PlannerPage renders without overflow on Fold 8 with 1.5x font scale', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const PlannerPage(),
          screenSize: fold8Unfolded,
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlannerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 3. Galaxy Z Fold 8 Folded Cover Screen (Narrow and tall: ~340 x 884 dp)
    testWidgets('PlannerPage renders without overflow on Fold 8 folded cover screen', (tester) async {
      final fold8Cover = const Size(340, 884);
      tester.view.physicalSize = fold8Cover;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const PlannerPage(),
          screenSize: fold8Cover,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlannerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 4. Split-screen / Pop-up view / Short height (e.g. 400 x 580 dp)
    testWidgets('PlannerPage renders without overflow in short split-screen mode', (tester) async {
      final splitScreen = const Size(400, 580);
      tester.view.physicalSize = splitScreen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const PlannerPage(),
          screenSize: splitScreen,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlannerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 5. Standard smartphone (390 x 844 dp) with 2.0x max font scale
    testWidgets('PlannerPage renders without overflow with extreme 2.0x font scale', (tester) async {
      final phone = const Size(390, 844);
      tester.view.physicalSize = phone;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const PlannerPage(),
          screenSize: phone,
          textScale: 2.0,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(PlannerPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 6. FocusPage responsiveness across screens
    testWidgets('FocusPage renders without overflow on Fold 8 unfolded', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const FocusPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(FocusPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 7. OnboardingPage responsiveness on Fold 8
    testWidgets('OnboardingPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const OnboardingPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OnboardingPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 8. QuickAddSheet in constrained bottom sheet
    testWidgets('QuickAddSheet renders safely without overflow', (tester) async {
      final smallScreen = const Size(360, 600);
      tester.view.physicalSize = smallScreen;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const Scaffold(body: QuickAddSheet()),
          screenSize: smallScreen,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(QuickAddSheet), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 9. CheckinPage on Fold 8 with 1.5x font scale
    testWidgets('CheckinPage renders without overflow on Fold 8 with 1.5x font scale', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const CheckinPage(),
          screenSize: fold8Unfolded,
          textScale: 1.5,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(CheckinPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 10. SegmentEditorPage on Fold 8
    testWidgets('SegmentEditorPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const SegmentEditorPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentEditorPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 11. SegmentFormPage on Fold 8
    testWidgets('SegmentFormPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const SegmentFormPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(SegmentFormPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 12. MemoInboxPage on Fold 8
    testWidgets('MemoInboxPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const MemoInboxPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MemoInboxPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 13. BrainDumpPage on Fold 8
    testWidgets('BrainDumpPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const BrainDumpPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(BrainDumpPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    // 14. TodayChecklistPage on Fold 8
    testWidgets('TodayChecklistPage renders without overflow on Fold 8', (tester) async {
      final fold8Unfolded = const Size(884, 768);
      tester.view.physicalSize = fold8Unfolded;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        createTestWidget(
          const TodayChecklistPage(),
          screenSize: fold8Unfolded,
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(TodayChecklistPage), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
