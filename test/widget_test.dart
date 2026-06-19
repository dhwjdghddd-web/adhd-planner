import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/focus/alarm_alert_dialog.dart';
import 'package:adhd_planner/services/notification_service.dart';

import 'fakes/fake_planner_repository.dart';

void main() {
  // pendingAlarmAlert/alarmDialogOpen are module-level singletons -- reset
  // them so one test's leftover dialog state can't leak into the next.
  setUp(() {
    pendingAlarmAlert.value = null;
    alarmDialogOpen.value = false;
  });

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

  testWidgets('a pending alarm alert set before the app even starts opens once it is ready '
      '(cold start)', (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));
    await repo.upsertRoutine(Routine(id: 'r1', segmentId: 's1', title: '약 먹기', startMinute: 0));

    pendingAlarmAlert.value = const PendingAlarmAlert(
      notificationId: 1,
      routineId: 'r1',
      isTransition: false,
    );
    addTearDown(() => pendingAlarmAlert.value = null);

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(AlarmAlertDialog), findsOneWidget);
    expect(find.text('약 먹기'), findsOneWidget);
    // Consumed, not left around to re-trigger on the next rebuild.
    expect(pendingAlarmAlert.value, isNull);
  });

  testWidgets('a pending alarm alert that arrives while the app is already open also opens it',
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));
    await repo.upsertRoutine(Routine(id: 'r1', segmentId: 's1', title: '약 먹기', startMinute: 0));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오늘'), findsOneWidget);

    pendingAlarmAlert.value = const PendingAlarmAlert(
      notificationId: 1,
      routineId: 'r1',
      isTransition: false,
    );
    addTearDown(() => pendingAlarmAlert.value = null);
    await tester.pumpAndSettle();

    expect(find.byType(AlarmAlertDialog), findsOneWidget);
  });
}
