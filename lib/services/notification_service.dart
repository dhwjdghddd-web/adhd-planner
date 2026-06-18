import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/time_geometry.dart';
import '../data/models/app_settings.dart';
import '../data/models/completion.dart';
import '../data/models/routine.dart';
import '../data/models/routine_postponement.dart';
import '../data/providers.dart';
import '../data/repositories/firestore/firestore_planner_repository.dart';
import '../data/repositories/planner_repository.dart';
import '../firebase_options.dart';

// v3/v2: base channel ids keep getting bumped because Android notification
// channels are immutable after creation on a given install — every time a
// channel-level setting (importance, sound, vibration) changes, anyone with
// the app already installed would keep the old behavior forever unless the
// id changes too. The sound/vibration choice itself (STEP 12+) is encoded
// into the id as a suffix for the same reason — see _channelSuffix.
const _routineChannelBase = 'routine_v2';
const _routineChannelName = '루틴 알람';
const _transitionChannelBase = 'transition_v3';
const _transitionChannelName = '전환 예고';
const _actionPostpone = 'postpone';
const _actionComplete = 'complete';

// USAGE_ALARM is what makes these ring/vibrate through the alarm stream
// instead of the notification stream — the same reason a normal alarm clock
// app still goes off when the phone's ringer is set to silent or vibrate.
// (This does not override a user-enabled Do Not Disturb, which needs a
// separate, more invasive "DND access" permission grant — out of scope
// unless that turns out to still be a problem.)
const _alarmAudioUsage = AudioAttributesUsage.alarm;
const _alarmCategory = AndroidNotificationCategory.alarm;
// Notification.FLAG_INSISTENT (not exposed as a named constant by the
// plugin): repeats the sound/vibration on a loop for as long as the
// notification exists, rather than alerting once and going quiet.
final _insistentFlag = Int32List.fromList([4]);
// 2x one vibration cycle — a noticeably longer nudge than before, but still
// just a heads-up, not something that needs to keep demanding attention
// indefinitely.
final _transitionRepeatMs = _vibrationCycleMs(AlarmVibrationPattern.defaultPattern) * 2;
// Repeats for a full minute, then the system cancels it on its own even if
// the app isn't running — no snooze/dismiss needed for it to eventually
// stop on its own.
const _mainAlarmRepeatMs = 60000;

final _plugin = FlutterLocalNotificationsPlugin();

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.read(plannerRepositoryProvider)),
);

/// The actual millisecond vibration pattern for each named preset in
/// [AlarmVibrationPattern] — `[pause, on, off, on, off, ...]`, same
/// convention as `Vibrator.vibrate(long[])`.
Int64List vibrationPatternFor(AlarmVibrationPattern preset) {
  switch (preset) {
    case AlarmVibrationPattern.defaultPattern:
      return Int64List.fromList([0, 1000, 500, 1000, 500, 1000, 500, 1000]);
    case AlarmVibrationPattern.short:
      return Int64List.fromList([0, 300, 200, 300, 200, 300, 200, 300, 200, 300]);
    case AlarmVibrationPattern.long:
      return Int64List.fromList([0, 2000, 1000, 2000, 1000, 2000]);
    case AlarmVibrationPattern.doublePulse:
      return Int64List.fromList([0, 250, 150, 250, 600, 250, 150, 250, 600]);
  }
}

int _vibrationCycleMs(AlarmVibrationPattern preset) =>
    vibrationPatternFor(preset).fold(0, (sum, ms) => sum + ms);

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
// constants. Stable for a given (sound, pattern) pair, so switching back to
// a combination tried before reuses that channel instead of piling up new
// ones forever.
String _channelSuffix(AppSettings settings) {
  final soundKey = (settings.alarmSoundUri ?? 'default').hashCode.toUnsigned(20).toRadixString(36);
  return '${soundKey}_${settings.vibrationPattern.name}';
}

String _routineChannelId(AppSettings settings) => '${_routineChannelBase}_${_channelSuffix(settings)}';

String _transitionChannelId(AppSettings settings) =>
    '${_transitionChannelBase}_${_channelSuffix(settings)}';

/// One concrete alarm that should exist on the device: a single weekday
/// occurrence of either a routine's main alarm or its transition warning.
/// Kept as a plain value (rather than calling the plugin while iterating
/// routines) so [buildSchedule] — the "which alarms should exist" logic —
/// is unit-testable without a real Android runtime.
class ScheduledSpec {
  const ScheduledSpec({
    required this.id,
    required this.routineId,
    required this.isTransition,
    required this.isoWeekday,
    required this.minuteOfDay,
    required this.title,
    required this.body,
  });

  final int id;
  final String routineId;
  final bool isTransition;
  final int isoWeekday;
  final int minuteOfDay;
  final String title;
  final String body;

  String get payload => '${isTransition ? 'transition' : 'main'}:$routineId';
}

/// Deterministic notification id for a (routine, weekday, slot) triple, so a
/// later `cancelAll` + reschedule always replaces exactly what it created
/// before. slot 0 = main alarm, 1 = transition warning, 2 = one-off 미루기
/// reschedule of the main alarm, 3 = one-off 미루기 reschedule of the
/// transition warning.
int notificationIdFor(String routineId, int isoWeekday, int slot) {
  final base = routineId.hashCode.abs() % 100000;
  return base * 100 + isoWeekday * 10 + slot;
}

/// Pure: turns the current routine list into the exact set of alarms that
/// should exist on the device. No plugin calls here — [NotificationService
/// .rescheduleAll] is the thin layer that applies this via
/// `flutter_local_notifications`.
List<ScheduledSpec> buildSchedule(List<Routine> routines) {
  final specs = <ScheduledSpec>[];
  for (final routine in routines) {
    if (!routine.alarmEnabled) continue;
    final days = routine.repeatDays.isEmpty
        ? const [1, 2, 3, 4, 5, 6, 7]
        : routine.repeatDays;
    for (final day in days) {
      specs.add(ScheduledSpec(
        id: notificationIdFor(routine.id, day, 0),
        routineId: routine.id,
        isTransition: false,
        isoWeekday: day,
        minuteOfDay: routine.startMinute,
        title: routine.title,
        body: '지금 시작할 시간이에요',
      ));
      if (routine.leadWarningMin > 0) {
        specs.add(ScheduledSpec(
          id: notificationIdFor(routine.id, day, 1),
          routineId: routine.id,
          isTransition: true,
          isoWeekday: day,
          minuteOfDay:
              (routine.startMinute - routine.leadWarningMin) % TimeGeometry.minutesPerDay,
          title: '곧 전환: ${routine.title}',
          body: '${routine.leadWarningMin}분 후 시작해요',
        ));
      }
    }
  }
  return specs;
}

/// Next moment (today or later) that lands on [isoWeekday] (1=Mon..7=Sun) at
/// [minuteOfDay], in the local timezone. Used as the anchor for a weekly
/// recurring `zonedSchedule`.
tz.TZDateTime nextInstanceOf(int isoWeekday, int minuteOfDay) {
  final now = tz.TZDateTime.now(tz.local);
  var scheduled = tz.TZDateTime(
    tz.local, now.year, now.month, now.day, minuteOfDay ~/ 60, minuteOfDay % 60,
  );
  while (scheduled.weekday != isoWeekday || !scheduled.isAfter(now)) {
    scheduled = scheduled.add(const Duration(days: 1));
  }
  return scheduled;
}

/// Next moment at [minuteOfDay] strictly after [now], regardless of
/// weekday — used for one-off 미루기 reschedules, which only ever care
/// about "later today" (or, for a minuteOfDay that's already passed
/// today, the same clock time tomorrow rather than firing immediately).
tz.TZDateTime _todayAt(tz.TZDateTime now, int minuteOfDay) {
  var candidate = tz.TZDateTime(
    tz.local, now.year, now.month, now.day, minuteOfDay ~/ 60, minuteOfDay % 60,
  );
  if (!candidate.isAfter(now)) candidate = candidate.add(const Duration(days: 1));
  return candidate;
}

AndroidNotificationDetails _androidDetailsFor(ScheduledSpec spec, AppSettings settings) {
  final sound = _soundFor(settings);
  final vibrationPattern = vibrationPatternFor(settings.vibrationPattern);

  if (spec.isTransition) {
    // high (not just defaultImportance): IMPORTANCE_DEFAULT shows in the
    // shade with sound but never pops up as a heads-up banner or reliably
    // vibrates — exactly the "I had to pull down the shade to notice it"
    // complaint this fixes. One notch below the main alarm's max, since
    // there's no 완료 here (nothing to mark done yet), only 미루기.
    return AndroidNotificationDetails(
      _transitionChannelId(settings),
      _transitionChannelName,
      importance: Importance.high,
      priority: Priority.high,
      enableVibration: true,
      vibrationPattern: vibrationPattern,
      sound: sound,
      audioAttributesUsage: _alarmAudioUsage,
      category: _alarmCategory,
      additionalFlags: _insistentFlag,
      timeoutAfter: _transitionRepeatMs,
      actions: const [
        AndroidNotificationAction(_actionPostpone, '미루기'),
      ],
    );
  }
  return AndroidNotificationDetails(
    _routineChannelId(settings),
    _routineChannelName,
    importance: Importance.max,
    priority: Priority.high,
    enableVibration: true,
    vibrationPattern: vibrationPattern,
    sound: sound,
    audioAttributesUsage: _alarmAudioUsage,
    category: _alarmCategory,
    additionalFlags: _insistentFlag,
    timeoutAfter: _mainAlarmRepeatMs,
    // Pops AlarmAlertDialog over the lock screen like a real alarm clock,
    // rather than waiting for the user to pull down the shade and tap it.
    // May also help with OneUI's "무음" ringer mode suppressing vibration
    // on an ordinary notification even with USAGE_ALARM set — unconfirmed,
    // worth re-checking once this ships.
    fullScreenIntent: true,
    actions: const [
      AndroidNotificationAction(_actionPostpone, '미루기'),
      AndroidNotificationAction(_actionComplete, '완료'),
    ],
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

/// Creates (or, for a combination already seen before, reuses) the two
/// channels for [settings]'s current sound+vibration choice. Safe to call
/// every time alarms are rescheduled — creating a channel that already
/// exists with that exact id is a no-op.
Future<void> _ensureChannels(AppSettings settings) async {
  final soundUri = settings.alarmSoundUri ?? 'content://settings/system/alarm_alert';
  final vibrationPattern = vibrationPatternFor(settings.vibrationPattern);
  try {
    await _alarmChannelChannel.invokeMethod('ensureAlarmChannel', {
      'id': _routineChannelId(settings),
      'name': _routineChannelName,
      'description': '루틴 시작 시각에 울리는 알람',
      'importance': Importance.max.value,
      'soundUri': soundUri,
      // .toList() rather than the raw Int64List: a plain Dart List always
      // arrives as a Java/Kotlin List via the standard method codec, which
      // is what MainActivity.kt's handler expects — a typed list like
      // Int64List instead maps to a raw long[], a different shape.
      'vibrationPattern': vibrationPattern.toList(),
    });
    await _alarmChannelChannel.invokeMethod('ensureAlarmChannel', {
      'id': _transitionChannelId(settings),
      'name': _transitionChannelName,
      'description': '루틴 시작 전 미리 알려주는 예고',
      'importance': Importance.high.value,
      'soundUri': soundUri,
      'vibrationPattern': vibrationPattern.toList(),
    });
  } catch (_) {
    // No such platform channel (iOS, flutter test). The plugin's own
    // zonedSchedule call below will fall back to creating an ordinary
    // channel itself — sound still works there, just not the silent-mode
    // vibration bypass.
  }
}

/// Local alarm scheduling: the main alarm at a routine's start time, a
/// transition warning before it, and snooze/complete actions on the alarm
/// notification itself. Works while the app is closed — Android replays
/// scheduled alarms via the plugin's own boot receiver (see
/// AndroidManifest.xml), and notification action taps are handled by the
/// top-level [handleNotificationResponse] below even if the app process was
/// killed.
class NotificationService {
  NotificationService(this._repository);

  final PlannerRepository _repository;

  Future<void> init() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    await _plugin.initialize(
      const InitializationSettings(android: androidInit),
      onDidReceiveNotificationResponse: handleNotificationResponse,
      onDidReceiveBackgroundNotificationResponse: handleNotificationResponseBackground,
    );

    tz_data.initializeTimeZones();
    try {
      final localTz = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localTz.identifier));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }
  }

  /// Requests POST_NOTIFICATIONS (Android 13+) and the exact-alarm
  /// permission (Android 12+). Returns false if either was denied so the
  /// caller can surface a settings-screen nudge (STEP 12).
  ///
  /// Also asks for the full-screen-intent permission the main alarm uses to
  /// pop the alarm-alert screen over the lock screen (Android 14+ can ship
  /// this denied by default) — not folded into the return value since the
  /// alarm still works as an ordinary notification without it, just without
  /// the full-screen takeover.
  Future<bool> requestPermissions() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final notifications = await android?.requestNotificationsPermission();
    final exactAlarms = await android?.requestExactAlarmsPermission();
    await android?.requestFullScreenIntentPermission();
    return (notifications ?? true) && (exactAlarms ?? true);
  }

  /// Cancels every previously scheduled alarm and re-schedules exactly the
  /// ones [routines] now call for, using [settings]'s current sound and
  /// vibration choice. Call this again (with the same routines) whenever
  /// that choice changes so it takes effect immediately rather than next
  /// app start.
  Future<void> rescheduleAll(List<Routine> routines, AppSettings settings) async {
    await _ensureChannels(settings);
    await _plugin.cancelAll();

    final specs = buildSchedule(routines);
    for (final spec in specs) {
      await _plugin.zonedSchedule(
        spec.id,
        spec.title,
        spec.body,
        nextInstanceOf(spec.isoWeekday, spec.minuteOfDay),
        NotificationDetails(android: _androidDetailsFor(spec, settings)),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: spec.payload,
      );
    }

    final idsByRoutine = <String, List<int>>{};
    for (final spec in specs) {
      idsByRoutine.putIfAbsent(spec.routineId, () => []).add(spec.id);
    }
    for (final routine in routines) {
      final ids = idsByRoutine[routine.id] ?? const <int>[];
      await _repository.upsertRoutine(routine.copyWith(notificationIds: ids));
    }
  }

  /// "미루기": pushes today's effective start time for the routine
  /// identified by [routineId] forward by its `snoozeMin` from wherever
  /// today's cumulative postponement currently sits — pressed on either the
  /// lead-warning or the main alarm, repeated presses stack (5+5=10 min,
  /// etc). Takes an id rather than a [Routine] and always re-reads it from
  /// the repository: callers (PlannerPage/FocusPage) may only be holding a
  /// *display* copy whose `startMinute` already has today's postponement
  /// overlaid on it (see `applyTodaysPostponements`), and computing the new
  /// offset against that instead of the permanent stored value would
  /// double-apply it.
  ///
  /// Persists the new offset as a [RoutinePostponement] (read by
  /// PlannerPage/FocusPage to show today's actual time, never touching the
  /// routine's permanent recurring schedule), then re-schedules today's
  /// remaining lead-warning and main alarm as one-off alerts at the new
  /// time — only the ones still in the future actually get scheduled, so
  /// postponing the main alarm itself doesn't resurrect an already-past
  /// lead-warning.
  Future<void> postpone(String routineId, AppSettings settings) async {
    final routine = await _findRoutine(_repository, routineId);
    if (routine == null) return;

    tz_data.initializeTimeZones();
    final now = tz.TZDateTime.now(tz.local);
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final postponements = await _repository.watchRoutinePostponements().first;
    var currentOffset = 0;
    for (final p in postponements) {
      if (p.routineId == routine.id && p.dateKey == dateKey) {
        currentOffset = p.offsetMinutes;
        break;
      }
    }
    final newOffset = currentOffset + routine.snoozeMin;
    await _repository.saveRoutinePostponement(
      RoutinePostponement(dateKey: dateKey, routineId: routine.id, offsetMinutes: newOffset),
    );

    await _ensureChannels(settings);
    final effectiveStart = (routine.startMinute + newOffset) % TimeGeometry.minutesPerDay;

    if (routine.leadWarningMin > 0) {
      final warnMinute =
          (effectiveStart - routine.leadWarningMin) % TimeGeometry.minutesPerDay;
      final warnAt = _todayAt(now, warnMinute);
      if (warnAt.isAfter(now)) {
        await _plugin.zonedSchedule(
          notificationIdFor(routine.id, 0, 3),
          '곧 전환: ${routine.title}',
          '${routine.leadWarningMin}분 후 시작해요',
          warnAt,
          NotificationDetails(
            android: _androidDetailsFor(
              ScheduledSpec(
                id: 0,
                routineId: routine.id,
                isTransition: true,
                isoWeekday: 0,
                minuteOfDay: 0,
                title: '곧 전환: ${routine.title}',
                body: '',
              ),
              settings,
            ),
          ),
          uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
          androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
          payload: 'transition:${routine.id}',
        );
      }
    }

    final mainAt = _todayAt(now, effectiveStart);
    await _plugin.zonedSchedule(
      notificationIdFor(routine.id, 0, 2),
      routine.title,
      '지금 시작할 시간이에요',
      mainAt,
      NotificationDetails(
        android: _androidDetailsFor(
          ScheduledSpec(
            id: 0,
            routineId: routine.id,
            isTransition: false,
            isoWeekday: 0,
            minuteOfDay: 0,
            title: routine.title,
            body: '',
          ),
          settings,
        ),
      ),
      uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: 'main:${routine.id}',
    );
  }

  /// Dismisses a still-showing notification outright — needed when a UI
  /// screen (rather than tapping the notification's own action) handles
  /// 완료/스누즈, since the insistently-repeating alarm notification has to
  /// be cancelled manually to actually stop the sound/vibration.
  Future<void> cancelNotification(int id) => _plugin.cancel(id);
}

/// What the main alarm notification was tapped (or full-screen-launched)
/// for, picked up by [App]'s alarm-alert launcher once the Navigator is
/// ready (see app.dart) — a [ValueNotifier] rather than calling
/// `Navigator.push` straight from here since this can fire before the
/// widget tree exists yet (cold start).
class PendingAlarmAlert {
  const PendingAlarmAlert({required this.notificationId, required this.routineId});

  final int notificationId;
  final String routineId;
}

final ValueNotifier<PendingAlarmAlert?> pendingAlarmAlert = ValueNotifier(null);

/// Foreground (or background-but-alive) notification tap/action handler.
void handleNotificationResponse(NotificationResponse response) {
  _handleResponse(response);
}

/// True background entry point: Android may run this in a fresh isolate
/// with no app state, so it must be a top-level function and re-open its
/// own storage. Required by flutter_local_notifications for taps that
/// arrive while the app process is fully killed.
@pragma('vm:entry-point')
void handleNotificationResponseBackground(NotificationResponse response) {
  _handleResponse(response);
}

Future<void> _handleResponse(NotificationResponse response) async {
  final payload = response.payload;
  if (payload == null) return;
  final parts = payload.split(':');
  if (parts.length != 2) return;
  final isTransition = parts[0] == 'transition';
  final routineId = parts[1];

  if (response.actionId == _actionPostpone) {
    // 미루기 is offered on both the lead-warning and the main alarm.
    await _handlePostpone(routineId);
  } else if (response.actionId == _actionComplete) {
    await _handleComplete(routineId);
  } else if (response.id != null) {
    // A plain tap, or the system auto-launching the app via
    // fullScreenIntent -- both arrive as PendingIntent.getActivity (unlike
    // the action buttons above, which are getBroadcast and so can run in
    // the background isolate this function might be on), so this always
    // runs in the main isolate and App's launcher can safely act on it.
    // Only the main alarm pops the alert dialog; tapping the lead-warning
    // notification's body is a no-op since there's nothing to act on yet.
    if (isTransition) return;
    pendingAlarmAlert.value =
        PendingAlarmAlert(notificationId: response.id!, routineId: routineId);
  }
}

// May run in a fresh background isolate with no app state (Android killed
// the process before delivering this action), so it re-initializes Firebase
// and resolves the signed-in user itself rather than assuming either is
// already set up. `Firebase.apps.isEmpty` distinguishes that case from
// running in the app's existing isolate, where re-initializing would throw
// a duplicate-app error.
Future<String?> _resolveUid() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }
  final current = FirebaseAuth.instance.currentUser;
  if (current != null) return current.uid;
  final restored = await FirebaseAuth.instance
      .authStateChanges()
      .firstWhere((u) => u != null)
      .timeout(const Duration(seconds: 5), onTimeout: () => null);
  return restored?.uid;
}

Future<void> _handlePostpone(String routineId) async {
  final uid = await _resolveUid();
  if (uid == null) return;
  final repository = FirestorePlannerRepository(uid);
  final settings = await repository.watchSettings().first;
  await NotificationService(repository).postpone(routineId, settings);
}

Future<void> _handleComplete(String routineId) async {
  final uid = await _resolveUid();
  if (uid == null) return;
  final repository = FirestorePlannerRepository(uid);
  await repository.setCompletion(Completion.now(routineId));
}

Future<Routine?> _findRoutine(PlannerRepository repository, String id) async {
  final routines = await repository.watchRoutines().first;
  for (final routine in routines) {
    if (routine.id == id) return routine;
  }
  return null;
}
