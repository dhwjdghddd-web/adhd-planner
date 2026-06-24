import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_log.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';
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
/// screen like a real alarm clock). A big clock + block name, dismissed by a
/// deliberate slide so a groggy half-tap can't clear it by accident.
///
/// [notificationId] is the still-showing, insistently repeating alarm
/// notification to silence on dismiss — though the tap/auto-launch that opened
/// this has usually silenced it already (see notification_service's
/// `_handleResponse`); re-cancelling the same id is a harmless no-op safety net
/// for the foreground-clock path (`_ForegroundAlarmWatcher`) that reaches here
/// without a real notification tap.
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
                const SizedBox(height: 32),
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
  void _dismiss(Segment segment) {
    unawaited(_tryCancelNotification());
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => FocusPage.forBlock(segment)),
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
