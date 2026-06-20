import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import 'core/theme.dart';
import 'core/time_geometry.dart';
import 'data/models/app_settings.dart';
import 'data/providers.dart';
import 'data/routine_status.dart';
import 'features/focus/alarm_alert_dialog.dart';
import 'features/memos/quick_add_button.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/planner/planner_page.dart';
import 'services/notification_service.dart';

/// Root widget. Theme mode and font scale follow [AppSettings] live (see
/// `settingsProvider`), so changing them in the settings screen is
/// reflected app-wide immediately. The home route is [_RootRouter], not
/// `PlannerPage`/`OnboardingPage` directly — `MaterialApp.home` only seeds
/// the Navigator's *initial* route, so deciding between them has to happen
/// inside a widget that can keep re-evaluating as settings load.
class App extends ConsumerWidget {
  const App({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).value ?? const AppSettings.defaults();

    return MaterialApp(
      title: 'ADHD Planner',
      navigatorKey: appNavigatorKey,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: _toThemeMode(settings.themeMode),
      home: const _RootRouter(),
      builder: (context, child) {
        final mediaQuery = MediaQuery.of(context);
        return MediaQuery(
          data: mediaQuery.copyWith(textScaler: TextScaler.linear(settings.fontScale)),
          child: Stack(
            children: [
              ?child,
              // snackBarVisible이 true일 동안 스낵바 높이(58 dp)만큼
              // 위로 AnimatedPadding으로 밀어올린다.
              // Scaffold FAB(루틴추가)은 fixed 모드로 자동 상승하고,
              // 전역 메모 FAB도 동일 애니메이션으로 함께 올라간다.
              ValueListenableBuilder<bool>(
                valueListenable: snackBarVisible,
                builder: (context, visible, child) => AnimatedPadding(
                  duration: const Duration(milliseconds: 250),
                  curve: visible ? Curves.easeOut : Curves.easeIn,
                  padding: EdgeInsets.only(bottom: visible ? 58.0 : 0.0),
                  child: child!,
                ),
                child: const SafeArea(
                  child: Align(
                    alignment: Alignment.bottomLeft,
                    child: Padding(
                      padding: EdgeInsets.all(16),
                      child: GlobalQuickAddButton(),
                    ),
                  ),
                ),
              ),
              const _AlarmAlertLauncher(),
              const _ForegroundAlarmWatcher(),
              const _AccountAlarmSync(),
            ],
          ),
        );
      },
    );
  }
}

/// True while [AlarmAlertDialog] is up, shared by [_AlarmAlertLauncher]
/// (the notification-tap/fullScreenIntent path) and
/// [_ForegroundAlarmWatcher] (the "app is already open" path below) so
/// they never pop two dialogs on top of each other for the same alarm.
/// Public (not `_`-prefixed) so tests can reset it between cases the same
/// way they already do for `quickAddSheetOpen`/`fabSuppressionCount`.
final ValueNotifier<bool> alarmDialogOpen = ValueNotifier(false);

void _showAlarmDialog({
  required String routineId,
  required int notificationId,
  required bool isTransition,
}) {
  if (alarmDialogOpen.value) return;
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  alarmDialogOpen.value = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlarmAlertDialog(
      routineId: routineId,
      notificationId: notificationId,
      isTransition: isTransition,
    ),
  ).whenComplete(() => alarmDialogOpen.value = false);
}

ThemeMode _toThemeMode(AppThemeMode mode) => switch (mode) {
      AppThemeMode.system => ThemeMode.system,
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
    };

/// Shows the onboarding guide once, then the circular planner home — as a
/// plain reactive widget swap rather than a Navigator push, so it keeps
/// working even before settings have finished loading the first time.
///
/// [ConsumerStatefulWidget]으로 작성해 `_lastOnboarded` 상태를 유지한다.
/// auth 전환(signOut → signInAnonymously) 중 [settingsProvider]가 잠깐
/// loading/기본값(onboardingComplete: false) 상태가 되어도 마지막으로 확인된
/// 라우팅 상태를 유지하므로, [OnboardingPage]([SuppressGlobalFab] 포함)가
/// 순간적으로 mount됐다 unmount되며 [fabSuppressionCount]가 꼬이는 현상을 방지한다.
class _RootRouter extends ConsumerStatefulWidget {
  const _RootRouter();

  @override
  ConsumerState<_RootRouter> createState() => _RootRouterState();
}

class _RootRouterState extends ConsumerState<_RootRouter> {
  /// 마지막으로 확인된 onboardingComplete 값.
  /// null이면 아직 첫 데이터를 받지 못한 것(앱 최초 로딩).
  bool? _lastOnboarded;

  @override
  Widget build(BuildContext context) {
    final settingsAsync = ref.watch(settingsProvider);

    // build 중에 직접 갱신(여분의 setState/microtask 없음).
    // auth 전환으로 settingsProvider가 loading이다가 data로 돌아오면
    // 이 build가 다시 호출되어 _lastOnboarded가 자동 유지된다.
    settingsAsync.whenData((s) => _lastOnboarded = s.onboardingComplete);

    // 컨테스트가 있으면 loading/error 구간에도 화면을 유지한다.
    // 이로써 로그아웃 시 OnboardingPage([SuppressGlobalFab] 포함)가
    // 좌대 mount/unmount되어 fabSuppressionCount가 꽔이는 현상을 방지한다.
    final onboarded = _lastOnboarded;
    if (onboarded != null) {
      return onboarded ? const PlannerPage() : const OnboardingPage();
    }

    // 케시 없음 = 앱 최초 로딩.
    return settingsAsync.when(
      data: (s) => s.onboardingComplete ? const PlannerPage() : const OnboardingPage(),
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('오류: $e'))),
    );
  }
}

/// No visual presence of its own — just watches [pendingAlarmAlert] (set by
/// notification_service.dart whenever the main alarm notification is
/// tapped, including the system auto-launching the app via
/// fullScreenIntent) and pops up [AlarmAlertDialog] once the Navigator
/// actually exists. A plain callback from the notification handler can't
/// show the dialog directly: on a cold start, that handler can fire before
/// `runApp()`'s widget tree — and therefore [appNavigatorKey] — is ready.
class _AlarmAlertLauncher extends StatefulWidget {
  const _AlarmAlertLauncher();

  @override
  State<_AlarmAlertLauncher> createState() => _AlarmAlertLauncherState();
}

class _AlarmAlertLauncherState extends State<_AlarmAlertLauncher> {
  @override
  void initState() {
    super.initState();
    pendingAlarmAlert.addListener(_openIfPending);
    // Covers a pending value that arrived before this widget was even
    // built (e.g. a cold start where the notification response callback
    // fired during main(), before runApp()).
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfPending());
  }

  void _openIfPending() {
    final pending = pendingAlarmAlert.value;
    if (pending == null) return;
    if (appNavigatorKey.currentContext == null) return;
    pendingAlarmAlert.value = null;
    _showAlarmDialog(
      routineId: pending.routineId,
      notificationId: pending.notificationId,
      isTransition: pending.isTransition,
    );
  }

  @override
  void dispose() {
    pendingAlarmAlert.removeListener(_openIfPending);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pops [AlarmAlertDialog] on its own, without waiting for a notification
/// tap, whenever a routine's main alarm time arrives while this app is
/// already the one on screen — checked once a second (cheap: just a
/// minute-of-day comparison) but only acted on once per actual minute
/// change, so a routine's start time only ever opens the dialog once. The
/// underlying notification still fires too (so the alarm still works when
/// the app isn't in the foreground); this just means whoever's already
/// looking at the app doesn't have to notice and tap a heads-up banner
/// first.
class _ForegroundAlarmWatcher extends ConsumerStatefulWidget {
  const _ForegroundAlarmWatcher();

  @override
  ConsumerState<_ForegroundAlarmWatcher> createState() => _ForegroundAlarmWatcherState();
}

class _ForegroundAlarmWatcherState extends ConsumerState<_ForegroundAlarmWatcher> {
  Timer? _ticker;
  int? _lastCheckedMinuteOfDay;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _check());
  }

  void _check() {
    final now = DateTime.now();
    final minuteOfDay = now.hour * 60 + now.minute;
    if (minuteOfDay == _lastCheckedMinuteOfDay) return;
    _lastCheckedMinuteOfDay = minuteOfDay;

    final routines = ref.read(routinesProvider).value;
    if (routines == null) return;
    final postponements = ref.read(routinePostponementsProvider).value ?? const [];
    final skips = ref.read(routineSkipsProvider).value ?? const [];
    // excludeTodaysSkips so a routine the user already 넘기기'd today doesn't
    // still auto-pop the dialog at its original time -- skipToday cancels
    // its OS notification, but this foreground watcher is a separate path
    // and would otherwise fire on the bare startMinute match regardless.
    final effective = excludeTodaysSkips(
      applyTodaysPostponements(routines, postponements, now: now),
      skips,
      now: now,
    );
    final dateKey = DateFormat('yyyy-MM-dd').format(now);

    for (final routine in effective) {
      if (!routine.alarmEnabled) continue;
      if (!routine.occursOn(now.weekday)) continue;
      // A 미루기'd routine's alarms were re-scheduled as one-off slot
      // 2/3 notifications (see notification_service.dart's postpone()) --
      // cancelling the wrong (still-recurring slot 0/1) id here would
      // leave the real, still-showing notification (and its sound/
      // vibration) untouched even after 확인/미루기 closes this dialog.
      final postponedToday = postponements.any(
        (p) => p.routineId == routine.id && p.dateKey == dateKey && p.offsetMinutes > 0,
      );
      if (routine.startMinute == minuteOfDay) {
        _showAlarmDialog(
          routineId: routine.id,
          notificationId: postponedToday
              ? notificationIdFor(routine.id, 0, 2)
              : notificationIdFor(routine.id, now.weekday, 0),
          isTransition: false,
        );
        break; // one dialog at a time is enough even if two start the same minute
      }
      final warnMinute =
          (routine.startMinute - routine.leadWarningMin) % TimeGeometry.minutesPerDay;
      if (routine.leadWarningMin > 0 && warnMinute == minuteOfDay) {
        _showAlarmDialog(
          routineId: routine.id,
          notificationId: postponedToday
              ? notificationIdFor(routine.id, 0, 3)
              : notificationIdFor(routine.id, now.weekday, 1),
          isTransition: true,
        );
        break;
      }
    }
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// No visual presence — watches [plannerRepositoryProvider] and, whenever the
/// active account changes (익명→구글 연결로 uid가 보존되는 경우는 repo가
/// 안 바뀌므로 여긴 안 탄다; 계정 전환/복구처럼 uid가 실제로 바뀔 때만),
/// clears and reschedules every alarm under the new account. main()'s
/// initial schedule (see main.dart) covers app startup; this covers
/// switching accounts while the app is already running.
class _AccountAlarmSync extends ConsumerWidget {
  const _AccountAlarmSync();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // repo가 "바뀔 때만" 재스케줄. fireImmediately를 쓰지 않는 이유:
    //  - 초기 스케줄은 main()이 이미 한다.
    //  - 위젯 테스트는 plannerRepositoryProvider를 "고정 Fake"로 override하므로
    //    이 listener는 절대 발화하지 않는다 → 테스트가 플랫폼 채널을 안 건드림.
    //    (fireImmediately를 켜면 테스트에서 rescheduleAll→cancelAll의
    //    MissingPluginException으로 깨진다. 절대 켜지 말 것.)
    ref.listen(plannerRepositoryProvider, (prev, next) async {
      // uid가 null인 순간(signOut ↔ signInAnonymously 사이)에는 skip.
      if (next == null) return;
      if (identical(prev, next)) return;
      final routines = await next.watchRoutines().first;
      final settings = await next.watchSettings().first;
      try {
        await ref.read(notificationServiceProvider).rescheduleAll(routines, settings);
      } catch (_) {
        // 플랫폼 채널 부재(테스트 등) — 무시.
      }
    });
    return const SizedBox.shrink();
  }
}
