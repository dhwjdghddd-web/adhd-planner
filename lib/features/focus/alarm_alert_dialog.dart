import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/debug_log.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';
import 'focus_page.dart';

/// Small dialog popped over whatever's on screen — not a full page — when a
/// block's start alarm is tapped, or the system auto-launches the app via
/// `fullScreenIntent` (see notification_service.dart and app.dart's
/// `_AlarmAlertLauncher`/`_ForegroundAlarmWatcher`). A title/time + 확인 popup
/// is all the interaction a block alarm needs.
///
/// [notificationId] identifies exactly which still-showing (and insistently
/// repeating) notification to dismiss once 확인 is pressed — the notification's
/// `autoCancel` is off specifically so tapping it to open this dialog doesn't
/// already silently stop the sound/vibration before the user has acted on it.
class AlarmAlertDialog extends ConsumerWidget {
  const AlarmAlertDialog({
    super.key,
    required this.segmentId,
    required this.notificationId,
  });

  final String segmentId;
  final int notificationId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segments = ref.watch(segmentsProvider).value ?? const <Segment>[];
    Segment? segment;
    for (final s in segments) {
      if (s.id == segmentId) {
        segment = s;
        break;
      }
    }

    if (segment == null) {
      return AlertDialog(
        title: const Text('구간을 찾을 수 없어요'),
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

    return AlertDialog(
      icon: Icon(
        Icons.access_time_filled,
        size: 40,
        color: theme.colorScheme.primary,
      ),
      title: Text(
        segment.name,
        style: theme.textTheme.headlineMedium,
        textAlign: TextAlign.center,
      ),
      content: Text(
        '${TimeGeometry.formatMinute(segment.startMinute)} · 지금 시작할 시간이에요',
        style: theme.textTheme.titleMedium?.copyWith(
          color: isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68),
        ),
        textAlign: TextAlign.center,
      ),
      actions: [
        FilledButton(
          onPressed: () => _confirm(context, ref),
          child: const Text('확인'),
        ),
      ],
    );
  }

  // 확인 turns the alarm off and opens FocusPage so "확인'd the alarm telling
  // me to start this block" leads straight into actually doing it (and ticking
  // its 루틴 items). It never records a completion on its own -- that's Focus's
  // job once the items are checked.
  void _confirm(BuildContext context, WidgetRef ref) {
    unawaited(_tryCancelNotification(ref));
    final segment = ref.read(segmentsProvider).value?.firstWhere(
          (s) => s.id == segmentId,
          orElse: () => throw StateError('missing'),
        );
    // pushReplacement (not pop, then push elsewhere) so the dialog route is
    // actually replaced by FocusPage rather than left underneath it -- popping
    // first and pushing separately raced the dialog's own closing animation,
    // leaving it still in the stack even though it looked closed.
    if (segment != null) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => FocusPage.forBlock(segment)),
      );
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _tryCancelNotification(WidgetRef ref) async {
    try {
      await ref.read(notificationServiceProvider).cancelNotification(notificationId);
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('알람 확인-알림취소', e);
    }
  }
}
