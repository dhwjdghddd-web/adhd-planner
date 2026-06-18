import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';
import 'package:adhd_planner/features/memos/quick_add_sheet.dart';

import '../../fakes/fake_planner_repository.dart';

/// Mirrors app.dart's MaterialApp.builder structure: the global FAB sits
/// outside the Navigator the builder wraps, exactly like in the real app.
/// This is what regression-tests the navigatorKey-based workaround for
/// reaching back into the Navigator from there.
Widget _testApp(FakePlannerRepository repo) {
  return ProviderScope(
    overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
    child: MaterialApp(
      navigatorKey: appNavigatorKey,
      home: const Scaffold(body: Center(child: Text('home'))),
      builder: (context, child) => Stack(
        children: [
          ?child,
          const SafeArea(
            child: Align(
              alignment: Alignment.bottomLeft,
              child: Padding(padding: EdgeInsets.all(16), child: GlobalQuickAddButton()),
            ),
          ),
        ],
      ),
    ),
  );
}

void main() {
  // quickAddSheetOpen/fabSuppressionCount are module-level singletons (they
  // have to be, so the FAB outside the Navigator can react to them) — reset
  // them so one test's leftover state can't leak into the next.
  setUp(() {
    quickAddSheetOpen.value = false;
    fabSuppressionCount.value = 0;
  });

  testWidgets('tapping the global FAB opens the quick-add sheet from outside the Navigator',
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

  testWidgets(
      'a SuppressGlobalFab-wrapped page (onboarding, Focus) hides the FAB while pushed, '
      'and it reappears after popping back',
      (tester) async {
    await tester.pumpWidget(_testApp(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_note), findsOneWidget);

    appNavigatorKey.currentState!.push(MaterialPageRoute<void>(
      builder: (_) => const SuppressGlobalFab(
        child: Scaffold(body: Center(child: Text('page with its own full-width bottom button'))),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_note), findsNothing);

    appNavigatorKey.currentState!.pop();
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.edit_note), findsOneWidget);
  });
}
