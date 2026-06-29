import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/features/focus/focus_timer_controller.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';

void main() {
  // Real DateTime.now() can't be faked by flutter_test's FakeAsync zone
  // (only Timer/Future.delayed can) -- fakeNow is the controller's injected
  // clock instead, advanced by hand in lockstep with each tester.pump() below
  // so the controller's Timer.periodic ticks see exactly the time the test
  // means for it to.
  //
  // Any test that ends with the timer still actively running calls
  // controller().cancel() as its own last line (not just in tearDown) --
  // flutter_test's "no pending timers" invariant check runs as part of
  // finishing the testWidgets callback itself, before package:test's
  // tearDown() hooks get a chance to run, so cleanup has to happen inside
  // the test body to land in time.
  late DateTime fakeNow;
  late FakeNotificationService notificationService;
  late ProviderContainer container;

  setUp(() {
    fakeNow = DateTime(2026, 1, 1, 9, 0);
    notificationService = FakeNotificationService();
    container = ProviderContainer(overrides: [
      notificationServiceProvider.overrideWithValue(notificationService),
      focusTimerControllerProvider.overrideWith(
        (ref) => FocusTimerController(ref, now: () => fakeNow),
      ),
    ]);
  });

  tearDown(() => container.dispose());

  FocusTimerController controller() => container.read(focusTimerControllerProvider.notifier);
  FocusTimerState state() => container.read(focusTimerControllerProvider);

  Future<void> advance(WidgetTester tester, Duration by) async {
    fakeNow = fakeNow.add(by);
    await tester.pump(by);
  }

  testWidgets('idle by default', (tester) async {
    expect(state().isIdle, true);
    expect(state().isRunning, false);
    expect(state().isPaused, false);
  });

  testWidgets('startPomodoro begins a 25분 focus leg and schedules its end notification',
      (tester) async {
    controller().startPomodoro();

    final s = state();
    expect(s.isRunning, true);
    expect(s.phase, FocusTimerPhase.focus);
    expect(s.totalDuration, FocusTimerController.pomodoroFocus);
    expect(s.remainingAt(fakeNow), FocusTimerController.pomodoroFocus);
    expect(notificationService.timerEndCalls, hasLength(1));
    controller().cancel();
  });

  testWidgets('a Pomodoro focus leg auto-chains into a 5분 break on completion',
      (tester) async {
    controller().startPomodoro();

    await advance(tester, FocusTimerController.pomodoroFocus - const Duration(seconds: 1));
    expect(state().phase, FocusTimerPhase.focus, reason: 'one second early -- not done yet');

    await advance(tester, const Duration(seconds: 1));
    final s = state();
    expect(s.phase, FocusTimerPhase.breakTime);
    expect(s.isRunning, true);
    expect(s.totalDuration, FocusTimerController.pomodoroBreak);
    expect(s.remainingAt(fakeNow), FocusTimerController.pomodoroBreak);
    // One for the focus leg, one for the auto-chained break leg.
    expect(notificationService.timerEndCalls, hasLength(2));
    controller().cancel();
  });

  testWidgets('a plain fixed timer (not a Pomodoro) goes idle on completion, no auto-chain',
      (tester) async {
    controller().startFixed(FocusTimerController.fifteenMinutes);

    await advance(tester, FocusTimerController.fifteenMinutes);

    expect(state().isIdle, true);
  });

  testWidgets('startTwoMinutes starts a plain 2분 timer', (tester) async {
    controller().startTwoMinutes();

    expect(state().totalDuration, const Duration(minutes: 2));
    expect(state().phase, FocusTimerPhase.focus);

    await advance(tester, const Duration(minutes: 2));
    expect(state().isIdle, true);
  });

  testWidgets('pause freezes the remaining time and cancels the scheduled notification',
      (tester) async {
    controller().startFixed(FocusTimerController.fifteenMinutes);
    await advance(tester, const Duration(minutes: 5));

    controller().pause();
    final s = state();
    expect(s.isPaused, true);
    expect(s.remainingAt(fakeNow), const Duration(minutes: 10));
    expect(notificationService.timerEndCancelCount, 1);

    // Time passing while paused must not change the frozen remaining value.
    await advance(tester, const Duration(minutes: 3));
    expect(state().remainingAt(fakeNow), const Duration(minutes: 10));
  });

  testWidgets('resume picks up from the frozen remaining time and reschedules the notification',
      (tester) async {
    controller().startFixed(FocusTimerController.fifteenMinutes);
    await advance(tester, const Duration(minutes: 5));
    controller().pause();

    await advance(tester, const Duration(minutes: 2)); // paused -- shouldn't matter
    controller().resume();

    final s = state();
    expect(s.isRunning, true);
    expect(s.remainingAt(fakeNow), const Duration(minutes: 10));
    expect(notificationService.timerEndCalls, hasLength(2)); // initial start + resume

    await advance(tester, const Duration(minutes: 10));
    expect(state().isIdle, true);
  });

  testWidgets('cancel goes idle immediately and cancels the scheduled notification',
      (tester) async {
    controller().startPomodoro();
    await advance(tester, const Duration(minutes: 10));

    controller().cancel();

    expect(state().isIdle, true);
    expect(notificationService.timerEndCancelCount, 1);

    // No lingering ticker -- letting more time pass changes nothing further.
    await advance(tester, const Duration(minutes: 30));
    expect(state().isIdle, true);
  });

  testWidgets('pause/resume/cancel on an idle timer are no-ops', (tester) async {
    controller().pause();
    expect(state().isIdle, true);

    controller().resume();
    expect(state().isIdle, true);

    controller().cancel();
    expect(state().isIdle, true);
    expect(notificationService.timerEndCancelCount, 1); // cancel() itself still calls through
  });
}
