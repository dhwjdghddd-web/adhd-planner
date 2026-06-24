import 'package:flutter/foundation.dart';

enum AppThemeMode { system, light, dark }

/// A named vibration shape for alarms (STEP 12+) — the actual millisecond
/// pattern each one maps to lives in notification_service.dart, since
/// that's the only place that needs real `Int64List` values.
enum AlarmVibrationPattern {
  defaultPattern,
  short,
  long,
  doublePulse;

  String get label => switch (this) {
        AlarmVibrationPattern.defaultPattern => '기본',
        AlarmVibrationPattern.short => '짧게, 자주',
        AlarmVibrationPattern.long => '길게, 천천히',
        AlarmVibrationPattern.doublePulse => '두 번씩 끊어서',
      };
}

/// Single-document user preferences: theme, accessibility scaling, alarm
/// sound/vibration choice, and the last-known permission state for exact
/// alarms (STEP 8/12).
@immutable
class AppSettings {
  final AppThemeMode themeMode;
  final double fontScale;
  final bool reduceMotion;
  final bool exactAlarmGranted;
  final bool onboardingComplete;
  // null means "use the system's default alarm sound".
  final String? alarmSoundUri;
  final String? alarmSoundLabel;
  final AlarmVibrationPattern vibrationPattern;
  // Day-key (yyyy-MM-dd) of the last day the "all of today's checklist done"
  // celebration was shown, so it fires at most once per day. null = never.
  final String? lastCelebratedDate;

  const AppSettings({
    this.themeMode = AppThemeMode.system,
    this.fontScale = 1.0,
    this.reduceMotion = false,
    this.exactAlarmGranted = false,
    this.onboardingComplete = false,
    this.alarmSoundUri,
    this.alarmSoundLabel,
    this.vibrationPattern = AlarmVibrationPattern.defaultPattern,
    this.lastCelebratedDate,
  });

  const AppSettings.defaults() : this();

  AppSettings copyWith({
    AppThemeMode? themeMode,
    double? fontScale,
    bool? reduceMotion,
    bool? exactAlarmGranted,
    bool? onboardingComplete,
    String? alarmSoundUri,
    String? alarmSoundLabel,
    // Set this to actually go back to the system default — a plain
    // `alarmSoundUri: null` argument can't be told apart from "unchanged".
    bool clearAlarmSound = false,
    AlarmVibrationPattern? vibrationPattern,
    String? lastCelebratedDate,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      exactAlarmGranted: exactAlarmGranted ?? this.exactAlarmGranted,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      alarmSoundUri: clearAlarmSound ? null : (alarmSoundUri ?? this.alarmSoundUri),
      alarmSoundLabel: clearAlarmSound ? null : (alarmSoundLabel ?? this.alarmSoundLabel),
      vibrationPattern: vibrationPattern ?? this.vibrationPattern,
      lastCelebratedDate: lastCelebratedDate ?? this.lastCelebratedDate,
    );
  }

  Map<String, dynamic> toMap() => {
        'themeMode': themeMode.name,
        'fontScale': fontScale,
        'reduceMotion': reduceMotion,
        'exactAlarmGranted': exactAlarmGranted,
        'onboardingComplete': onboardingComplete,
        'alarmSoundUri': alarmSoundUri,
        'alarmSoundLabel': alarmSoundLabel,
        'vibrationPattern': vibrationPattern.name,
        'lastCelebratedDate': lastCelebratedDate,
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
        alarmSoundUri: map['alarmSoundUri'] as String?,
        alarmSoundLabel: map['alarmSoundLabel'] as String?,
        vibrationPattern: AlarmVibrationPattern.values.firstWhere(
          (v) => v.name == map['vibrationPattern'],
          orElse: () => AlarmVibrationPattern.defaultPattern,
        ),
        lastCelebratedDate: map['lastCelebratedDate'] as String?,
      );
}
