import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/memos/memo_inbox_page.dart';

import '../../fakes/fake_planner_repository.dart';

Memo _memo(String id, String text, {bool reviewed = false, MemoSource source = MemoSource.text}) {
  return Memo(
    id: id,
    text: text,
    source: source,
    createdAtIso: DateTime(2026, 6, 18, 10, id.hashCode.abs() % 59).toIso8601String(),
    reviewed: reviewed,
  );
}

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      // Pinned to the same day every fixture memo below is created on, so
      // none of them are "old enough" to trigger the resurfacing nudge card
      // (see memo_resurfacing_test.dart / memo_inbox_nudge_test.dart for
      // that) -- these tests are about the plain list/search/swipe behaviour.
      child: MaterialApp(home: MemoInboxPage(debugNow: DateTime(2026, 6, 18, 12))),
    );
  }

  testWidgets('shows the empty state when there are no unreviewed memos', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('확인하지 않은 메모가 없어요'), findsOneWidget);
  });

  testWidgets('shows unreviewed memos by default and hides reviewed ones', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '안 읽은 메모'));
    await repo.addMemo(_memo('m2', '읽은 메모', reviewed: true));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('안 읽은 메모'), findsOneWidget);
    expect(find.text('읽은 메모'), findsNothing);

    await tester.tap(find.text('확인한 메모도 보기'));
    await tester.pumpAndSettle();

    expect(find.text('읽은 메모'), findsOneWidget);
  });

  testWidgets('checking a memo marks it reviewed and removes it from the default view',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '체크할 메모'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    expect(find.text('체크할 메모'), findsNothing);
  });

  testWidgets('search filters memos by substring', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '우유 사기'));
    await repo.addMemo(_memo('m2', '병원 예약하기'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '우유');
    await tester.pumpAndSettle();

    expect(find.text('우유 사기'), findsOneWidget);
    expect(find.text('병원 예약하기'), findsNothing);
  });

  testWidgets('reviewed memos show a strikethrough', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '읽은 메모', reviewed: true));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인한 메모도 보기'));
    await tester.pumpAndSettle();

    final text = tester.widget<Text>(find.text('읽은 메모'));
    expect(text.style?.decoration, TextDecoration.lineThrough);
  });

  testWidgets('unreviewed memos are sorted above reviewed ones', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '읽은 메모', reviewed: true));
    await repo.addMemo(_memo('m2', '안 읽은 메모'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();
    await tester.tap(find.text('확인한 메모도 보기'));
    await tester.pumpAndSettle();

    final unreviewedY = tester.getTopLeft(find.text('안 읽은 메모')).dy;
    final reviewedY = tester.getTopLeft(find.text('읽은 메모')).dy;
    expect(unreviewedY, lessThan(reviewedY));
  });

  testWidgets(
      'the visible list area is shrunk (not just padded inside) so the '
      'last tile clears the global FAB even before scrolling', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '메모'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    final padding = tester.widget<Padding>(
      find.ancestor(of: find.byType(ListView), matching: find.byType(Padding)).first,
    );
    expect((padding.padding as EdgeInsets).bottom, greaterThanOrEqualTo(56));
  });

  testWidgets('swiping a memo away and confirming deletes it', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_memo('m1', '지울 메모'));

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.drag(find.text('지울 메모'), const Offset(-500, 0));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '삭제'));
    await tester.pumpAndSettle();

    expect(find.text('지울 메모'), findsNothing);
  });
}
