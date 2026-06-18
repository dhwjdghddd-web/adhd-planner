import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/settings/settings_page.dart';

import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  // The settings list is taller than the default test surface, which would
  // leave the account row below the fold un-inflated. Growing the surface
  // (same approach as routine_form_page_test.dart) avoids needing to scroll.
  Future<void> growSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    tester.view.physicalSize = const Size(800, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('renders permission rows and theme/motion controls without crashing',
      (tester) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('알림'), findsOneWidget);
    expect(find.text('정확한 알람'), findsOneWidget);
    expect(find.text('마이크'), findsOneWidget);
    expect(find.text('동작 줄이기'), findsOneWidget);
    // No platform channel under flutter test, so status degrades gracefully.
    expect(find.text('확인 중...'), findsWidgets);
  });

  testWidgets('selecting a theme segment persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('다크'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.themeMode, AppThemeMode.dark);
  });

  testWidgets('toggling reduce motion persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, '동작 줄이기'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.reduceMotion, true);
  });

  testWidgets('the account upgrade button shows a coming-soon snackbar', (tester) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('업그레이드'));
    await tester.pumpAndSettle();

    expect(find.textContaining('추후 지원될 예정'), findsOneWidget);
  });
}
