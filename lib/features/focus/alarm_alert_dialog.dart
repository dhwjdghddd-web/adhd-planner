import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_log.dart';
import '../../core/time_geometry.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/routine.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';
import '../memos/quick_add_button.dart' show appNavigatorKey, showAppSnackBar;
import 'focus_page.dart';

/// Small dialog popped over whatever's on screen — not a full page — when
/// an alarm notification (lead-warning or main) is tapped, or the system
/// auto-launches the app via `fullScreenIntent` (see notification_service.dart
/// and app.dart's `_AlarmAlertLauncher`/`_ForegroundAlarmWatcher`). A real
/// alarm-clock-style takeover page felt heavier than this app wants; a
/// title/time + 확인/미루기 popup is enough.
///
/// [notificationId] identifies exactly which still-showing (and
/// insistently repeating) notification to dismiss once 확인/미루기 is
/// pressed — the notification's `autoCancel` is off specifically so tapping
/// it to open this dialog doesn't already silently stop the sound/vibration
/// before the user has actually acted on it.
class AlarmAlertDialog extends ConsumerWidget {
  const AlarmAlertDialog({
    super.key,
    required this.routineId,
    required this.notificationId,
    this.isTransition = false,
  });

  final String routineId;
  final int notificationId;
  // True for the lead-warning (전환예고) alert.
  final bool isTransition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final routines = ref.watch(routinesProvider).value ?? const <Routine>[];
    Routine? routine;
    for (final r in routines) {
      if (r.id == routineId) {
        routine = r;
        break;
      }
    }

    if (routine == null) {
      return AlertDialog(
        title: const Text('루틴을 찾을 수 없어요'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).maybePop(),
            child: const Text('닫기'),
          ),
        ],
      );
    }

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Stack(
      clipBehavior: Clip.none,
      children: [
        // 1. Centered Alert Dialog
        Align(
          alignment: Alignment.center,
          child: AlertDialog(
            icon: Icon(
              Icons.access_time_filled,
              size: 40,
              color: theme.colorScheme.primary,
            ),
            title: Text(
              routine.title,
              style: theme.textTheme.headlineMedium,
              textAlign: TextAlign.center,
            ),
            content: Text(
              isTransition
                  ? '${TimeGeometry.formatMinute(routine.startMinute)}에 시작해요'
                  : TimeGeometry.formatMinute(routine.startMinute),
              style: theme.textTheme.titleMedium?.copyWith(
                color: isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68),
              ),
              textAlign: TextAlign.center,
            ),
            actions: [
              TextButton(
                onPressed: () => _skip(context, ref, routine!),
                child: const Text('넘기기'),
              ),
              TextButton(
                onPressed: () => _postpone(context, ref, routine!),
                child: const Text('미루기'),
              ),
              FilledButton(
                onPressed: () => _confirm(context, ref),
                child: const Text('확인'),
              ),
            ],
          ),
        ),
        
        // 2. Floating Top Banner
        Positioned(
          top: 56,
          left: 16,
          right: 16,
          child: Material(
            color: Colors.transparent,
            child: Align(
              alignment: Alignment.topCenter,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1E2630) : const Color(0xFFFFFFFF),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: theme.colorScheme.outline.withValues(alpha: 0.15),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.12),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.notifications_active,
                      color: theme.colorScheme.primary,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        isTransition
                            ? '${routine.title} 곧 시작할 시간이에요'
                            : '${routine.title} 지금 시작할 시간이에요',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: isDark ? const Color(0xFFE9EEF3) : const Color(0xFF171C22),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  // 확인 just turns the alarm off -- it never records a completion on its
  // own (that's Focus's job, including checking off micro-steps), so it
  // doesn't matter whether this was the lead-warning or the main alarm.
  // For the main alarm specifically, it also opens FocusPage right away,
  // since "확인'd the alarm telling me to start this" naturally leads
  // straight into actually starting it -- the lead-warning doesn't get
  // this, since "곧 전환" isn't "start now" yet; going into FocusPage on
  // its own already shows the upcoming routine's micro-steps to pre-check
  // once its remaining time drops inside its own leadWarningMin window.
  void _confirm(BuildContext context, WidgetRef ref) {
    unawaited(_tryCancelNotification(ref));
    if (isTransition) {
      Navigator.of(context).maybePop();
      return;
    }
    // pushReplacement (not pop, then push elsewhere) so the dialog route
    // is actually replaced by FocusPage rather than left underneath it --
    // popping first and pushing separately raced the dialog's own closing
    // animation, leaving it still in the stack (and visible again on
    // FocusPage's own back button) even though it looked closed.
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const FocusPage()),
    );
  }

  void _postpone(BuildContext context, WidgetRef ref, Routine routine) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings.defaults();
    unawaited(_tryPostpone(ref, routine.id, settings));
    Navigator.of(context).maybePop();
    _showFeedback('${routine.snoozeMin}분 후 다시 알려드려요');
  }

  // "넘기기": today's occurrence is done with entirely, not just snoozed --
  // see NotificationService.skipToday for why this also needs to cancel
  // today's still-armed alarms (not just this one) rather than only this
  // notification.
  void _skip(BuildContext context, WidgetRef ref, Routine routine) {
    unawaited(_trySkip(ref, routine.id));
    Navigator.of(context).maybePop();
    _showFeedback('${routine.title}을(를) 내일로 넘겼어요');
  }

  // The dialog's own context is gone right after maybePop() -- this app's
  // single shared Navigator's current context is what's left on screen
  // once the dialog finishes closing, same trick app.dart's launcher uses
  // to open the dialog in the first place.
  void _showFeedback(String message) {
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    showAppSnackBar(context, Text(message));
  }

  Future<void> _tryCancelNotification(WidgetRef ref) async {
    try {
      await ref.read(notificationServiceProvider).cancelNotification(notificationId);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 확인-알림취소', e);
    }
  }

  Future<void> _tryPostpone(WidgetRef ref, String routineId, AppSettings settings) async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.postpone(routineId, settings);
      await service.cancelNotification(notificationId);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 미루기', e);
    }
  }

  Future<void> _trySkip(WidgetRef ref, String routineId) async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.skipToday(routineId);
      await service.cancelNotification(notificationId);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 넘기기', e);
    }
  }
}
