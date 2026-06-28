import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/memos/memo_inbox_page.dart';
import 'package:adhd_planner/features/segments/segment_form_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
import '../../fakes/fake_planner_repository.dart';

Memo _memo(String id, String text) {
  return Memo(
    id: id,
    text: text,
    source: MemoSource.text,
    createdAtIso: DateTime(2026, 6, 18, 10).toIso8601String(),
  );
}

Widget _wrap(FakePlannerRepository repo) {
  return ProviderScope(
    overrides: [
      plannerRepositoryProvider.overrideWithValue(repo),
      notificationServiceProvider.overrideWithValue(FakeNotificationService()),
    ],
    child: MaterialApp(home: MemoInboxPage(debugNow: DateTime(2026, 6, 18, 12))),
  );
}

Future<void> _openPromoteSheet(WidgetTester tester, String memoText) async {
  await tester.longPress(find.text(memoText));
  await tester.pumpAndSettle();
}

void main() {
  // 새 블록으로 만들기 pushes SegmentFormPage, a long scrolling ListView -- a
  // tall surface keeps its 저장 button (near the bottom) built and findable
  // without scrolling, the same approach segment_form_page_test.dart uses.
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

  testWidgets('long-pressing a memo opens the promotion sheet', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '병원 예약하기'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _openPromoteSheet(tester, '병원 예약하기');

    expect(find.text('이 메모를 어떻게 처리할까요?'), findsOneWidget);
    expect(find.text('새 블록으로 만들기'), findsOneWidget);
    expect(find.text('기존 블록에 항목으로 추가'), findsOneWidget);
  });

  testWidgets(
      '새 블록으로 만들기 opens SegmentFormPage prefilled with the memo text, and saving '
      'marks the memo reviewed', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '병원 예약하기'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _openPromoteSheet(tester, '병원 예약하기');

    await tester.tap(find.text('새 블록으로 만들기'));
    await tester.pumpAndSettle();

    expect(find.byType(SegmentFormPage), findsOneWidget);
    expect(find.widgetWithText(TextField, '병원 예약하기'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    final segments = await repo.watchSegments().first;
    expect(segments.map((s) => s.name), contains('병원 예약하기'));
    final memos = await repo.watchMemos().first;
    expect(memos.single.reviewed, true);
  });

  testWidgets(
      '기존 블록에 항목으로 추가 lets you pick a block and appends the memo text as a '
      'checklist item, marking the memo reviewed', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '우유 사기'));
    await repo.upsertSegment(Segment(
      id: 's1',
      name: '장보기',
      colorValue: 0xFF000000,
      iconKey: 'wb_sunny',
      startMinute: 9 * 60,
      endMinute: 10 * 60,
      order: 0,
      microSteps: const ['지갑 챙기기'],
    ));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _openPromoteSheet(tester, '우유 사기');

    await tester.tap(find.text('기존 블록에 항목으로 추가'));
    await tester.pumpAndSettle();

    expect(find.text('어느 블록에 추가할까요?'), findsOneWidget);
    await tester.tap(find.text('장보기'));
    await tester.pumpAndSettle();

    final segments = await repo.watchSegments().first;
    expect(segments.single.microSteps, ['지갑 챙기기', '우유 사기']);
    final memos = await repo.watchMemos().first;
    expect(memos.single.reviewed, true);
  });

  testWidgets('기존 블록에 항목으로 추가 with no blocks at all shows a snackbar instead of a picker',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '우유 사기'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();
    await _openPromoteSheet(tester, '우유 사기');

    await tester.tap(find.text('기존 블록에 항목으로 추가'));
    await tester.pumpAndSettle();

    expect(find.text('추가할 블록이 없어요. 먼저 블록을 만들어주세요.'), findsOneWidget);
    final memos = await repo.watchMemos().first;
    expect(memos.single.reviewed, false);
  });
}
