import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/data/today.dart';
import 'package:adhd_planner/features/focus/alarm_alert_dialog.dart';
import 'package:adhd_planner/services/notification_service.dart';

import 'fakes/fake_planner_repository.dart';

Segment _block({
  String id = 's1',
  String name = '약 먹기',
  int startMinute = 0,
  List<String> microSteps = const [],
}) {
  return Segment(
    id: id,
    name: name,
    colorValue: 0xFF000000,
    iconKey: 'wb_sunny',
    startMinute: startMinute,
    endMinute: startMinute + 60,
    order: 0,
    microSteps: microSteps,
  );
}

void main() {
  // pendingAlarmAlert/alarmDialogOpen are module-level singletons -- reset them
  // so one test's leftover dialog state can't leak into the next.
  setUp(() {
    pendingAlarmAlert.value = null;
    alarmDialogOpen.value = false;
  });

  testWidgets('App boots and shows the circular planner home', (tester) async {
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
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기'));

    pendingAlarmAlert.value = const PendingAlarmAlert(notificationId: 1, segmentId: 's1');
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
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기'));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();
    expect(find.text('오늘'), findsOneWidget);

    pendingAlarmAlert.value = const PendingAlarmAlert(notificationId: 1, segmentId: 's1');
    addTearDown(() => pendingAlarmAlert.value = null);
    await tester.pumpAndSettle();

    expect(find.byType(AlarmAlertDialog), findsOneWidget);
  });

  testWidgets('_AchievementRecorder banks settled past days but never today', (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));
    // A block with two items.
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b']));
    // Both today and yesterday cleared every item (100% >= the 50% bar).
    final now = DateTime.now();
    final yesterday = now.subtract(const Duration(days: 1));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1], at: yesterday));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    final banked = (await repo.watchAchievedDays().first).map((d) => d.dateKey).toSet();
    // Yesterday is settled history and gets banked permanently; today is still
    // live (could fall back below the bar before midnight) so it must not be.
    expect(banked, contains(dayKeyFor(yesterday)));
    expect(banked, isNot(contains(dayKeyFor(now))));
  });
}
