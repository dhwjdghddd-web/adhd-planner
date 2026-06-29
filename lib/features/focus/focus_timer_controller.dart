import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../services/notification_service.dart';

/// Which leg of a Pomodoro cycle a running/paused timer is on -- a plain
/// fixed-length timer (15분/사용자정의/2분) is always [focus] and never
/// chains into a break.
enum FocusTimerPhase { focus, breakTime }

/// Snapshot of the Focus screen's optional timer. Deliberately stores the
/// wall-clock [endAt] rather than a ticking-down remaining count: a backed
/// timer recomputed only against a stored remaining-seconds counter would
/// drift if a tick is ever skipped or delayed (e.g. the app briefly
/// suspended) -- recomputing against [endAt] on every read is always
/// accurate the moment the UI looks again, with no catch-up needed.
@immutable
class FocusTimerState {
  const FocusTimerState({
    this.endAt,
    this.totalDuration = Duration.zero,
    this.pausedRemaining,
    this.phase = FocusTimerPhase.focus,
    this.willAutoChainBreak = false,
  });

  /// Wall-clock time this leg ends, while running. Null when idle or paused.
  final DateTime? endAt;
  // Length of the *current* leg (e.g. 25분 while on the focus leg of a
  // Pomodoro, then 5분 once it auto-chains into the break) -- what
  // [progressAt] measures against, not the cycle as a whole.
  final Duration totalDuration;

  /// Remaining time frozen at the moment [FocusTimerController.pause] was
  /// called. Null unless actually paused.
  final Duration? pausedRemaining;
  final FocusTimerPhase phase;
  // True only for a Pomodoro's focus leg -- its completion starts the break
  // leg automatically instead of just stopping.
  final bool willAutoChainBreak;

  bool get isIdle => totalDuration == Duration.zero;
  bool get isPaused => !isIdle && endAt == null;
  bool get isRunning => endAt != null;

  Duration remainingAt(DateTime now) {
    if (isIdle) return Duration.zero;
    if (isPaused) return pausedRemaining!;
    final left = endAt!.difference(now);
    return left.isNegative ? Duration.zero : left;
  }

  /// 0.0 (just started) to 1.0 (done).
  double progressAt(DateTime now) {
    if (isIdle || totalDuration == Duration.zero) return 0;
    final remainingMs = remainingAt(now).inMilliseconds;
    final progress = 1 - remainingMs / totalDuration.inMilliseconds;
    return progress.clamp(0.0, 1.0);
  }
}

final focusTimerControllerProvider =
    StateNotifierProvider<FocusTimerController, FocusTimerState>(
      (ref) => FocusTimerController(ref),
    );

/// Drives [FocusTimerState]: a Pomodoro (25분 집중, auto-chains into 5분
/// 휴식), a plain fixed-length timer (15분/사용자정의/2분), pause/resume/cancel.
/// Global (not scoped to a particular block or to FocusPage's lifetime) so a
/// running timer survives leaving Focus and its end notification still fires
/// in the background -- see [NotificationService.scheduleTimerEnd].
class FocusTimerController extends StateNotifier<FocusTimerState> {
  FocusTimerController(this._ref, {@visibleForTesting DateTime Function()? now})
    : _now = now ?? DateTime.now,
      super(const FocusTimerState());

  final Ref _ref;
  // Test-only override for "now" -- DateTime.now() itself can't be faked by
  // flutter_test's FakeAsync zone (unlike Timer/Future.delayed), so a
  // controller test injects a controllable clock here instead, the same
  // "now is a parameter, not a global" approach the rest of this codebase
  // uses (e.g. FocusPage.debugNowMinuteOfDay).
  final DateTime Function() _now;
  Timer? _ticker;

  static const pomodoroFocus = Duration(minutes: 25);
  static const pomodoroBreak = Duration(minutes: 5);
  static const fifteenMinutes = Duration(minutes: 15);
  static const twoMinutes = Duration(minutes: 2);

  void startPomodoro() => _start(
    pomodoroFocus,
    phase: FocusTimerPhase.focus,
    willAutoChainBreak: true,
  );

  void startFixed(Duration duration) =>
      _start(duration, phase: FocusTimerPhase.focus, willAutoChainBreak: false);

  void startTwoMinutes() => startFixed(twoMinutes);

  void _start(
    Duration duration, {
    required FocusTimerPhase phase,
    required bool willAutoChainBreak,
  }) {
    final endAt = _now().add(duration);
    state = FocusTimerState(
      endAt: endAt,
      totalDuration: duration,
      phase: phase,
      willAutoChainBreak: willAutoChainBreak,
    );
    _scheduleNotification(endAt, phase);
    _runTicker();
  }

  void pause() {
    if (!state.isRunning) return;
    _ticker?.cancel();
    state = FocusTimerState(
      pausedRemaining: state.remainingAt(_now()),
      totalDuration: state.totalDuration,
      phase: state.phase,
      willAutoChainBreak: state.willAutoChainBreak,
    );
    unawaited(_ref.read(notificationServiceProvider).cancelTimerEnd());
  }

  void resume() {
    if (!state.isPaused) return;
    final endAt = _now().add(state.pausedRemaining!);
    state = FocusTimerState(
      endAt: endAt,
      totalDuration: state.totalDuration,
      phase: state.phase,
      willAutoChainBreak: state.willAutoChainBreak,
    );
    _scheduleNotification(endAt, state.phase);
    _runTicker();
  }

  void cancel() {
    _ticker?.cancel();
    state = const FocusTimerState();
    unawaited(_ref.read(notificationServiceProvider).cancelTimerEnd());
  }

  void _runTicker() {
    _ticker?.cancel();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
  }

  void _tick() {
    if (!state.isRunning) return;
    if (state.remainingAt(_now()) <= Duration.zero) {
      _onLegComplete();
    } else {
      // A fresh instance with the same fields: forces dependents watching
      // this provider to rebuild every second so the on-screen countdown
      // (computed from endAt, not stored here) keeps refreshing.
      state = FocusTimerState(
        endAt: state.endAt,
        totalDuration: state.totalDuration,
        phase: state.phase,
        willAutoChainBreak: state.willAutoChainBreak,
      );
    }
  }

  void _onLegComplete() {
    _ticker?.cancel();
    if (state.phase == FocusTimerPhase.focus && state.willAutoChainBreak) {
      _start(
        pomodoroBreak,
        phase: FocusTimerPhase.breakTime,
        willAutoChainBreak: false,
      );
    } else {
      state = const FocusTimerState();
    }
  }

  void _scheduleNotification(DateTime endAt, FocusTimerPhase phase) {
    final isFocus = phase == FocusTimerPhase.focus;
    unawaited(
      _ref
          .read(notificationServiceProvider)
          .scheduleTimerEnd(
            endAt: endAt,
            title: isFocus ? '집중 시간이 끝났어요' : '휴식이 끝났어요',
            body: isFocus ? '잘하셨어요 — 잠깐 쉬어가요' : '다시 집중할 시간이에요',
          ),
    );
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }
}
