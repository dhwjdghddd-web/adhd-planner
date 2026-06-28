import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/data/today.dart';
import 'package:adhd_planner/features/focus/alarm_screen.dart';
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
  // pendingAlarmAlert/alarmScreenOpen are module-level singletons -- reset them
  // so one test's leftover alarm state can't leak into the next.
  setUp(() {
    pendingAlarmAlert.value = null;
    alarmScreenOpen.value = false;
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

    expect(find.byType(AlarmScreen), findsOneWidget);
    // Scoped to the alarm screen: the block name also now appears in the home
    // screen's today-timeline strip behind it.
    expect(
      find.descendant(of: find.byType(AlarmScreen), matching: find.text('약 먹기')),
      findsOneWidget,
    );
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

    expect(find.byType(AlarmScreen), findsOneWidget);
  });

  testWidgets('_AchievementRecorder banks settled past days but never today', (tester) async {
    final repo = FakePlannerRepository();
    // Mark today already celebrated so the full-screen completion celebration
    // (today is set up 100% complete below) doesn't pop and keep the confetti
    // animation pumping forever -- this test is about achievement banking.
    await repo.saveSettings(
      AppSettings.defaults().copyWith(onboardingComplete: true, lastCelebratedDate: dayKeyFor()),
    );
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

  testWidgets(
      '_CompletionCelebrator shows the lighter halfway snackbar on first crossing 50%, '
      'not the full-screen 100% celebration', (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));
    // 2 of 4 items checked today -- exactly the 50% bar, not 100%.
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b', 'c', 'd']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘 절반을 해냈어요 — 충분히 잘하고 있어요'), findsOneWidget);
    // The full-screen celebration is for 100% only -- must not also appear.
    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsNothing);

    final saved = await repo.watchSettings().first;
    expect(saved.lastPartialCelebratedDate, dayKeyFor());
  });

  testWidgets(
      "_CompletionCelebrator doesn't re-show the halfway snackbar once already marked today",
      (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(
      AppSettings.defaults()
          .copyWith(onboardingComplete: true, lastPartialCelebratedDate: dayKeyFor()),
    );
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b', 'c', 'd']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘 절반을 해냈어요 — 충분히 잘하고 있어요'), findsNothing);
  });

  testWidgets(
      'the halfway snackbar never fires on a day with no checklist items at all '
      '(whole-block fallback achievement is not a "halfway")', (tester) async {
    final repo = FakePlannerRepository();
    await repo.saveSettings(const AppSettings.defaults().copyWith(onboardingComplete: true));
    // A block with NO checklist items, completed for the whole day -- this makes
    // DailyAchievement.isAchieved true via the whole-block fallback (total == 0),
    // but there's no real "halfway" to celebrate.
    await repo.upsertSegment(_block(id: 's1', name: '퇴근'));
    await repo.setCompletion(Completion.now('s1'));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘 절반을 해냈어요 — 충분히 잘하고 있어요'), findsNothing);
  });

  testWidgets(
      'the halfway snackbar is suppressed once today is already fully celebrated '
      '(un-checking back to 50% must not downgrade to a halfway nudge)', (tester) async {
    final repo = FakePlannerRepository();
    // Today already got its full 100% celebration; now sitting at 50% again
    // (e.g. pressed 모두 완료 then un-checked an item). The lighter snackbar
    // must not fire after the full one -- guarded by !alreadyToday.
    await repo.saveSettings(
      AppSettings.defaults().copyWith(onboardingComplete: true, lastCelebratedDate: dayKeyFor()),
    );
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b', 'c', 'd']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘 절반을 해냈어요 — 충분히 잘하고 있어요'), findsNothing);
  });

  testWidgets(
      'a 100% completion on a milestone-length streak (e.g. day 3) shows the streak '
      'line in the full-screen celebration', (tester) async {
    final repo = FakePlannerRepository();
    // reduceMotion: true -- the celebration's confetti animation would
    // otherwise keep pumpAndSettle from ever settling.
    await repo.saveSettings(
      const AppSettings.defaults().copyWith(onboardingComplete: true, reduceMotion: true),
    );
    final now = DateTime.now();
    // Two consecutive banked days right before today, so today completing
    // makes this the 3rd consecutive day -- a celebrationMilestones entry.
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 1))));
    await repo.saveAchievedDay(AchievedDay.forDay(now.subtract(const Duration(days: 2))));
    await repo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b']));
    await repo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsOneWidget);
    expect(find.text('3일 연속, 정말 멋져요!'), findsOneWidget);
  });
}
