import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/data/today.dart';
import 'package:adhd_planner/features/memos/memo_inbox_page.dart';

import '../../fakes/fake_planner_repository.dart';

final _now = DateTime(2026, 6, 29, 12);

Memo _oldMemo(String id, String text) {
  return Memo(
    id: id,
    text: text,
    source: MemoSource.text,
    createdAtIso: _now.subtract(const Duration(days: 10)).toIso8601String(),
  );
}

Memo _freshMemo(String id, String text) {
  return Memo(
    id: id,
    text: text,
    source: MemoSource.text,
    createdAtIso: _now.subtract(const Duration(hours: 1)).toIso8601String(),
  );
}

Widget _wrap(FakePlannerRepository repo) {
  return ProviderScope(
    overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(home: MemoInboxPage(debugNow: _now)),
  );
}

void main() {
  testWidgets('shows the nudge card for an old unreviewed memo', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_oldMemo('m1', '오래된 메모'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('이 메모, 아직이에요'), findsOneWidget);
    expect(find.text('오래된 메모'), findsNWidgets(2)); // nudge card + list row
  });

  testWidgets('does not show the nudge card when every memo is fresh', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_freshMemo('m1', '방금 적은 메모'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('이 메모, 아직이에요'), findsNothing);
  });

  testWidgets('does not show the nudge card once already dismissed today', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_oldMemo('m1', '오래된 메모'));
    await repo.saveSettings(AppSettings.defaults().copyWith(lastMemoNudgeDate: dayKeyFor(_now)));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    expect(find.text('이 메모, 아직이에요'), findsNothing);
  });

  testWidgets('나중에 dismisses the card and persists today as nudged', (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_oldMemo('m1', '오래된 메모'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, '나중에'));
    await tester.pumpAndSettle();

    expect(find.text('이 메모, 아직이에요'), findsNothing);
    final settings = await repo.watchSettings().first;
    expect(settings.lastMemoNudgeDate, dayKeyFor(_now));
  });

  testWidgets('지금 처리 dismisses the card and opens the promotion sheet for that memo',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.addMemo(_oldMemo('m1', '오래된 메모'));

    await tester.pumpWidget(_wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '지금 처리'));
    await tester.pumpAndSettle();

    expect(find.text('이 메모를 어떻게 처리할까요?'), findsOneWidget);
    expect(find.text('새 블록으로 만들기'), findsOneWidget);
    final settings = await repo.watchSettings().first;
    expect(settings.lastMemoNudgeDate, dayKeyFor(_now));
  });
}
