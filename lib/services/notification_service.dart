import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/debug_log.dart';
import '../data/models/app_settings.dart';
import '../data/models/segment.dart';
import '../data/providers.dart';
import '../data/repositories/planner_repository.dart';
import 'notification_schedule.dart';
// The pure scheduling logic lives in notification_schedule.dart; re-export it
// so existing importers of this file (and notification_service_test) keep
// seeing buildSchedule/ScheduledSpec/notificationIdFor/nextInstanceOf/
// vibrationPatternFor unchanged.
export 'notification_schedule.dart';

// The base channel id is versioned because Android notification channels are
// immutable after creation on a given install — every time a channel-level
// setting (importance, sound, vibration) changes, anyone with the app already
// installed would keep the old behavior forever unless the id changes too. The
// sound/vibration choice itself is encoded into the id as a suffix for the
// same reason — see _channelSuffix.
const _alarmChannelBase = 'routine_v2';
const _alarmChannelName = '구간 알람';

// USAGE_ALARM is what makes these ring/vibrate through the alarm stream
// instead of the notification stream — the same reason a normal alarm clock
// app still goes off when the phone's ringer is set to silent or vibrate.
const _alarmAudioUsage = AudioAttributesUsage.alarm;
const _alarmCategory = AndroidNotificationCategory.alarm;
// Notification.FLAG_INSISTENT (not exposed as a named constant by the
// plugin): repeats the sound/vibration on a loop for as long as the
// notification exists, rather than alerting once and going quiet.
final _insistentFlag = Int32List.fromList([4]);
// Repeats for a full minute, then the system cancels it on its own even if
// the app isn't running — no snooze/dismiss needed for it to eventually
// stop on its own.
const _alarmRepeatMs = 60000;

final _plugin = FlutterLocalNotificationsPlugin();

final notificationServiceProvider = Provider<NotificationService>((ref) {
  // uid가 null인 순간(signOut ↔ signInAnonymously 사이)에는 repo가 null.
  // NotificationService는 null repo로도 생성 가능하며, 실제 사용 시 !로 단언.
  return NotificationService(ref.watch(plannerRepositoryProvider));
});

AndroidNotificationSound _soundFor(AppSettings settings) {
  final uri = settings.alarmSoundUri;
  if (uri == null) {
    return const UriAndroidNotificationSound('content://settings/system/alarm_alert');
  }
  return UriAndroidNotificationSound(uri);
}

// Encodes the sound+vibration choice into the channel id so changing either
// in Settings creates a fresh channel with the new behaviour rather than
// silently keeping the old one — see the comment on the *ChannelBase
// constant. Stable for a given (sound, pattern) pair, so switching back to a
// combination tried before reuses that channel instead of piling up new ones.
String _channelSuffix(AppSettings settings) {
  final soundKey = (settings.alarmSoundUri ?? 'default').hashCode.toUnsigned(20).toRadixString(36);
  return '${soundKey}_${settings.vibrationPattern.name}';
}

String _alarmChannelId(AppSettings settings) => '${_alarmChannelBase}_${_channelSuffix(settings)}';

AndroidNotificationDetails _androidDetailsFor(ScheduledSpec spec, AppSettings settings) {
  final sound = _soundFor(settings);
  final vibrationPattern = vibrationPatternFor(settings.vibrationPattern);

  return AndroidNotificationDetails(
    _alarmChannelId(settings),
    _alarmChannelName,
    importance: Importance.max,
    priority: Priority.high,
    enableVibration: true,
    vibrationPattern: vibrationPattern,
    sound: sound,
    audioAttributesUsage: _alarmAudioUsage,
    category: _alarmCategory,
    additionalFlags: _insistentFlag,
    // autoCancel's default (true) only removes the notification (and so its
    // own sound) on tap -- it has no idea about the separate native Vibrator
    // alarm riding alongside it, which would keep buzzing regardless. Left
    // off so dismissal always goes through our own explicit cancel in
    // _handleResponse below, which stops both.
    autoCancel: false,
    timeoutAfter: _alarmRepeatMs,
    // Pops AlarmAlertDialog over the lock screen like a real alarm clock,
    // rather than waiting for the user to pull down the shade and tap it.
    fullScreenIntent: true,
    // No action buttons: a plain body tap (or the fullScreenIntent
    // auto-launch) is the only alarm interaction there is, and it already
    // silences the alarm on its own -- see _handleResponse.
  );
}

// Talks to MainActivity.kt's "ensureAlarmChannel" handler — see the long
// comment there for why this can't just be
// AndroidFlutterLocalNotificationsPlugin.createNotificationChannel: that
// path builds the channel's AudioAttributes with only setUsage(), and
// Android then defaults to muting the haptic (vibration) channel on it,
// which silently kills vibration on an otherwise-correct USAGE_ALARM
// channel. Building the channel natively is the only way to clear that.
const _alarmChannelChannel = MethodChannel('com.adhdplanner.adhd_planner/alarm_sound');

/// Creates (or, for a combination already seen before, reuses) the alarm
/// channel for [settings]'s current sound+vibration choice. Safe to call every
/// time alarms are rescheduled — creating a channel that already exists with
/// that exact id is a no-op.
Future<void> _ensureChannels(AppSettings settings) async {
  final soundUri = settings.alarmSoundUri ?? 'content://settings/system/alarm_alert';
  final vibrationPattern = vibrationPatternFor(settings.vibrationPattern);
  try {
    await _alarmChannelChannel.invokeMethod('ensureAlarmChannel', {
      'id': _alarmChannelId(settings),
      'name': _alarmChannelName,
      'description': '구간 시작 시각에 울리는 알람',
      'importance': Importance.max.value,
      'soundUri': soundUri,
      // .toList() rather than the raw Int64List: a plain Dart List always
      // arrives as a Java/Kotlin List via the standard method codec, which
      // is what MainActivity.kt's handler expects — a typed list like
      // Int64List instead maps to a raw long[], a different shape.
      'vibrationPattern': vibrationPattern.toList(),
    });
  } catch (e) {
    // No such platform channel (iOS, flutter test). The plugin's own
    // zonedSchedule call below will fall back to creating an ordinary
    // channel itself — sound still works there, just not the silent-mode
    // vibration bypass.
    logSwallowed('ensureAlarmChannel', e);
  }
}

/// Sets `tz.local` to the device's real timezone. Must be called before any
/// `tz.TZDateTime.now(tz.local)`/scheduling call — `tz.local` otherwise
/// defaults to UTC.
Future<void> _ensureLocalTimezone() async {
  tz_data.initializeTimeZones();
  try {
    final localTz = await FlutterTimezone.getLocalTimezone();
    tz.setLocalLocation(tz.getLocation(localTz.identifier));
  } catch (e) {
    tz.setLocalLocation(tz.UTC);
    logSwallowed('getLocalTimezone(UTC로 대체)', e);
  }
}

/// Local alarm scheduling: one start-of-block alarm per alarm-enabled block.
/// Works while the app is closed — Android replays scheduled alarms via the
/// plugin's own boot receiver (see AndroidManifest.xml), and notification taps
/// are handled by the top-level [handleNotificationResponse] below even if the
/// app process was killed.
class NotificationService {
  NotificationService(this._repository);

  final PlannerRepository? _repository;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: handleNotificationResponseBackground,
    );

    await _ensureLocalTimezone();
  }

  /// Requests POST_NOTIFICATIONS (Android 13+) and the exact-alarm
  /// permission (Android 12+). Returns false if either was denied so the
  /// caller can surface a settings-screen nudge.
  ///
  /// Also asks for the full-screen-intent permission the alarm uses to pop the
  /// alarm-alert screen over the lock screen (Android 14+ can ship this denied
  /// by default) — not folded into the return value since the alarm still
  /// works as an ordinary notification without it, just without the takeover.
  Future<bool> requestPermissions() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final notifications = await android?.requestNotificationsPermission();
    final exactAlarms = await android?.requestExactAlarmsPermission();
    await android?.requestFullScreenIntentPermission();
    return (notifications ?? true) && (exactAlarms ?? true);
  }

  /// Cancels every previously scheduled alarm and re-schedules exactly the
  /// ones [segments] now call for (one start-of-block alarm per alarm-enabled
  /// block), using [settings]'s current sound and vibration choice. Call this
  /// again whenever blocks or that choice change so it takes effect immediately.
  Future<void> rescheduleAll(List<Segment> segments, AppSettings settings) async {
    final repo = _repository;
    if (repo == null) return; // auth 전환 중 — 알람 재스케줄 건너뜀
    await _ensureChannels(settings);

    // 기존 알람을 전부 비우고 아래에서 현재 blocks만 다시 건다.
    // 네이티브가 자체 보관하는 requestCode 집합으로 진동 알람을 전부 취소하고
    // 그 id들을 받아, 같은 id의 flutter_local_notifications 알림도 id별로
    // 취소한다(_plugin.cancel은 추적 목록과 무관하게 id로 PendingIntent를
    // 재구성해 취소하므로, 재부팅 boot-replay로 플러그인 추적이 어긋나
    // cancelAll이 놓치는 고아 알림까지 잡는다). 마지막에 cancelAll로 한 번 더 정리.
    final staleIds = await _cancelAllVibrationAlarms();
    for (final id in staleIds) {
      await _plugin.cancel(id);
    }
    await _plugin.cancelAll();

    final specs = buildSchedule(segments);
    for (final spec in specs) {
      final triggerAt = nextInstanceOf(spec.minuteOfDay);
      await _plugin.zonedSchedule(
        spec.id,
        spec.title,
        spec.body,
        triggerAt,
        NotificationDetails(android: _androidDetailsFor(spec, settings)),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        // alarmClock (AlarmManager.setAlarmClock under the hood), not just
        // exactAllowWhileIdle: Samsung OneUI's "무음" ringer mode appears to
        // suppress vibration on a plain notification even with USAGE_ALARM set
        // on its channel, but alarms registered this way get the same "real
        // alarm clock" treatment as the stock clock app's alarms -- bypassing
        // ringer mode/DND. Trade-off: a permanent alarm-clock icon shows in
        // the status bar whenever one of these is pending.
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: DateTimeComponents.time,
        payload: spec.payload,
      );
      // The notification's own vibration is what 무음 ringer mode silences
      // (see VibrationAlarmReceiver.kt) -- this directly-triggered Vibrator
      // call alongside it is the part that actually buzzes in that mode.
      // Re-arms itself daily on the native side, so it stays in sync with
      // matchDateTimeComponents above without Dart needing to be running.
      await _scheduleVibrationAlarm(
        requestCode: spec.id,
        triggerAt: triggerAt,
        pattern: vibrationPatternFor(settings.vibrationPattern),
        durationMs: _alarmRepeatMs,
        repeatInterval: const Duration(days: 1),
      );
    }

    final idsBySegment = <String, List<int>>{};
    for (final spec in specs) {
      idsBySegment.putIfAbsent(spec.segmentId, () => []).add(spec.id);
    }
    for (final segment in segments) {
      final ids = idsBySegment[segment.id] ?? const <int>[];
      // NOT awaited: persisting notificationIds is a cache-side bookkeeping
      // write whose Firestore Future doesn't resolve until the backend acks
      // (never, while offline). The alarms themselves are already scheduled
      // above, so awaiting this here would, at app-startup (main.dart awaits
      // rescheduleAll before runApp), hang an offline launch on a black screen
      // for no benefit. The local cache updates synchronously, so cancelBlock
      // Alarms still reads the right ids.
      unawaited(repo.upsertSegment(segment.copyWith(notificationIds: ids)));
    }
  }

  /// Dismisses a still-showing notification outright — needed when a UI
  /// screen (rather than the notification tap itself) handles 확인, since the
  /// insistently-repeating alarm notification has to be cancelled manually to
  /// actually stop the sound. Also stops (and un-arms) this id's
  /// directly-triggered Vibrator call alongside it (see VibrationAlarmReceiver
  /// .kt) — that one keeps buzzing on its own timer independently.
  Future<void> cancelNotification(int id) => _silenceAlarm(id);

  /// Cancels every still-armed notification (and the Vibrator alarm riding
  /// alongside each) for a block that's about to be deleted. `rescheduleAll`'s
  /// own `cancelAll` only clears flutter_local_notifications' side -- a deleted
  /// block is gone from the list it rebuilds from, so without this its
  /// still-armed Vibrator alarms (which re-arm themselves weekly on the native
  /// side) would otherwise keep buzzing forever with nothing left to silence.
  Future<void> cancelBlockAlarms(Segment segment) async {
    for (final id in segment.notificationIds) {
      await cancelNotification(id);
    }
  }

  /// Wipes every alarm this device has scheduled -- both the
  /// flutter_local_notifications side (`cancelAll`, which is account-global)
  /// and the separate native Vibrator alarms riding alongside them -- without
  /// needing the current account's block list. Unlike [rescheduleAll], this
  /// deliberately does NOT depend on `_repository`: logout switches to a fresh
  /// empty account, so by the time anything reads the block list it's already
  /// empty and the previous account's still-armed alarms would be unreachable.
  ///
  /// The native Vibrator alarms are keyed by notification id, which the new
  /// account can't re-derive -- so the native side keeps its own record of
  /// every armed requestCode and [_cancelAllVibrationAlarms] wipes them all
  /// from that. [knownIds] (the logging-out account's `segment.notificationIds`,
  /// read before teardown) is an extra belt-and-suspenders pass.
  Future<void> cancelEverything({Iterable<int> knownIds = const []}) async {
    final ids = {...await _cancelAllVibrationAlarms(), ...knownIds};
    for (final id in ids) {
      await _plugin.cancel(id);
    }
    await _plugin.cancelAll();
  }

  /// Cancels all native Vibrator alarms and returns their request codes
  /// (== notification ids). Empty when there's no platform channel (tests).
  Future<List<int>> _cancelAllVibrationAlarms() async {
    try {
      final result = await _alarmChannelChannel.invokeMethod('cancelAllVibrationAlarms');
      return (result as List?)?.map((e) => (e as num).toInt()).toList() ?? const [];
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('cancelAllVibrationAlarms', e);
      return const [];
    }
  }

  Future<void> _scheduleVibrationAlarm({
    required int requestCode,
    required tz.TZDateTime triggerAt,
    required Int64List pattern,
    required int durationMs,
    required Duration repeatInterval,
  }) async {
    try {
      await _alarmChannelChannel.invokeMethod('scheduleVibrationAlarm', {
        'requestCode': requestCode,
        'triggerAtMillis': triggerAt.millisecondsSinceEpoch,
        // .toList(): a typed Int64List crosses the platform channel as a
        // Java long[], which a Kotlin List<*> argument() cast can't read
        // -- a plain Dart List<int> (boxed Longs) is what ensureAlarmChannel
        // already sends the same vibration pattern as, above.
        'pattern': pattern.toList(),
        'durationMs': durationMs,
        'repeatIntervalMs': repeatInterval.inMilliseconds,
      });
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('scheduleVibrationAlarm', e);
    }
  }

}

/// Stops [id]'s alarm notification and the native Vibrator alarm riding
/// alongside it (see VibrationAlarmReceiver.kt). Shared by
/// [NotificationService.cancelNotification] (a UI screen's own 확인) and
/// [_handleResponse] (any tap on the notification itself, including the
/// fullScreenIntent auto-launch) — a closed/folded phone's cover screen can't
/// reliably render the dialog that follows a tap, so the alarm has to
/// actually stop right there rather than wait on reaching 확인 inside it.
Future<void> _silenceAlarm(int id) async {
  await _plugin.cancel(id);
  try {
    await _alarmChannelChannel.invokeMethod('cancelVibrationAlarm', {
      'requestCode': id,
    });
  } catch (e) {
    // No platform channel available (e.g. under flutter test).
    logSwallowed('cancelVibrationAlarm', e);
  }
}

/// What alarm notification was tapped (or full-screen-launched) for, picked up
/// by [App]'s alarm-alert launcher once the Navigator is ready (see app.dart)
/// — a [ValueNotifier] rather than calling `Navigator.push`/`showDialog`
/// straight from here since this can fire before the widget tree exists yet
/// (cold start).
class PendingAlarmAlert {
  const PendingAlarmAlert({
    required this.notificationId,
    required this.segmentId,
  });

  final int notificationId;
  final String segmentId;
}

final ValueNotifier<PendingAlarmAlert?> pendingAlarmAlert = ValueNotifier(null);

/// Foreground (or background-but-alive) notification tap handler.
void handleNotificationResponse(NotificationResponse response) {
  _handleResponse(response);
}

/// True background entry point: Android may run this in a fresh isolate with no
/// app state, so it must be a top-level function. Required by
/// flutter_local_notifications for taps that arrive while the app is killed.
@pragma('vm:entry-point')
void handleNotificationResponseBackground(NotificationResponse response) {
  _handleResponse(response);
}

// The notifications carry no action buttons (see _androidDetailsFor), so this
// only ever handles a plain body-tap or the system auto-launching the app via
// fullScreenIntent. Either way the tap itself already silences the alarm --
// AlarmAlertDialog (popped by App's launcher picking up the pending alert
// below) is then just the review/confirm step into Focus, not the thing that
// stops the buzzing. That matters most exactly when it's least reachable: a
// closed/folded phone's cover screen may never render the dialog properly,
// but the tap that got this far always fires.
void _handleResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;
  final parts = payload.split(':');
  if (parts.length != 2 || parts[0] != 'block') return;
  final id = response.id;
  if (id == null) return;
  unawaited(_silenceAlarm(id));
  pendingAlarmAlert.value = PendingAlarmAlert(
    notificationId: id,
    segmentId: parts[1],
  );
}
