import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/memos/quick_add_sheet.dart';

import '../../fakes/fake_planner_repository.dart';

/// Mimics Firestore offline behaviour: the write Future never resolves
/// (no server to acknowledge it), even though the local cache/stream
/// updates immediately, same as the real repository.
class _NeverAcksWritesRepository extends FakePlannerRepository {
  @override
  Future<void> addMemo(Memo m) {
    super.addMemo(m);
    return Completer<void>().future;
  }
}

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () => showQuickAddSheet(context),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('save is disabled until text is entered', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final saveButton = find.widgetWithText(FilledButton, '저장');
    expect(tester.widget<FilledButton>(saveButton).onPressed, isNull);

    await tester.enterText(find.byType(TextField), '잡생각 하나');
    await tester.pumpAndSettle();

    expect(tester.widget<FilledButton>(saveButton).onPressed, isNotNull);
  });

  testWidgets('saving adds a text memo and closes the sheet', (tester) async {
    final repo = FakePlannerRepository();
    final memos = <List<Memo>>[];
    repo.watchMemos().listen(memos.add);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '잡생각 하나');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(memos.last, hasLength(1));
    expect(memos.last.single.text, '잡생각 하나');
    expect(memos.last.single.source, MemoSource.text);
  });

  testWidgets('closes immediately even if the write never acknowledges (offline)',
      (tester) async {
    final repo = _NeverAcksWritesRepository();
    final memos = <List<Memo>>[];
    repo.watchMemos().listen(memos.add);

    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField), '오프라인 메모');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    // pumpAndSettle only waits out the sheet's own close animation, not the
    // dangling write Future — if _save() ever went back to awaiting that
    // Future before popping, this would time out instead of settling.
    await tester.pumpAndSettle();

    expect(find.byType(TextField), findsNothing);
    expect(memos.last.single.text, '오프라인 메모');
  });

  testWidgets('quickAddSheetOpen flips back to false once the sheet closes', (tester) async {
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(quickAddSheetOpen.value, true);

    await tester.enterText(find.byType(TextField), '잡생각');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, '저장'));
    await tester.pumpAndSettle();

    expect(quickAddSheetOpen.value, false);
  });
}
