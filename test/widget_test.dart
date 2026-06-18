import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/providers.dart';

import 'fakes/fake_planner_repository.dart';

void main() {
  testWidgets('App boots and shows the circular planner home', (tester) async {
    // Onboarding is gated on AppSettings.onboardingComplete (STEP 12) — mark
    // it done here so this smoke test still exercises the home screen
    // itself; onboarding's own gating is covered separately.
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));

    await tester.pumpWidget(ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
      ],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘'), findsOneWidget);
    expect(find.byTooltip('구간 관리'), findsOneWidget);
  });

  testWidgets('a fresh user sees onboarding first, then the home screen once finished',
      (tester) async {
    final repo = FakePlannerRepository();

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('구간으로 하루 나누기'), findsOneWidget);
    expect(find.text('오늘'), findsNothing);

    await tester.tap(find.text('건너뛰기'));
    await tester.pumpAndSettle();

    expect(find.text('오늘'), findsOneWidget);
  });
}
