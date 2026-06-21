import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:intl/intl.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/debug_log.dart';
import '../core/time_geometry.dart';
import '../data/models/app_settings.dart';
import '../data/models/routine.dart';
import '../data/models/routine_postponement.dart';
import '../data/models/routine_skip.dart';
import '../data/providers.dart';
import '../data/repositories/planner_repository.dart';

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

final notificationServiceProvider = Provider<NotificationService>((ref) {
  // uid가 null인 순간(signOut ↔ signInAnonymously 사이)에는 repo가 null.
  // NotificationService는 null repo로도 생성 가능하며, 실제 사용 시 !로 단언.
  return NotificationService(ref.watch(plannerRepositoryProvider));
});

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

/// [nextInstanceOf], but pushed a further week ahead when [routineId] has
/// been skipped ("넘기기") for today and the naive next-instance would
/// otherwise land on today -- see [NotificationService.rescheduleAll]'s
/// doc comment for why this matters (without it, the very next
/// rescheduleAll before today's original time passes would immediately
/// resurrect the skip).
tz.TZDateTime _nextInstanceRespectingSkip(
  int isoWeekday,
  int minuteOfDay,
  String routineId,
  Set<String> skippedTodayRoutineIds,
) {
  final candidate = nextInstanceOf(isoWeekday, minuteOfDay);
  if (!skippedTodayRoutineIds.contains(routineId)) return candidate;
  final now = tz.TZDateTime.now(tz.local);
  final isToday = candidate.year == now.year &&
      candidate.month == now.month &&
      candidate.day == now.day;
  return isToday ? candidate.add(const Duration(days: 7)) : candidate;
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
      // Tapping the body must not silently stop the sound/vibration before
      // the alert dialog's own 확인/미루기/넘기기 is pressed -- autoCancel's
      // default (true) would dismiss (and so stop) it right on tap.
      autoCancel: false,
      // No action buttons by design: every alarm interaction goes through
      // AlarmAlertDialog (auto-popped in the foreground, fullScreenIntent /
      // body-tap otherwise), which is the only path that reliably stops the
      // separate native Vibrator alarm too. A notification action button
      // taps in a background isolate that can't reach the native channel,
      // so it would leave the vibration running -- and a '완료' button there
      // would record a completion, which the redesigned 확인 deliberately
      // does not (completion is an explicit Focus-screen action).
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
    // Same reasoning as the transition channel above.
    autoCancel: false,
    timeoutAfter: _mainAlarmRepeatMs,
    // Pops AlarmAlertDialog over the lock screen like a real alarm clock,
    // rather than waiting for the user to pull down the shade and tap it.
    // May also help with OneUI's "무음" ringer mode suppressing vibration
    // on an ordinary notification even with USAGE_ALARM set — unconfirmed,
    // worth re-checking once this ships.
    fullScreenIntent: true,
    // No action buttons -- see the transition channel's comment above.
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
/// defaults to UTC, and a fresh background isolate (a notification action
/// tapped while the app was killed, see `_handlePostpone`/
/// `_handleComplete` below) starts with none of `main()`'s setup, [init]
/// included. Missing this in [postpone] specifically caused 미루기 to
/// reschedule things 9 hours off in KST.
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

/// Local alarm scheduling: the main alarm at a routine's start time, a
/// transition warning before it, and snooze/complete actions on the alarm
/// notification itself. Works while the app is closed — Android replays
/// scheduled alarms via the plugin's own boot receiver (see
/// AndroidManifest.xml), and notification action taps are handled by the
/// top-level [handleNotificationResponse] below even if the app process was
/// killed.
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
    final repo = _repository;
    if (repo == null) return; // auth 전환 중 — 알람 재스케줄 건너뜀
    await _ensureChannels(settings);

    // 현재 등록된 모든 알림 ID를 읽어 flutter_local_notifications와 함께
    // 네이티브 AlarmManager 진동 알람도 취소한다.
    // _plugin.cancelAll()만으로는 Dart 레벨 알림만 취소되고, VibrationAlarmReceiver가
    // 매주 스스로 재등록하는 AlarmManager 알람은 취소되지 않는다.
    // 특히 Firestore 데이터가 초기화(로그아웃 등)된 경우 routines 목록이 비어 있어
    // cancelRoutineAlarms를 호출할 수 없으므로, 여기서 반드시 처리해야 한다.
    final pending = await _plugin.pendingNotificationRequests();
    for (final n in pending) {
      await _cancelVibrationAlarm(n.id);
    }
    // Firestore에 저장된 notificationIds로도 진동 알람 취소.
    // pendingNotificationRequests는 아직 발동 전인 알림만 반환하므로,
    // 이미 울린 후 AlarmManager가 재등록한 진동 알람은 여기서 취소한다.
    for (final routine in routines) {
      for (final id in routine.notificationIds) {
        await _cancelVibrationAlarm(id);
      }
    }
    await _plugin.cancelAll();

    // Routines skipped ("넘기기") for today: without this, the very next
    // rescheduleAll (app start, any routine/settings edit) before today's
    // original time has passed would immediately resurrect the skip, since
    // nextInstanceOf just finds the next time at/after now -- which is
    // still today. See _nextInstanceRespectingSkip.
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final skips = await repo.watchRoutineSkips().first;
    final skippedTodayRoutineIds = {
      for (final s in skips)
        if (s.dateKey == dateKey) s.routineId,
    };

    final specs = buildSchedule(routines);
    for (final spec in specs) {
      final triggerAt = _nextInstanceRespectingSkip(
        spec.isoWeekday,
        spec.minuteOfDay,
        spec.routineId,
        skippedTodayRoutineIds,
      );
      await _plugin.zonedSchedule(
        spec.id,
        spec.title,
        spec.body,
        triggerAt,
        NotificationDetails(android: _androidDetailsFor(spec, settings)),
        uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
        // alarmClock (AlarmManager.setAlarmClock under the hood), not just
        // exactAllowWhileIdle: Samsung OneUI's "무음" ringer mode appears
        // to suppress vibration on a plain notification even with
        // USAGE_ALARM set on its channel, but alarms registered this way
        // get the same "real alarm clock" treatment as the stock clock
        // app's alarms -- bypassing ringer mode/DND. Trade-off: a
        // permanent alarm-clock icon shows in the status bar whenever one
        // of these is pending, same as any other alarm app.
        androidScheduleMode: AndroidScheduleMode.alarmClock,
        matchDateTimeComponents: DateTimeComponents.dayOfWeekAndTime,
        payload: spec.payload,
      );
      // The notification's own vibration is what 무음 ringer mode silences
      // (see VibrationAlarmReceiver.kt) -- this directly-triggered Vibrator
      // call alongside it is the part that actually buzzes in that mode.
      // Re-arms itself weekly on the native side, so it stays in sync with
      // matchDateTimeComponents above without Dart needing to be running.
      await _scheduleVibrationAlarm(
        requestCode: spec.id,
        triggerAt: triggerAt,
        pattern: vibrationPatternFor(settings.vibrationPattern),
        durationMs: spec.isTransition ? _transitionRepeatMs : _mainAlarmRepeatMs,
        repeatInterval: const Duration(days: 7),
      );
    }

    final idsByRoutine = <String, List<int>>{};
    for (final spec in specs) {
      idsByRoutine.putIfAbsent(spec.routineId, () => []).add(spec.id);
    }
    for (final routine in routines) {
      final ids = idsByRoutine[routine.id] ?? const <int>[];
      await repo.upsertRoutine(routine.copyWith(notificationIds: ids));
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
    final repo = _repository;
    if (repo == null) return; // auth 전환 중
    final routine = await _findRoutine(repo, routineId);
    if (routine == null) return;

    await _ensureLocalTimezone();
    final now = tz.TZDateTime.now(tz.local);
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());

    final postponements = await repo.watchRoutinePostponements().first;
    var currentOffset = 0;
    for (final p in postponements) {
      if (p.routineId == routine.id && p.dateKey == dateKey) {
        currentOffset = p.offsetMinutes;
        break;
      }
    }
    final newOffset = currentOffset + routine.snoozeMin;
    await repo.saveRoutinePostponement(
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
          // alarmClock (AlarmManager.setAlarmClock under the hood), not just
        // exactAllowWhileIdle: Samsung OneUI's "무음" ringer mode appears
        // to suppress vibration on a plain notification even with
        // USAGE_ALARM set on its channel, but alarms registered this way
        // get the same "real alarm clock" treatment as the stock clock
        // app's alarms -- bypassing ringer mode/DND. Trade-off: a
        // permanent alarm-clock icon shows in the status bar whenever one
        // of these is pending, same as any other alarm app.
        androidScheduleMode: AndroidScheduleMode.alarmClock,
          payload: 'transition:${routine.id}',
        );
        await _scheduleVibrationAlarm(
          requestCode: notificationIdFor(routine.id, 0, 3),
          triggerAt: warnAt,
          pattern: vibrationPatternFor(settings.vibrationPattern),
          durationMs: _transitionRepeatMs,
          repeatInterval: Duration.zero,
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
      androidScheduleMode: AndroidScheduleMode.alarmClock,
      payload: 'main:${routine.id}',
    );
    await _scheduleVibrationAlarm(
      requestCode: notificationIdFor(routine.id, 0, 2),
      triggerAt: mainAt,
      pattern: vibrationPatternFor(settings.vibrationPattern),
      durationMs: _mainAlarmRepeatMs,
      repeatInterval: Duration.zero,
    );
  }

  /// "넘기기": removes today's occurrence of [routineId] from consideration
  /// entirely -- it won't show as 지금/다음 anywhere today (see
  /// `excludeTodaysSkips`) and reappears normally on its next scheduled day.
  /// Unlike 미루기 (shifts today's time) or 완료 (marks today's occurrence
  /// done), this is "don't bother me with this today at all".
  ///
  /// Slot 2/3 (미루기's one-off reschedules for today) are always safe to
  /// cancel outright. Slot 0/1 (the permanent weekly recurrence) are only
  /// cancelled while today's occurrence genuinely hasn't fired yet -- once
  /// it has, the recurring chain (flutter_local_notifications' own
  /// matchDateTimeComponents handling, and VibrationAlarmReceiver alongside
  /// it) has already self-rescheduled itself to *next* week, so cancelling
  /// now would wrongly kill that instead of today's (already-fired, nothing
  /// left to cancel) occurrence.
  Future<void> skipToday(String routineId) async {
    final routine = await _findRoutine(_repository, routineId);
    if (routine == null) return;

    final now = DateTime.now();
    final dateKey = DateFormat('yyyy-MM-dd').format(now);
    await _repository!.saveRoutineSkip(RoutineSkip(dateKey: dateKey, routineId: routineId));

    // Slot 2/3 (today's one-off 미루기 reschedules) are always safe to cancel.
    await cancelNotification(notificationIdFor(routine.id, 0, 2));
    await cancelNotification(notificationIdFor(routine.id, 0, 3));

    // Slot 0/1 (the permanent weekly recurrence): only cancel an occurrence
    // that genuinely hasn't fired yet today. Once an occurrence fires it
    // self-reschedules to next week, so cancelling it then would wrongly
    // kill next week's, not today's (already-fired) one.
    final nowMinute = now.hour * 60 + now.minute;
    final today = now.weekday;
    if (routine.startMinute > nowMinute) {
      await cancelNotification(notificationIdFor(routine.id, today, 0));
    }
    // The transition (slot 1) fires at startMinute - leadWarningMin, *earlier*
    // than the main alarm, so it has to be checked against its own time, not
    // the main's -- otherwise, in the window between the transition and the
    // main start, this would cancel a slot-1 alarm that already fired and
    // rescheduled itself to next week. Restricted to the non-midnight-
    // wrapping case (transition later today AND before the main): a wrapped
    // transition (transitionMinute > startMinute) fired the previous evening
    // and is likewise already rescheduled, so it's left alone.
    if (routine.leadWarningMin > 0) {
      final transitionMinute =
          (routine.startMinute - routine.leadWarningMin) % TimeGeometry.minutesPerDay;
      if (transitionMinute > nowMinute && transitionMinute < routine.startMinute) {
        await cancelNotification(notificationIdFor(routine.id, today, 1));
      }
    }
  }

  /// Dismisses a still-showing notification outright — needed when a UI
  /// screen (rather than tapping the notification's own action) handles
  /// 확인/미루기, since the insistently-repeating alarm notification has to
  /// be cancelled manually to actually stop the sound. Also stops (and
  /// un-arms) this id's directly-triggered Vibrator call alongside it --
  /// see VibrationAlarmReceiver.kt -- since that one keeps buzzing on its
  /// own timer independently of the notification.
  Future<void> cancelNotification(int id) async {
    await _plugin.cancel(id);
    await _cancelVibrationAlarm(id);
  }

  /// Cancels every still-armed notification (and the Vibrator alarm
  /// riding alongside each) for a routine that's about to be deleted.
  /// `rescheduleAll`'s own `cancelAll` only clears flutter_local_
  /// notifications' side -- a deleted routine is gone from the routine
  /// list it rebuilds from, so without this its still-armed Vibrator
  /// alarms (see VibrationAlarmReceiver.kt, which re-arms itself weekly
  /// on the native side) would otherwise keep buzzing on their own
  /// forever with nothing left to silence them.
  Future<void> cancelRoutineAlarms(Routine routine) async {
    for (final id in routine.notificationIds) {
      await cancelNotification(id);
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

  Future<void> _cancelVibrationAlarm(int requestCode) async {
    try {
      await _alarmChannelChannel.invokeMethod('cancelVibrationAlarm', {
        'requestCode': requestCode,
      });
    } catch (e) {
      // No platform channel available (e.g. under flutter test).
      logSwallowed('cancelVibrationAlarm', e);
    }
  }
}

/// What alarm notification was tapped (or full-screen-launched) for,
/// picked up by [App]'s alarm-alert launcher once the Navigator is ready
/// (see app.dart) — a [ValueNotifier] rather than calling
/// `Navigator.push`/`showDialog` straight from here since this can fire
/// before the widget tree exists yet (cold start).
class PendingAlarmAlert {
  const PendingAlarmAlert({
    required this.notificationId,
    required this.routineId,
    required this.isTransition,
  });

  final int notificationId;
  final String routineId;
  final bool isTransition;
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

// The notifications carry no action buttons (see _androidDetailsFor), so
// this only ever handles a plain body-tap or the system auto-launching the
// app via fullScreenIntent -- both arrive as PendingIntent.getActivity in
// the main isolate, where App's launcher can safely pick up the pending
// alert. Everything the user can do (확인/미루기/넘기기) happens in
// AlarmAlertDialog, never on the notification itself.
void _handleResponse(NotificationResponse response) {
  final payload = response.payload;
  if (payload == null) return;
  final parts = payload.split(':');
  if (parts.length != 2) return;
  final isTransition = parts[0] == 'transition';
  final routineId = parts[1];
  if (response.id == null) return;
  pendingAlarmAlert.value = PendingAlarmAlert(
    notificationId: response.id!,
    routineId: routineId,
    isTransition: isTransition,
  );
}

Future<Routine?> _findRoutine(PlannerRepository? repository, String id) async {
  if (repository == null) return null;
  final routines = await repository.watchRoutines().first;
  for (final routine in routines) {
    if (routine.id == id) return routine;
  }
  return null;
}
