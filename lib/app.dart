import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/debug_log.dart';
import 'core/theme.dart';
import 'data/models/achieved_day.dart';
import 'data/models/app_settings.dart';
import 'data/providers.dart';
import 'data/today.dart';
import 'features/checkin/checkin_page.dart';
import 'features/focus/alarm_screen.dart';
import 'features/memos/quick_add_button.dart';
import 'features/onboarding/onboarding_page.dart';
import 'features/planner/planner_page.dart';
import 'features/rewards/completion_celebration.dart';
import 'features/rewards/daily_achievement.dart';
import 'features/rewards/streak.dart';
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
    final settings =
        ref.watch(settingsProvider).value ?? const AppSettings.defaults();

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
          data: mediaQuery.copyWith(
            textScaler: TextScaler.linear(settings.fontScale),
          ),
          child: Stack(
            children: [
              child!,
              const _AlarmAlertLauncher(),
              const _ForegroundAlarmWatcher(),
              const _CheckinAlertLauncher(),
              const _AccountAlarmSync(),
              const _AchievementRecorder(),
              const _CompletionCelebrator(),
            ],
          ),
        );
      },
    );
  }
}

/// True while [AlarmScreen] is up, shared by [_AlarmAlertLauncher]
/// (the notification-tap/fullScreenIntent path) and
/// [_ForegroundAlarmWatcher] (the "app is already open" path below) so
/// they never push two alarm screens on top of each other for the same alarm.
/// Public (not `_`-prefixed) so tests can reset it between cases the same
/// way they already do for `quickAddSheetOpen`/`fabSuppressionCount`.
final ValueNotifier<bool> alarmScreenOpen = ValueNotifier(false);

void _showAlarmScreen({
  required String segmentId,
  required int notificationId,
}) {
  if (alarmScreenOpen.value) return;
  final navigator = appNavigatorKey.currentState;
  if (navigator == null) return;
  alarmScreenOpen.value = true;
  // A full-screen route, not a dialog: it takes the whole screen (and, with the
  // activity's showWhenLocked/turnScreenOn, the lock screen) like a real alarm.
  navigator
      .push(
        MaterialPageRoute<void>(
          fullscreenDialog: true,
          builder: (_) =>
              AlarmScreen(segmentId: segmentId, notificationId: notificationId),
        ),
      )
      .whenComplete(() => alarmScreenOpen.value = false);
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
      data: (s) =>
          s.onboardingComplete ? const PlannerPage() : const OnboardingPage(),
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, st) => Scaffold(body: Center(child: Text('오류: $e'))),
    );
  }
}

/// No visual presence of its own — just watches [pendingAlarmAlert] (set by
/// notification_service.dart whenever the main alarm notification is
/// tapped, including the system auto-launching the app via
/// fullScreenIntent) and pushes [AlarmScreen] once the Navigator
/// actually exists. A plain callback from the notification handler can't
/// show the screen directly: on a cold start, that handler can fire before
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
    _showAlarmScreen(
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

/// No visual presence — watches [pendingCheckinAlert] (set by
/// notification_service.dart when the daily check-in reminder is tapped) and
/// pushes [CheckinPage] straight into its mood/energy dialog once the
/// Navigator is ready. Same cold-start handoff problem and fix as
/// [_AlarmAlertLauncher] above.
class _CheckinAlertLauncher extends StatefulWidget {
  const _CheckinAlertLauncher();

  @override
  State<_CheckinAlertLauncher> createState() => _CheckinAlertLauncherState();
}

class _CheckinAlertLauncherState extends State<_CheckinAlertLauncher> {
  @override
  void initState() {
    super.initState();
    pendingCheckinAlert.addListener(_openIfPending);
    WidgetsBinding.instance.addPostFrameCallback((_) => _openIfPending());
  }

  void _openIfPending() {
    if (!pendingCheckinAlert.value) return;
    final navigator = appNavigatorKey.currentState;
    if (navigator == null) return;
    pendingCheckinAlert.value = false;
    navigator.push(
      MaterialPageRoute<void>(
        builder: (_) => const CheckinPage(autoOpenMoodDialog: true),
      ),
    );
  }

  @override
  void dispose() {
    pendingCheckinAlert.removeListener(_openIfPending);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Pushes [AlarmScreen] on its own, without waiting for a notification
/// tap, whenever a block's start alarm time arrives while this app is already
/// the one on screen — checked once a second (cheap: just a minute-of-day
/// comparison) but only acted on once per actual minute change, so a block's
/// start time only ever opens the screen once. The underlying notification
/// still fires too (so the alarm still works when the app isn't in the
/// foreground); this just means whoever's already looking at the app doesn't
/// have to notice and tap a heads-up banner first.
class _ForegroundAlarmWatcher extends ConsumerStatefulWidget {
  const _ForegroundAlarmWatcher();

  @override
  ConsumerState<_ForegroundAlarmWatcher> createState() =>
      _ForegroundAlarmWatcherState();
}

class _ForegroundAlarmWatcherState
    extends ConsumerState<_ForegroundAlarmWatcher> {
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
    // Blocks skipped for today ("오늘은 건너뛰기" on AlarmScreen) shouldn't pop
    // again from this independent timer -- mainly a defensive guard against a
    // same-minute race (this State recreating and resetting
    // _lastCheckedMinuteOfDay right after a skip, within the same literal
    // minute the alarm fired in).
    final skips = ref.read(alarmSkipsProvider).value ?? const [];
    final skippedToday = skippedBlockIdsOn(skips);

    for (final segment in segments) {
      if (!segment.alarmEnabled) continue;
      if (skippedToday.contains(segment.id)) continue;
      if (segment.startMinute == minuteOfDay) {
        _showAlarmScreen(
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
        await ref
            .read(notificationServiceProvider)
            .rescheduleAll(segments, settings);
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
  ConsumerState<_AchievementRecorder> createState() =>
      _AchievementRecorderState();
}

class _AchievementRecorderState extends ConsumerState<_AchievementRecorder> {
  // Day-keys this session has already asked the repo to persist, so a rebuild
  // before the write round-trips through achievedDaysProvider doesn't queue the
  // same write again. (The write itself is idempotent — doc id is the day-key —
  // so this is just to avoid redundant calls, not for correctness.)
  final Set<String> _persistRequested = {};

  @override
  Widget build(BuildContext context) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final completionsAsync = ref.watch(completionsProvider);
    final progressAsync = ref.watch(microStepProgressProvider);
    final storedAsync = ref.watch(achievedDaysProvider);

    // Wait until everything we'd compute from has actually loaded *for the
    // current account* -- not just non-null, but settled (not mid-reload
    // from a uid change). During a logout/login transition,
    // plannerRepositoryProvider can already point at the new account while
    // these still report the previous account's last-known values (Riverpod
    // keeps a StreamProvider's previous data visible while its new
    // subscription's first event is in flight) -- acting on that mix could
    // bank a *past* day the old account hadn't gotten to yet into the new,
    // unrelated account. Same hazard as _CompletionCelebrator's
    // lastCelebratedDate write; same fix.
    if (segmentsAsync.isLoading ||
        completionsAsync.isLoading ||
        progressAsync.isLoading ||
        storedAsync.isLoading) {
      return const SizedBox.shrink();
    }

    final segments = segmentsAsync.value;
    final completions = completionsAsync.value;
    final progress = progressAsync.value;
    final stored = storedAsync.value;

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

/// No visual presence — watches today's checklist progress for two milestones,
/// each firing at most once a day (gated by its own [AppSettings] day-key, so
/// neither re-fires on rebuild, app restart, or un-checking and re-checking):
/// the moment every one of today's "루틴" items is ticked, the full-screen
/// completion celebration ([showCompletionCelebration], gated by
/// [AppSettings.lastCelebratedDate]); the moment today first crosses the
/// achievement bar (>=50%) without yet reaching 100%, a lighter snackbar
/// ([AppSettings.lastPartialCelebratedDate]) -- so a hard day that never
/// reaches 100% still gets *something* warm rather than nothing at all.
/// Lives here (not on the home screen) so either lands wherever the
/// triggering item is checked — Focus, the catch-up checklist, anywhere.
class _CompletionCelebrator extends ConsumerStatefulWidget {
  const _CompletionCelebrator();

  @override
  ConsumerState<_CompletionCelebrator> createState() =>
      _CompletionCelebratorState();
}

class _CompletionCelebratorState extends ConsumerState<_CompletionCelebrator> {
  // Guards a double-pop in the window between deciding to celebrate and the
  // persisted lastCelebratedDate write round-tripping back through settings.
  bool _shownThisSession = false;
  // Same guard, for the lighter 50% ("halfway there") feedback -- independent
  // of [_shownThisSession] so the two milestones never block each other.
  bool _partialShownThisSession = false;

  @override
  Widget build(BuildContext context) {
    // On logout (signOut -> signInAnonymously), plannerRepositoryProvider
    // switches straight from the old account's repo to null to the new
    // (empty) anonymous account's repo -- but segments/completions/progress/
    // achievedDays each depend on it via their own ref.watch, so each one
    // independently goes through its own AsyncLoading-with-previous-data
    // phase while its *own* new stream subscription gets its first event.
    // settingsProvider's catches up fastest (its null-repo fallback and a
    // brand new account's first read are both near-instant), but
    // segments/completions/progress took ~100ms longer on a real device --
    // long enough for one build to see the *old* account's "fully done
    // today" segments/completions/progress (still mid-AsyncLoading, value
    // retained) alongside the *new* account's already-reset
    // lastCelebratedDate=null, which looked exactly like "today hasn't been
    // celebrated yet" and re-popped the celebration (and then wrote
    // lastCelebratedDate into the *new*, empty account). Checking
    // !hasValue/isLoading on every one of them -- not just whether the repo
    // itself is currently null -- closes that gap regardless of which
    // provider lags.
    final segmentsAsync = ref.watch(segmentsProvider);
    final completionsAsync = ref.watch(completionsProvider);
    final progressAsync = ref.watch(microStepProgressProvider);
    final settingsAsync = ref.watch(settingsProvider);
    final achievedDaysAsync = ref.watch(achievedDaysProvider);

    if (segmentsAsync.isLoading ||
        completionsAsync.isLoading ||
        progressAsync.isLoading ||
        settingsAsync.isLoading ||
        achievedDaysAsync.isLoading) {
      return const SizedBox.shrink();
    }

    final segments = segmentsAsync.value;
    final completions = completionsAsync.value;
    final progress = progressAsync.value;
    final settings = settingsAsync.value;
    final achievedDays = achievedDaysAsync.value;

    if (segments == null ||
        completions == null ||
        progress == null ||
        settings == null ||
        achievedDays == null) {
      return const SizedBox.shrink();
    }

    final todayKey = dayKeyFor();
    final achievement = dailyAchievementFor(
      dateKey: todayKey,
      segments: segments,
      completions: completions,
      progress: progress,
    );

    // Only blocks that actually use checklist items can be "all done" -- a day
    // with no items at all never triggers it (there's nothing to finish).
    final fullyDone =
        achievement.total > 0 && achievement.checked >= achievement.total;
    // Crossed the achievement bar (>=50%) but not yet 100% -- the lighter
    // "halfway there" moment. Gated on total > 0 so a day with no checklist
    // items at all (which can only reach [DailyAchievement.isAchieved] via the
    // whole-block fallback) never fires this -- there's no real "halfway"
    // there to mark.
    final partiallyDone =
        achievement.total > 0 && achievement.isAchieved && !fullyDone;
    final alreadyToday = settings.lastCelebratedDate == todayKey;
    final alreadyPartialToday = settings.lastPartialCelebratedDate == todayKey;

    if (fullyDone && !alreadyToday && !_shownThisSession) {
      _shownThisSession = true;
      // Current streak length (today included), so a milestone day (3/7/14/
      // 30/60/100) gets a special line in the celebration -- see
      // [celebrationMilestones]. Computed the same way StreakBadge does.
      final streakDays = currentStreak(
        streakDateKeys(
          achievedDays: achievedDays,
          segments: segments,
          completions: completions,
          progress: progress,
        ),
      );
      // After this frame: persisting (and showing a dialog) mid-build would
      // re-enter the provider graph / Navigator.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        // Fire-and-forget: the Firestore write's Future doesn't resolve offline,
        // but the local cache (which gates re-firing) updates synchronously.
        final repo = ref.read(plannerRepositoryProvider);
        repo
            ?.saveSettings(settings.copyWith(lastCelebratedDate: todayKey))
            .catchError((Object e) => logSwallowed('완료 축하 표시일 저장', e));
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          showCompletionCelebration(
            ctx,
            reduceMotion: settings.reduceMotion,
            streakDays: streakDays,
          );
        }
      });
    } else if (partiallyDone &&
        !alreadyPartialToday &&
        !alreadyToday &&
        !_partialShownThisSession) {
      // !alreadyToday: if today's full 100% celebration already happened (e.g.
      // pressed "모두 완료" then un-checked back below 100%), don't follow it
      // with the lighter "오늘 절반을 해냈어요" -- that would read as a downgrade.
      _partialShownThisSession = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final repo = ref.read(plannerRepositoryProvider);
        repo
            ?.saveSettings(
              settings.copyWith(lastPartialCelebratedDate: todayKey),
            )
            .catchError((Object e) => logSwallowed('부분 달성 표시일 저장', e));
        final ctx = appNavigatorKey.currentContext;
        if (ctx != null) {
          showAppSnackBar(ctx, const Text('오늘 절반을 해냈어요 — 충분히 잘하고 있어요'));
        }
      });
    }

    // Reset guards independently of the trigger above, so falling back below
    // a bar (un-checking an item) always allows that milestone to fire again
    // later -- lastCelebratedDate/lastPartialCelebratedDate still gate today.
    if (!fullyDone && _shownThisSession) {
      _shownThisSession = false;
    }
    if (!partiallyDone && _partialShownThisSession) {
      _partialShownThisSession = false;
    }

    return const SizedBox.shrink();
  }
}
