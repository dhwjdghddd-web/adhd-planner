import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme.dart';
import 'data/models/app_settings.dart';
import 'data/providers.dart';
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
            ],
          ),
        );
      },
    );
  }
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
    final context = appNavigatorKey.currentContext;
    if (context == null) return;
    pendingAlarmAlert.value = null;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlarmAlertDialog(
        routineId: pending.routineId,
        notificationId: pending.notificationId,
      ),
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
