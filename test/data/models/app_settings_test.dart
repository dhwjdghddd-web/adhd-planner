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
    });

    test('toMap/fromMap round-trips every field including onboardingComplete', () {
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
    });

    test('fromMap defaults onboardingComplete to false when missing (pre-STEP-12 documents)', () {
      final restored = AppSettings.fromMap(const {'themeMode': 'dark'});
      expect(restored.onboardingComplete, false);
    });

    test('copyWith only changes the given fields', () {
      const settings = AppSettings.defaults();
      final updated = settings.copyWith(onboardingComplete: true);

      expect(updated.onboardingComplete, true);
      expect(updated.themeMode, settings.themeMode);
      expect(updated.fontScale, settings.fontScale);
    });
  });
}
