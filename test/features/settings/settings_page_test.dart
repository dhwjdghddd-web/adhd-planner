import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/providers.dart';
import 'package:adhd_planner/features/help/help_page.dart';
import 'package:adhd_planner/features/settings/settings_page.dart';
import 'package:adhd_planner/services/notification_service.dart';

import '../../fakes/fake_notification_service.dart';
import '../../fakes/fake_planner_repository.dart';

void main() {
  Widget wrap(FakePlannerRepository repo) {
    return ProviderScope(
      overrides: [plannerRepositoryProvider.overrideWithValue(repo)],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  // T10's 알림 채널 rows call NotificationService.openChannelSettings
  // directly (not behind a try/catch the way _rescheduleAlarms swallows a
  // MissingPluginException) -- the real service's own catch would still
  // keep these tests from crashing, but a recording fake is what lets a test
  // actually assert *which* channel id a given row opened.
  Widget wrapWithFakeNotifications(
    FakePlannerRepository repo,
    FakeNotificationService fakeService,
  ) {
    return ProviderScope(
      overrides: [
        plannerRepositoryProvider.overrideWithValue(repo),
        notificationServiceProvider.overrideWithValue(fakeService),
      ],
      child: const MaterialApp(home: SettingsPage()),
    );
  }

  // The settings list is taller than the default test surface, which would
  // leave the account row below the fold un-inflated. Growing the surface
  // (same approach as routine_form_page_test.dart) avoids needing to scroll.
  // Grown again for T10's 알림 채널 section -- five more rows pushed 화면/계정
  // further down than the previous 1400px height could still inflate.
  Future<void> growSurface(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1900));
    tester.view.physicalSize = const Size(800, 1900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets(
    'renders permission rows and theme/motion controls without crashing',
    (tester) async {
      await growSurface(tester);
      await tester.pumpWidget(wrap(FakePlannerRepository()));
      await tester.pumpAndSettle();

      expect(find.text('알림'), findsOneWidget);
      expect(find.text('정확한 알람'), findsOneWidget);
      expect(find.text('마이크'), findsOneWidget);
      expect(find.text('동작 줄이기'), findsOneWidget);
      // No platform channel under flutter test, so status degrades gracefully.
      expect(find.text('확인 중...'), findsWidgets);
    },
  );

  testWidgets('the 도움말 row opens HelpPage', (tester) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    await tester.tap(find.text('도움말'));
    await tester.pumpAndSettle();

    expect(find.byType(HelpPage), findsOneWidget);
  });

  testWidgets(
    'shows the system default alarm sound and all vibration pattern choices',
    (tester) async {
      await growSurface(tester);
      await tester.pumpWidget(wrap(FakePlannerRepository()));
      await tester.pumpAndSettle();

      expect(find.text('기본 알람음'), findsOneWidget);
      for (final pattern in AlarmVibrationPattern.values) {
        expect(find.widgetWithText(ChoiceChip, pattern.label), findsOneWidget);
      }
      final defaultChip = tester.widget<ChoiceChip>(
        find.widgetWithText(
          ChoiceChip,
          AlarmVibrationPattern.defaultPattern.label,
        ),
      );
      expect(defaultChip.selected, true);
    },
  );

  testWidgets('picking a different vibration pattern persists it', (
    tester,
  ) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(
      find.widgetWithText(ChoiceChip, AlarmVibrationPattern.long.label),
    );
    await tester.pumpAndSettle();

    expect(settingsLog.last.vibrationPattern, AlarmVibrationPattern.long);
  });

  testWidgets('shows the snooze-minutes choices with the default selected', (
    tester,
  ) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    for (final minutes in const [5, 10, 15]) {
      expect(find.widgetWithText(ChoiceChip, '$minutes분'), findsOneWidget);
    }
    final defaultChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, '10분'),
    );
    expect(defaultChip.selected, true);
  });

  testWidgets('picking a different snooze minutes persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(ChoiceChip, '15분'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.snoozeMinutes, 15);
  });

  testWidgets(
    'tapping the alarm sound row does not crash with no platform channel',
    (tester) async {
      await growSurface(tester);
      await tester.pumpWidget(wrap(FakePlannerRepository()));
      await tester.pumpAndSettle();

      await tester.tap(find.text('기본 알람음'));
      await tester.pumpAndSettle();

      // No native picker under flutter test, so this is a no-op rather than a
      // crash — the row should still be showing the unchanged default.
      expect(find.text('기본 알람음'), findsOneWidget);
    },
  );

  testWidgets('selecting a theme segment persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.text('다크'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.themeMode, AppThemeMode.dark);
  });

  testWidgets('toggling reduce motion persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, '동작 줄이기'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.reduceMotion, true);
  });

  testWidgets('toggling 화면 항상 켜두기 persists it', (tester) async {
    final repo = FakePlannerRepository();
    final settingsLog = <AppSettings>[];
    repo.watchSettings().listen(settingsLog.add);

    await growSurface(tester);
    await tester.pumpWidget(wrap(repo));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(SwitchListTile, '화면 항상 켜두기'));
    await tester.pumpAndSettle();

    expect(settingsLog.last.keepScreenOn, true);
  });

  testWidgets('checkin alarm is off by default, with the time row disabled', (
    tester,
  ) async {
    await growSurface(tester);
    await tester.pumpWidget(wrap(FakePlannerRepository()));
    await tester.pumpAndSettle();

    expect(find.text('하루 체크인 알림'), findsOneWidget);
    final toggle = tester.widget<SwitchListTile>(
      find.widgetWithText(SwitchListTile, '하루 체크인 알림'),
    );
    expect(toggle.value, false);

    final timeRow = tester.widget<ListTile>(
      find.widgetWithText(ListTile, '알림 시간'),
    );
    expect(timeRow.enabled, false);
    // Default time (21:00) still shows even while disabled.
    expect(find.text('9:00 PM'), findsOneWidget);
  });

  testWidgets(
    'turning on the checkin alarm persists it and enables the time row',
    (tester) async {
      final repo = FakePlannerRepository();
      final settingsLog = <AppSettings>[];
      repo.watchSettings().listen(settingsLog.add);

      await growSurface(tester);
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, '하루 체크인 알림'));
      await tester.pumpAndSettle();

      expect(settingsLog.last.checkinAlarmEnabled, true);
      final timeRow = tester.widget<ListTile>(
        find.widgetWithText(ListTile, '알림 시간'),
      );
      expect(timeRow.enabled, true);
    },
  );

  testWidgets(
    'tapping the time row while enabled opens the scrollable wheel picker '
    '(not the dial/keyboard time picker)',
    (tester) async {
      final repo = FakePlannerRepository();
      await repo.saveSettings(const AppSettings(checkinAlarmEnabled: true));

      await growSurface(tester);
      await tester.pumpWidget(wrap(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('9:00 PM'));
      await tester.pumpAndSettle();

      expect(find.byType(CupertinoDatePicker), findsOneWidget);
      expect(find.byType(TimePickerDialog), findsNothing);
    },
  );

  testWidgets('shows a row for every notification channel (T10)', (
    tester,
  ) async {
    await growSurface(tester);
    await tester.pumpWidget(
      wrapWithFakeNotifications(
        FakePlannerRepository(),
        FakeNotificationService(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('구간 알람'), findsOneWidget);
    expect(find.text('구간 전환 예고'), findsOneWidget);
    expect(find.text('집중 타이머'), findsOneWidget);
    expect(find.text('체크인 알림 채널'), findsOneWidget);
  });

  testWidgets(
    "tapping a channel row opens that channel's system settings (T10)",
    (tester) async {
      final fakeService = FakeNotificationService();
      await growSurface(tester);
      await tester.pumpWidget(
        wrapWithFakeNotifications(FakePlannerRepository(), fakeService),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('체크인 알림 채널'));
      await tester.pumpAndSettle();
      expect(fakeService.openedChannelSettings, [checkinChannelId]);

      await tester.tap(find.text('집중 타이머'));
      await tester.pumpAndSettle();
      expect(fakeService.openedChannelSettings, [
        checkinChannelId,
        focusTimerChannelId,
      ]);

      await tester.tap(find.text('구간 전환 예고'));
      await tester.pumpAndSettle();
      expect(fakeService.openedChannelSettings, [
        checkinChannelId,
        focusTimerChannelId,
        leadWarningChannelId,
      ]);

      // The main alarm channel's id varies with the current sound+vibration
      // choice (see _channelSuffix in notification_service.dart) -- default
      // settings here, so it should resolve to alarmChannelId's value for them.
      await tester.tap(find.text('구간 알람'));
      await tester.pumpAndSettle();
      expect(
        fakeService.openedChannelSettings.last,
        alarmChannelId(const AppSettings.defaults()),
      );
    },
  );

  testWidgets(
    'the account section renders as anonymous with no Firebase app initialized',
    (tester) async {
      // Under flutter test there's no Firebase app at all, so
      // firebaseUserProvider's stream errors out -- the account section should
      // degrade to the anonymous state rather than crash. Real sign-in flow is
      // platform-dependent and isn't exercised by widget tests (see
      // GOOGLE_AUTH_PLAN.md §9).
      await growSurface(tester);
      await tester.pumpWidget(wrap(FakePlannerRepository()));
      await tester.pumpAndSettle();

      expect(find.text('익명으로 사용 중'), findsOneWidget);
      expect(find.text('Google 연결'), findsOneWidget);
    },
  );
}
