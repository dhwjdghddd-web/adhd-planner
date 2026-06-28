import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_log.dart';
import '../../core/time_geometry.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';
import 'alarm_skip_controller.dart';
import 'focus_page.dart';

// Same platform channel MainActivity already handles for alarm sound/vibration.
// Used here only for the screen-off (power-button) dismissal guard: Dart asks
// native to start/stop watching for ACTION_SCREEN_OFF, and native calls back
// 'onAlarmDismissedByPower' once it fires (having already silenced the alarm).
const _alarmGuardChannel = MethodChannel('com.adhdplanner.adhd_planner/alarm_sound');

/// Full-screen alarm takeover — pushed as a route (not a small dialog) by
/// app.dart's `_showAlarmScreen` when a block's start alarm fires, including the
/// system auto-launching the app over the lock screen via `fullScreenIntent`
/// (the activity declares `showWhenLocked`/`turnScreenOn`, so it wakes the
/// screen like a real alarm clock). A big clock + block name, started by a
/// deliberate slide so a groggy half-tap can't clear it by accident -- plus
/// two lighter exits below it ("N분 뒤 다시"/"오늘은 건너뛰기") for "지금은 못
/// 해" rather than only ever being able to start or silently ignore it.
///
/// [notificationId] is the still-showing, insistently repeating alarm
/// notification: opening this screen (whether via a real tap, the system
/// auto-launching it, or `_ForegroundAlarmWatcher`'s own foreground check)
/// never silences it on its own -- only this screen's own three actions below
/// (slide-to-dismiss/snooze/skip) or the power-button screen-off guard do, so
/// the ring/vibration keeps going exactly the way a real alarm clock's would
/// until actually responded to. The notification's own `timeoutAfter` and the
/// native Vibrator's `durationMs` (60s, see notification_service.dart) are the
/// fallback for a screen that's truly unreachable (e.g. a folded phone's cover
/// screen) -- it self-silences eventually rather than ringing forever.
class AlarmScreen extends ConsumerStatefulWidget {
  const AlarmScreen({
    super.key,
    required this.segmentId,
    required this.notificationId,
  });

  final String segmentId;
  final int notificationId;

  @override
  ConsumerState<AlarmScreen> createState() => _AlarmScreenState();
}

class _AlarmScreenState extends ConsumerState<AlarmScreen> {
  @override
  void initState() {
    super.initState();
    // While this alarm is up, have native treat a power-button press (which
    // turns the screen off) as "dismiss the alarm" -- the standard alarm-clock
    // gesture for silencing it without unlocking. Native silences the
    // sound/vibration and calls back so we can close this screen.
    _alarmGuardChannel.setMethodCallHandler(_onNativeCall);
    _alarmGuardChannel
        .invokeMethod('startScreenOffGuard', {'notificationId': widget.notificationId})
        .catchError((Object e) {
      // No platform channel (e.g. under flutter test).
      logSwallowed('알람 화면 끄기 가드 시작', e);
    });
  }

  Future<dynamic> _onNativeCall(MethodCall call) async {
    if (call.method == 'onAlarmDismissedByPower' && mounted) {
      // Native already stopped the sound/vibration; just close the alarm screen
      // (no jump into Focus -- a power-button dismiss means "not now").
      Navigator.of(context).maybePop();
    }
    return null;
  }

  @override
  void dispose() {
    _alarmGuardChannel.setMethodCallHandler(null);
    _alarmGuardChannel.invokeMethod('stopScreenOffGuard').catchError((Object e) {
      logSwallowed('알람 화면 끄기 가드 정지', e);
    });
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider).value ?? const <Segment>[];
    Segment? segment;
    for (final s in segments) {
      if (s.id == widget.segmentId) {
        segment = s;
        break;
      }
    }

    final settings = ref.watch(settingsProvider).value ?? const AppSettings.defaults();
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    if (segment == null) {
      return Scaffold(
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('구간을 찾을 수 없어요'),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: const Text('닫기'),
              ),
            ],
          ),
        ),
      );
    }

    final mutedColor = isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68);

    // No back button / pop scope: the slide is the only way out, so a stray
    // system-back can't dismiss the alarm without the deliberate gesture.
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),
                Icon(Icons.alarm, size: 72, color: theme.colorScheme.primary),
                const SizedBox(height: 28),
                Text(
                  TimeGeometry.formatMinute(segment.startMinute),
                  style: theme.textTheme.displayMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  segment.name,
                  style: theme.textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 12),
                Text(
                  '지금 시작할 시간이에요',
                  style: theme.textTheme.titleMedium?.copyWith(color: mutedColor),
                  textAlign: TextAlign.center,
                ),
                const Spacer(flex: 3),
                _SlideToDismiss(
                  label: '밀어서 끄기',
                  onDismiss: () => _dismiss(segment!),
                ),
                const SizedBox(height: 20),
                // Two lighter exits below the slide track (never overlapping
                // it) -- "지금은 못 함"의 출구. A bare 해제 was the only
                // response before; these turn the alarm into something you can
                // actually answer instead of just silencing and ignoring.
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => _snooze(segment!, settings.snoozeMinutes),
                        child: Text('${settings.snoozeMinutes}분 뒤 다시'),
                      ),
                    ),
                    Expanded(
                      child: TextButton(
                        onPressed: () => _skipToday(segment!),
                        child: const Text('오늘은 건너뛰기'),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // Dismissing turns the alarm off and opens Focus so "the alarm told me to
  // start this block" leads straight into actually doing it (and ticking its
  // 루틴 items). It never records a completion on its own -- that's Focus's job
  // once the items are checked.
  //
  // pushAndRemoveUntil down to the root (not pushReplacement): the alarm can
  // fire while the user is *already* on a Focus screen, and a plain replacement
  // would leave that earlier Focus underneath this one -- two stacked Focus
  // screens, needing two back-taps to reach home. Resetting to [home, Focus]
  // guarantees exactly one Focus regardless of what was open when it rang.
  void _dismiss(Segment segment) {
    unawaited(_tryCancelNotification());
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => FocusPage.forBlock(segment)),
      (route) => route.isFirst,
    );
  }

  Future<void> _tryCancelNotification() async {
    try {
      await ref.read(notificationServiceProvider).cancelNotification(widget.notificationId);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 끄기-알림취소', e);
    }
  }

  // "지금은 못 함, 잠시 후에" -- silences this ring and arms a one-time re-alert
  // (see NotificationService.scheduleSnooze) rather than just disappearing
  // until tomorrow, which is what a bare 해제/무시 would do.
  void _snooze(Segment segment, int snoozeMinutes) {
    unawaited(_cancelThenScheduleSnooze(segment));
    // pop, not maybePop: this screen's PopScope(canPop: false) blocks
    // maybePop()/popDisposition-based pops (that's the whole point -- it's
    // what stops a stray system back gesture) but does NOT affect this direct
    // imperative pop, which is exactly the deliberate exit these two buttons
    // are meant to be.
    Navigator.of(context).pop();
  }

  // Cancel and schedule both round-trip through the SAME native channel
  // (com.adhdplanner.adhd_planner/alarm_sound) and act on the SAME
  // requestCode's AlarmManager entry -- cancelNotification's
  // cancelVibrationAlarm call and scheduleSnooze's scheduleVibrationAlarm call
  // are two independent platform-channel round-trips with no ordering
  // guarantee between them if fired concurrently (each goes through its own
  // chain of awaits -- e.g. cancel waits on flutter_local_notifications' own
  // plugin.cancel first). Firing them unawaited side-by-side let the
  // schedule's "arm the snooze alarm" sometimes land *before* the dismiss's
  // "cancel whatever's armed for this id" -- silently wiping out the just-armed
  // snooze. Awaiting cancel to fully finish first makes the order
  // deterministic: cancel today's ring, *then* arm the snooze.
  Future<void> _cancelThenScheduleSnooze(Segment segment) async {
    await _tryCancelNotification();
    await _tryScheduleSnooze(segment);
  }

  Future<void> _tryScheduleSnooze(Segment segment) async {
    try {
      final settings = ref.read(settingsProvider).value ?? const AppSettings.defaults();
      await ref
          .read(notificationServiceProvider)
          .scheduleSnooze(segment: segment, settings: settings);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 스누즈 예약', e);
    }
  }

  // "오늘은 그냥 패스" -- silences this ring and records a skip for today (see
  // AlarmSkipController/_ForegroundAlarmWatcher) instead of starting the block.
  // Tomorrow's normal daily alarm is untouched.
  void _skipToday(Segment segment) {
    unawaited(_tryCancelNotification());
    unawaited(ref.read(alarmSkipControllerProvider).skipToday(segment.id));
    // pop, not maybePop -- see the comment in _snooze above.
    Navigator.of(context).pop();
  }
}

/// A slide-to-confirm control: drag the thumb to the far end to fire
/// [onDismiss]. A deliberate gesture (rather than a tap) so a half-asleep user
/// can't clear the alarm by accident — the standard alarm-clock affordance.
class _SlideToDismiss extends StatefulWidget {
  const _SlideToDismiss({required this.onDismiss, required this.label});

  final VoidCallback onDismiss;
  final String label;

  @override
  State<_SlideToDismiss> createState() => _SlideToDismissState();
}

class _SlideToDismissState extends State<_SlideToDismiss> {
  static const _thumb = 60.0;
  static const _trackHeight = 68.0;
  double _dragX = 0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final primary = theme.colorScheme.primary;

    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth = constraints.maxWidth;
        final maxDrag = (trackWidth - _thumb - 8).clamp(0.0, double.infinity);
        final progress = maxDrag == 0 ? 0.0 : (_dragX / maxDrag).clamp(0.0, 1.0);

        return SizedBox(
          height: _trackHeight,
          width: double.infinity,
          child: Stack(
            alignment: Alignment.centerLeft,
            children: [
              // Track
              Container(
                decoration: BoxDecoration(
                  color: primary.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(_trackHeight / 2),
                  border: Border.all(color: primary.withValues(alpha: 0.30)),
                ),
              ),
              // Label, fading as the thumb advances.
              Center(
                child: Opacity(
                  opacity: 1 - progress,
                  child: Text(
                    widget.label,
                    style: theme.textTheme.titleMedium?.copyWith(
                      color: primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              // Draggable thumb.
              Padding(
                padding: const EdgeInsets.all(4),
                child: Transform.translate(
                  offset: Offset(_dragX, 0),
                  child: GestureDetector(
                    key: const Key('alarm-dismiss-thumb'),
                    onHorizontalDragUpdate: (details) {
                      setState(() {
                        _dragX = (_dragX + details.delta.dx).clamp(0.0, maxDrag);
                      });
                    },
                    onHorizontalDragEnd: (_) {
                      if (_dragX >= maxDrag * 0.85 && maxDrag > 0) {
                        widget.onDismiss();
                      } else {
                        setState(() => _dragX = 0);
                      }
                    },
                    child: Container(
                      width: _thumb,
                      height: _thumb,
                      decoration: BoxDecoration(
                        color: primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.chevron_right,
                        color: theme.colorScheme.onPrimary,
                        size: 32,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
