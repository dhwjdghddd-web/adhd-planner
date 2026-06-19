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
              const SafeArea(
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: GlobalQuickAddButton(),
                  ),
                ),
              ),
              const _AlarmAlertLauncher(),
              const _ForegroundAlarmWatcher(),
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
class _RootRouter extends ConsumerWidget {
  const _RootRouter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settingsAsync = ref.watch(settingsProvider);
    return settingsAsync.when(
      data: (settings) =>
          settings.onboardingComplete ? const PlannerPage() : const OnboardingPage(),
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
    final effective = applyTodaysPostponements(routines, postponements, now: now);
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
