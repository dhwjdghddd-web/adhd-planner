import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';
import 'package:adhd_planner/features/memos/quick_add_sheet.dart';

import '../../fakes/fake_planner_repository.dart';

/// MultiFabRow와 Scaffold FAB 형태로 구현된 메모 버튼의 기능을 테스트합니다.
Widget _testApp(FakePlannerRepository repo) {
  return ProviderScope(
    overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: const Scaffold(
        body: Center(child: Text('home')),
        floatingActionButton: MultiFabRow(
          left: GlobalQuickAddButton(),
        ),
        floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      ),
    ),
  );
}

void main() {
  setUp(() {
    quickAddSheetOpen.value = false;
  });

  testWidgets('tapping the global FAB opens the quick-add sheet',
      (tester) async {
    await tester.pumpWidget(_testApp(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();

    expect(find.text('빠른 메모'), findsOneWidget);
  });

  testWidgets('the global FAB hides itself while the sheet is open', (tester) async {
    await tester.pumpWidget(_testApp(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_note), findsOneWidget);

    await tester.tap(find.byIcon(Icons.edit_note));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_note), findsNothing);
  });
}
