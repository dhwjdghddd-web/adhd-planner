import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/app.dart';
import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/alarm_skip.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/mit.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/data/repositories/planner_repository.dart';
import 'package:adhd_planner/data/today.dart';
import 'package:adhd_planner/features/focus/alarm_screen.dart';
import 'package:adhd_planner/features/focus/focus_page.dart';
import 'package:adhd_planner/features/memos/quick_add_button.dart';
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

/// Wraps a [PlannerRepository], delaying the *first* emission of
/// segments/completions/microStepProgress/achievedDays by a beat -- settings
/// (and everything else) passes straight through. Reproduces the asymmetric
/// catch-up speed Riverpod's StreamProviders showed on a real device after
/// plannerRepositoryProvider switched accounts: settingsProvider's first read
/// resolved near-instantly, while these needed an actual round trip, leaving
/// a real window where the new account is active but its checklist data
/// hasn't arrived yet.
class _DelayedDataRepository implements PlannerRepository {
  _DelayedDataRepository(this._inner);
  final PlannerRepository _inner;

  Stream<T> _delayed<T>(Stream<T> source) => source.asyncMap((v) async {
        await Future.delayed(const Duration(milliseconds: 10));
        return v;
      });

  @override
  Stream<List<Segment>> watchSegments() => _delayed(_inner.watchSegments());
  @override
  Stream<List<Completion>> watchCompletions() => _delayed(_inner.watchCompletions());
  @override
  Stream<List<MicroStepProgress>> watchMicroStepProgress() =>
      _delayed(_inner.watchMicroStepProgress());
  @override
  Stream<List<AchievedDay>> watchAchievedDays() => _delayed(_inner.watchAchievedDays());

  @override
  Stream<List<Memo>> watchMemos() => _inner.watchMemos();
  @override
  Stream<List<AlarmSkip>> watchAlarmSkips() => _inner.watchAlarmSkips();
  @override
  Stream<List<Mit>> watchMits() => _inner.watchMits();
  @override
  Stream<AppSettings> watchSettings() => _inner.watchSettings();

  @override
  Future<void> upsertSegment(Segment s) => _inner.upsertSegment(s);
  @override
  Future<void> deleteSegment(String id) => _inner.deleteSegment(id);
  @override
  Future<void> addMemo(Memo m) => _inner.addMemo(m);
  @override
  Future<void> updateMemo(Memo m) => _inner.updateMemo(m);
  @override
  Future<void> deleteMemo(String id) => _inner.deleteMemo(id);
  @override
  Future<void> setCompletion(Completion c) => _inner.setCompletion(c);
  @override
  Future<void> removeCompletion(String dateKey, String segmentId) =>
      _inner.removeCompletion(dateKey, segmentId);
  @override
  Future<void> saveMicroStepProgress(MicroStepProgress p) => _inner.saveMicroStepProgress(p);
  @override
  Future<void> saveAchievedDay(AchievedDay d) => _inner.saveAchievedDay(d);
  @override
  Future<void> saveAlarmSkip(AlarmSkip s) => _inner.saveAlarmSkip(s);
  @override
  Future<void> saveMit(Mit m) => _inner.saveMit(m);
  @override
  Future<void> removeMit(String dateKey, String segmentId) =>
      _inner.removeMit(dateKey, segmentId);
  @override
  Future<void> saveSettings(AppSettings s) => _inner.saveSettings(s);
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

  testWidgets(
      'the completion celebration is suppressed during the in-between window '
      "where segments/completions/progress/achievedDays haven't caught up to "
      'a brand new account yet, even though plannerRepositoryProvider and '
      'settings already have (regression: on a real device, '
      'signInAnonymously took over a second -- long enough for one rebuild '
      "to see the logged-out account's stale \"fully done today\" "
      'segments/completions/progress alongside the new account\'s '
      'already-reset lastCelebratedDate=null, which looked exactly like '
      '"today not yet celebrated" and fired the celebration -- persisting '
      'lastCelebratedDate into the *new*, unrelated account)', (tester) async {
    final repoHolder = StateProvider<PlannerRepository?>((ref) => null);

    final oldRepo = FakePlannerRepository();
    await oldRepo.saveSettings(
      AppSettings.defaults().copyWith(onboardingComplete: true, lastCelebratedDate: dayKeyFor()),
    );
    await oldRepo.upsertSegment(_block(id: 's1', name: '약 먹기', microSteps: const ['a', 'b']));
    await oldRepo.saveMicroStepProgress(MicroStepProgress.today('s1', const [0, 1]));

    final newRepo = _DelayedDataRepository(FakePlannerRepository());

    final container = ProviderContainer(overrides: [
      plannerRepositoryProvider.overrideWith((ref) => ref.watch(repoHolder)),
    ]);
    addTearDown(container.dispose);
    container.read(repoHolder.notifier).state = oldRepo;

    await tester.pumpWidget(UncontrolledProviderScope(container: container, child: const App()));
    await tester.pumpAndSettle();

    // Already celebrated today on the old account -- nothing to show yet.
    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsNothing);

    // The account switch: plannerRepositoryProvider flips straight to the new
    // account. settingsProvider's near-instant first read lands within the
    // first tick or two, but newRepo's artificially delayed
    // segments/completions/progress/achievedDays streams stay mid-flight for
    // ~10ms -- stepping in 1ms ticks (rather than one bare pump(), which
    // settles past the whole window in a single jump) is what actually
    // catches the transient mismatch in between.
    container.read(repoHolder.notifier).state = newRepo;
    for (var i = 0; i < 15; i++) {
      await tester.pump(const Duration(milliseconds: 1));
      // Must never fire during the transition -- this is exactly the
      // transient window the fix guards against (isLoading still true on the
      // delayed providers while settings has already reset).
      expect(find.text('오늘 할 일을 다 끝냈어요!'), findsNothing);
    }

    // Let the delayed streams finally emit -- the new account settles as the
    // empty account it really is.
    await tester.pumpAndSettle();
    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsNothing);
  });

  testWidgets(
      'checking the last item closes Focus even when the separate completion '
      "celebration races it onto the same navigator (regression: Focus's own "
      'delayed self-close used to call a blind Navigator.pop(), which by then '
      'removed whatever was *currently on top* -- the celebration dialog, '
      'dismissing it after only a flash -- instead of closing Focus as '
      'intended)', (tester) async {
    final repo = FakePlannerRepository();
    // reduceMotion: true keeps Focus's own self-close delay short (250ms
    // instead of 900ms-plus-confetti) and avoids the celebration's confetti
    // animation, so pumpAndSettle reaches a true steady state.
    await repo.saveSettings(
      const AppSettings.defaults().copyWith(onboardingComplete: true, reduceMotion: true),
    );
    final block = _block(id: 's1', name: '약 먹기', microSteps: const ['물 마시기']);
    await repo.upsertSegment(block);

    await tester.pumpWidget(ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const App(),
    ));
    await tester.pumpAndSettle();

    // Pushed over the home route (PlannerPage) -- the same shape as the real
    // dial-tap entry, so there's something underneath for Focus's fix to
    // safely target without ever emptying the navigator.
    appNavigatorKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => FocusPage.forBlock(block)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(CheckboxListTile, '물 마시기'));
    await tester.pumpAndSettle();

    // Focus closed itself correctly (not left stuck open because its delayed
    // pop hit the wrong route)...
    expect(find.byType(FocusPage), findsNothing);
    // ...and the celebration that raced it is still showing, undisturbed
    // (not yanked away the instant it appeared).
    expect(find.text('오늘 할 일을 다 끝냈어요!'), findsOneWidget);
  });
}
