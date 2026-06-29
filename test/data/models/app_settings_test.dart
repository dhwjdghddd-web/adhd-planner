import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/app_settings.dart';

void main() {
  group('AppSettings', () {
    test('defaults are not onboarded and use system theme', () {
      const settings = AppSettings.defaults();
      expect(settings.onboardingComplete, false);
      expect(settings.themeMode, AppThemeMode.system);
      expect(settings.fontScale, 1.0);
      expect(settings.reduceMotion, false);
      expect(settings.exactAlarmGranted, false);
      expect(settings.alarmSoundUri, isNull);
      expect(settings.alarmSoundLabel, isNull);
      expect(settings.vibrationPattern, AlarmVibrationPattern.defaultPattern);
      expect(settings.snoozeMinutes, 10);
      expect(settings.leadMinutes, 10);
    });

    test(
      'toMap/fromMap round-trips every field including onboardingComplete',
      () {
        const settings = AppSettings(
          themeMode: AppThemeMode.dark,
          fontScale: 1.5,
          reduceMotion: true,
          exactAlarmGranted: true,
          onboardingComplete: true,
        );

        final restored = AppSettings.fromMap(settings.toMap());

        expect(restored.themeMode, AppThemeMode.dark);
        expect(restored.fontScale, 1.5);
        expect(restored.reduceMotion, true);
        expect(restored.exactAlarmGranted, true);
        expect(restored.onboardingComplete, true);
      },
    );

    test(
      'fromMap defaults onboardingComplete to false when missing (pre-STEP-12 documents)',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.onboardingComplete, false);
      },
    );

    test('copyWith only changes the given fields', () {
      const settings = AppSettings.defaults();
      final updated = settings.copyWith(onboardingComplete: true);

      expect(updated.onboardingComplete, true);
      expect(updated.themeMode, settings.themeMode);
      expect(updated.fontScale, settings.fontScale);
    });

    test(
      'toMap/fromMap round-trips a custom alarm sound and vibration pattern',
      () {
        const settings = AppSettings(
          alarmSoundUri: 'content://media/some/sound',
          alarmSoundLabel: '신나는 알람',
          vibrationPattern: AlarmVibrationPattern.long,
        );

        final restored = AppSettings.fromMap(settings.toMap());

        expect(restored.alarmSoundUri, 'content://media/some/sound');
        expect(restored.alarmSoundLabel, '신나는 알람');
        expect(restored.vibrationPattern, AlarmVibrationPattern.long);
      },
    );

    test(
      'fromMap defaults to the system sound and defaultPattern when missing',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.alarmSoundUri, isNull);
        expect(restored.vibrationPattern, AlarmVibrationPattern.defaultPattern);
      },
    );

    test('toMap/fromMap round-trips snoozeMinutes and leadMinutes', () {
      const settings = AppSettings(snoozeMinutes: 15, leadMinutes: 5);
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.snoozeMinutes, 15);
      expect(restored.leadMinutes, 5);
    });

    test(
      'fromMap defaults snoozeMinutes/leadMinutes to 10 on a legacy doc missing them',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.snoozeMinutes, 10);
        expect(restored.leadMinutes, 10);
      },
    );

    test('toMap/fromMap round-trips lastMemoNudgeDate', () {
      const settings = AppSettings(lastMemoNudgeDate: '2026-06-20');
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.lastMemoNudgeDate, '2026-06-20');
    });

    test(
      'fromMap defaults lastMemoNudgeDate to null on a legacy doc missing it',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.lastMemoNudgeDate, isNull);
      },
    );

    test('toMap/fromMap round-trips homeViewMode', () {
      const settings = AppSettings(homeViewMode: HomeViewMode.nextAction);
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.homeViewMode, HomeViewMode.nextAction);
    });

    test(
      'fromMap defaults homeViewMode to dial on a legacy doc missing it',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.homeViewMode, HomeViewMode.dial);
      },
    );

    test('checkin alarm defaults to off, at 21:00', () {
      const settings = AppSettings.defaults();
      expect(settings.checkinAlarmEnabled, false);
      expect(settings.checkinAlarmMinuteOfDay, 21 * 60);
    });

    test('toMap/fromMap round-trips the checkin alarm toggle and time', () {
      const settings = AppSettings(
        checkinAlarmEnabled: true,
        checkinAlarmMinuteOfDay: 8 * 60 + 30,
      );
      final restored = AppSettings.fromMap(settings.toMap());
      expect(restored.checkinAlarmEnabled, true);
      expect(restored.checkinAlarmMinuteOfDay, 8 * 60 + 30);
    });

    test(
      'fromMap defaults the checkin alarm to off/21:00 on a legacy doc missing it',
      () {
        final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
        expect(restored.checkinAlarmEnabled, false);
        expect(restored.checkinAlarmMinuteOfDay, 21 * 60);
      },
    );

    test('keepScreenOn defaults to off and round-trips', () {
      expect(const AppSettings.defaults().keepScreenOn, false);
      final restored = AppSettings.fromMap(
        const AppSettings(keepScreenOn: true).toMap(),
      );
      expect(restored.keepScreenOn, true);
    });

    test('fromMap defaults keepScreenOn to off on a legacy doc missing it', () {
      final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
      expect(restored.keepScreenOn, false);
    });

    test(
      'clearAlarmSound resets to the system default even with a uri/label passed',
      () {
        const settings = AppSettings(
          alarmSoundUri: 'content://media/some/sound',
          alarmSoundLabel: '신나는 알람',
        );

        final cleared = settings.copyWith(clearAlarmSound: true);

        expect(cleared.alarmSoundUri, isNull);
        expect(cleared.alarmSoundLabel, isNull);
      },
    );

    test('copyWith without clearAlarmSound keeps the existing sound', () {
      const settings = AppSettings(
        alarmSoundUri: 'content://media/some/sound',
        alarmSoundLabel: '신나는 알람',
      );

      final updated = settings.copyWith(reduceMotion: true);

      expect(updated.alarmSoundUri, 'content://media/some/sound');
      expect(updated.alarmSoundLabel, '신나는 알람');
    });
  });
}
