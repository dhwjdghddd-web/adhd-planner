import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_geometry.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/routine.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';
import 'completions_controller.dart';

/// Small dialog popped over whatever's on screen — not a full page — when
/// the main alarm notification is tapped, or the system auto-launches the
/// app via `fullScreenIntent` (see notification_service.dart and
/// app.dart's `_AlarmAlertLauncher`). A real alarm-clock-style takeover
/// page felt heavier than this app wants; a title/time + 완료/미루기 popup
/// is enough.
///
/// [notificationId] identifies exactly which still-showing (and
/// insistently repeating) notification to dismiss once 완료/미루기 is
/// pressed — without cancelling it explicitly, the sound/vibration would
/// keep going even after this dialog closes.
class AlarmAlertDialog extends ConsumerWidget {
  const AlarmAlertDialog({super.key, required this.routineId, required this.notificationId});

  final String routineId;
  final int notificationId;

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

    return AlertDialog(
      icon: const Icon(Icons.alarm),
      title: Text(routine.title),
      content: Text(TimeGeometry.formatMinute(routine.startMinute)),
      actions: [
        TextButton(
          onPressed: () => _postpone(context, ref, routine!),
          child: const Text('미루기'),
        ),
        FilledButton(
          onPressed: () => _complete(context, ref, routine!),
          child: const Text('완료'),
        ),
      ],
    );
  }

  // Closing the dialog never waits on the completion write or the
  // notification-cancel call -- same reason as everywhere else in this app
  // that touches the repository or the plugin: either can be slow (offline
  // Firestore writes never resolve locally) or simply unavailable (no
  // platform channel under flutter test), and none of that should keep
  // this dialog stuck open.
  void _complete(BuildContext context, WidgetRef ref, Routine routine) {
    unawaited(ref.read(completionsControllerProvider).complete(routine.id));
    unawaited(_tryCancelNotification(ref));
    Navigator.of(context).maybePop();
  }

  void _postpone(BuildContext context, WidgetRef ref, Routine routine) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings.defaults();
    unawaited(_tryPostpone(ref, routine.id, settings));
    Navigator.of(context).maybePop();
  }

  Future<void> _tryCancelNotification(WidgetRef ref) async {
    try {
      await ref.read(notificationServiceProvider).cancelNotification(notificationId);
    } catch (_) {
      // No platform channel available (e.g. under flutter test).
    }
  }

  Future<void> _tryPostpone(WidgetRef ref, String routineId, AppSettings settings) async {
    final service = ref.read(notificationServiceProvider);
    try {
      await service.postpone(routineId, settings);
      await service.cancelNotification(notificationId);
    } catch (_) {
      // No platform channel available (e.g. under flutter test).
    }
  }
}
