import 'package:flutter/foundation.dart';

enum AppThemeMode { system, light, dark }

/// Single-document user preferences: theme, accessibility scaling, and the
/// last-known permission state for exact alarms (STEP 8/12).
@immutable
class AppSettings {
  final AppThemeMode themeMode;
  final double fontScale;
  final bool reduceMotion;
  final bool exactAlarmGranted;
  final bool onboardingComplete;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.fontScale = 1.0,
    this.reduceMotion = false,
    this.exactAlarmGranted = false,
    this.onboardingComplete = false,
  });

  const AppSettings.defaults() : this();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    double? fontScale,
    bool? reduceMotion,
    bool? exactAlarmGranted,
    bool? onboardingComplete,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      exactAlarmGranted: exactAlarmGranted ?? this.exactAlarmGranted,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
    );
  }

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'fontScale': fontScale,
        'reduceMotion': reduceMotion,
        'exactAlarmGranted': exactAlarmGranted,
        'onboardingComplete': onboardingComplete,
      };

  factory AppSettings.fromMap(Map<String, dynamic> map) => AppSettings(
        themeMode: AppThemeMode.values.firstWhere(
          (m) => m.name == map['themeMode'],
          orElse: () => AppThemeMode.system,
        ),
        fontScale: (map['fontScale'] as num?)?.toDouble() ?? 1.0,
        reduceMotion: (map['reduceMotion'] as bool?) ?? false,
        exactAlarmGranted: (map['exactAlarmGranted'] as bool?) ?? false,
        onboardingComplete: (map['onboardingComplete'] as bool?) ?? false,
      );
}
