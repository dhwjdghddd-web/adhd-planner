import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/debug_log.dart';
import 'core/theme.dart';
import 'data/models/achieved_day.dart';
import 'data/models/app_settings.dart';
import 'data/providers.dart';
import 'data/today.dart';
import 'features/focus/alarm_alert_dialog.dart';
import 'features/memos/quick_add_button.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/planner/planner_page.dart';
import 'features/rewards/daily_achievement.dart';
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
              child!,
              const _AlarmAlertLauncher(),
              const _ForegroundAlarmWatcher(),
              const _AccountAlarmSync(),
              const _AchievementRecorder(),
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
  required String segmentId,
  required int notificationId,
}) {
  if (alarmDialogOpen.value) return;
  final context = appNavigatorKey.currentContext;
  if (context == null) return;
  alarmDialogOpen.value = true;
  showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => AlarmAlertDialog(
      segmentId: segmentId,
      notificationId: notificationId,
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
      segmentId: pending.segmentId,
      notificationId: pending.notificationId,
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
/// tap, whenever a block's start alarm time arrives while this app is already
/// the one on screen — checked once a second (cheap: just a minute-of-day
/// comparison) but only acted on once per actual minute change, so a block's
/// start time only ever opens the dialog once. The underlying notification
/// still fires too (so the alarm still works when the app isn't in the
/// foreground); this just means whoever's already looking at the app doesn't
/// have to notice and tap a heads-up banner first.
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

    final segments = ref.read(segmentsProvider).value;
    if (segments == null) return;

    for (final segment in segments) {
      if (!segment.alarmEnabled) continue;
      if (segment.startMinute == minuteOfDay) {
        _showAlarmDialog(
          segmentId: segment.id,
          notificationId: notificationIdFor(segment.id, 0),
        );
        break; // one dialog at a time is enough even if two start the same minute
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
      // 계정이 사라지는 순간(로그아웃 등으로 uid=null) — 이 기기에 예약된
      // 모든 알람을 취소한다. _signOut()이 로그아웃 직전에 이미 한 번
      // 취소하지만(가장 확실한 경로), 여기서도 한 번 더 거는 안전망:
      // cancelEverything은 idempotent하고 현재 routine 목록에 의존하지
      // 않으므로, 어떤 경로로 계정이 비워지든 이전 계정 알람이 남지 않는다.
      if (next == null) {
        if (prev != null) {
          try {
            await ref.read(notificationServiceProvider).cancelEverything();
          } catch (e) {
            logSwallowed('로그아웃 후 알람 전체 취소', e);
          }
        }
        return;
      }
      if (identical(prev, next)) return;
      final segments = await next.watchSegments().first;
      final settings = await next.watchSettings().first;
      try {
        await ref.read(notificationServiceProvider).rescheduleAll(segments, settings);
      } catch (e) {
        // 플랫폼 채널 부재(테스트 등) — 무시.
        logSwallowed('계정 전환 후 알람 재스케줄', e);
      }
    });
    return const SizedBox.shrink();
  }
}

/// No visual presence — banks each day the user reaches the achievement bar
/// as a permanent [AchievedDay], so the streak (see [StreakBadge]) reads those
/// stored days for everything but today instead of recomputing history from
/// the current routine list. Without this, adding a micro-step or deleting a
/// routine would silently rewrite past days' achievement and shift a streak
/// that was already earned — exactly the kind of "the app moved my goalposts"
/// moment this app works hard to avoid.
///
/// Writes only the *difference* (computed-achieved days not yet stored), which
/// on first run after this feature lands also backfills whatever history the
/// old live computation would have counted — freezing it once, from then on
/// authoritative. Records are write-once and never removed: an earned day
/// stays earned even if you later edit the routines behind it.
class _AchievementRecorder extends ConsumerStatefulWidget {
  const _AchievementRecorder();

  @override
  ConsumerState<_AchievementRecorder> createState() => _AchievementRecorderState();
}

class _AchievementRecorderState extends ConsumerState<_AchievementRecorder> {
  // Day-keys this session has already asked the repo to persist, so a rebuild
  // before the write round-trips through achievedDaysProvider doesn't queue the
  // same write again. (The write itself is idempotent — doc id is the day-key —
  // so this is just to avoid redundant calls, not for correctness.)
  final Set<String> _persistRequested = {};

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider).value;
    final completions = ref.watch(completionsProvider).value;
    final progress = ref.watch(microStepProgressProvider).value;
    final stored = ref.watch(achievedDaysProvider).value;

    // Wait until everything we'd compute from has actually loaded — acting on
    // a half-loaded picture could bank a day that isn't really achieved yet,
    // or (worse) skip backfilling one that is.
    if (segments == null ||
        completions == null ||
        progress == null ||
        stored == null) {
      return const SizedBox.shrink();
    }

    final storedKeys = {for (final d in stored) d.dateKey};
    final computed = achievedDateKeys(
      segments: segments,
      completions: completions,
      progress: progress,
    );
    // Never bank *today*: today is still live and can fall back below the bar
    // before midnight (un-checking an item). streakDateKeys deliberately
    // ignores any stored record for today and recomputes it live for exactly
    // this reason -- so banking today here (the moment it first crosses 50%)
    // would leave a permanent, never-removed record that wrongly counts
    // tomorrow even if the day ended below the bar. Today is banked naturally
    // the next time the app opens on a later day, when it's a settled past day.
    final todayKey = dayKeyFor();
    final toPersist = computed
        .difference(storedKeys)
        .difference(_persistRequested)
        .where((k) => k != todayKey)
        .toSet();

    if (toPersist.isNotEmpty) {
      _persistRequested.addAll(toPersist);
      // Persist after this frame: writing to the repo (and so emitting on
      // achievedDaysProvider) mid-build would re-enter the provider graph.
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final repo = ref.read(plannerRepositoryProvider);
        if (repo == null) return;
        for (final dateKey in toPersist) {
          try {
            await repo.saveAchievedDay(AchievedDay(dateKey: dateKey));
          } catch (e) {
            // 저장 실패(플랫폼/네트워크) — 다음 빌드에서 다시 시도되도록
            // _persistRequested에서 되돌린다.
            _persistRequested.remove(dateKey);
            logSwallowed('달성일 저장', e);
          }
        }
      });
    }

    return const SizedBox.shrink();
  }
}
