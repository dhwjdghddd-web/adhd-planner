import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../core/time_geometry.dart';
import '../data/models/completion.dart';
import '../data/models/routine.dart';
import '../data/providers.dart';
import '../data/repositories/firestore/firestore_planner_repository.dart';
import '../data/repositories/planner_repository.dart';
import '../firebase_options.dart';

const _routineChannelId = 'routine';
const _routineChannelName = '루틴 알람';
const _transitionChannelId = 'transition';
const _transitionChannelName = '전환 예고';
const _actionSnooze = 'snooze';
const _actionComplete = 'complete';

final _plugin = FlutterLocalNotificationsPlugin();

final notificationServiceProvider = Provider<NotificationService>(
  (ref) => NotificationService(ref.read(plannerRepositoryProvider)),
);

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

  String get channelId => isTransition ? _transitionChannelId : _routineChannelId;
  String get payload => '${isTransition ? 'transition' : 'main'}:$routineId';
}

/// Deterministic notification id for a (routine, weekday, slot) triple, so a
/// later `cancelAll` + reschedule always replaces exactly what it created
/// before. slot 0 = main alarm, 1 = transition warning, 2 = one-off snooze.
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

AndroidNotificationDetails _androidDetailsFor(ScheduledSpec spec) {
  if (spec.isTransition) {
    return const AndroidNotificationDetails(
      _transitionChannelId,
      _transitionChannelName,
      importance: Importance.defaultImportance,
      priority: Priority.defaultPriority,
    );
  }
  return const AndroidNotificationDetails(
    _routineChannelId,
    _routineChannelName,
    importance: Importance.max,
    priority: Priority.high,
    actions: [
      AndroidNotificationAction(_actionSnooze, '스누즈'),
      AndroidNotificationAction(_actionComplete, '완료'),
    ],
  );
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

    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _routineChannelId,
      _routineChannelName,
      description: '루틴 시작 시각에 울리는 알람',
      importance: Importance.max,
    ));
    await android?.createNotificationChannel(const AndroidNotificationChannel(
      _transitionChannelId,
      _transitionChannelName,
      description: '루틴 시작 전 미리 알려주는 예고',
      importance: Importance.defaultImportance,
    ));

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
  Future<bool> requestPermissions() async {
    final android =
        _plugin.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    final notifications = await android?.requestNotificationsPermission();
    final exactAlarms = await android?.requestExactAlarmsPermission();
    return (notifications ?? true) && (exactAlarms ?? true);
  }

  /// Cancels every previously scheduled alarm and re-schedules exactly the
  /// ones [routines] now call for, then persists each routine's fresh
  /// notification ids (for later cancellation/debugging).
  Future<void> rescheduleAll(List<Routine> routines) async {
    await _plugin.cancelAll();

    final specs = buildSchedule(routines);
    for (final spec in specs) {
      await _plugin.zonedSchedule(
        spec.id,
        spec.title,
        spec.body,
        nextInstanceOf(spec.isoWeekday, spec.minuteOfDay),
        NotificationDetails(android: _androidDetailsFor(spec)),
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
}

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
  if (parts.length != 2 || parts[0] == 'transition') return;
  final routineId = parts[1];

  if (response.actionId == _actionSnooze) {
    await _handleSnooze(routineId);
  } else if (response.actionId == _actionComplete) {
    await _handleComplete(routineId);
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

Future<void> _handleSnooze(String routineId) async {
  final uid = await _resolveUid();
  if (uid == null) return;
  final repository = FirestorePlannerRepository(uid);
  final routine = await _findRoutine(repository, routineId);
  if (routine == null) return;

  tz_data.initializeTimeZones();
  final fireAt = tz.TZDateTime.now(tz.local).add(Duration(minutes: routine.snoozeMin));
  await _plugin.zonedSchedule(
    notificationIdFor(routine.id, 0, 2),
    routine.title,
    '스누즈: 다시 알려드려요',
    fireAt,
    NotificationDetails(android: _androidDetailsFor(ScheduledSpec(
      id: 0,
      routineId: routine.id,
      isTransition: false,
      isoWeekday: 0,
      minuteOfDay: 0,
      title: routine.title,
      body: '',
    ))),
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    payload: 'main:${routine.id}',
  );
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
