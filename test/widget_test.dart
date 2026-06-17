import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/providers.dart';

import 'fakes/fake_planner_repository.dart';

void main() {
  testWidgets('App boots and shows the segments editor', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(FakePlannerRepository()),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('하루 구간'), findsOneWidget);
    expect(find.text('구간 추가'), findsWidgets);
  });
}
