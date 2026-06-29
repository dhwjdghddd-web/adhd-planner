import 'package:flutter/foundation.dart';

enum AppThemeMode { system, light, dark }

/// Which view the home screen ('오늘') shows -- the full 24h dial, or T6's
/// minimal "다음 한 행동" (next action) view that hides everything but the
/// current/next block and a big start button. Remembered across launches
/// (see [AppSettings.homeViewMode]) so a deliberate switch sticks.
enum HomeViewMode { dial, nextAction }

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
  // Day-key of the last day the lighter "halfway there" (>=50% but not yet
  // 100%) feedback was shown -- a separate marker from [lastCelebratedDate]
  // so the two milestones (50%, 100%) each fire at most once per day,
  // independently. null = never.
  final String? lastPartialCelebratedDate;
  // Minutes the "10분 뒤 다시" alarm-screen button re-alerts after -- one of
  // 5/10/15, enforced by the settings-screen picker UI (not validated here).
  final int snoozeMinutes;
  // App-wide default minutes the quiet "전환 예고" heads-up notification fires
  // before a block's start. No settings-screen control yet (see
  // Segment.leadWarning for the per-block on/off).
  final int leadMinutes;
  // Day-key of the last day the memo inbox's "이 메모, 아직이에요" resurfacing
  // nudge was shown (or dismissed) — at most once per day, the same pattern
  // as [lastCelebratedDate]. null = never.
  final String? lastMemoNudgeDate;
  // Last home-screen view the user deliberately switched to (T6) -- the
  // toggle button remembers it across launches instead of always starting
  // back on the dial.
  final HomeViewMode homeViewMode;

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
    this.lastPartialCelebratedDate,
    this.snoozeMinutes = 10,
    this.leadMinutes = 10,
    this.lastMemoNudgeDate,
    this.homeViewMode = HomeViewMode.dial,
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
    String? lastPartialCelebratedDate,
    int? snoozeMinutes,
    int? leadMinutes,
    String? lastMemoNudgeDate,
    HomeViewMode? homeViewMode,
  }) {
    return AppSettings(
      themeMode: themeMode ?? this.themeMode,
      fontScale: fontScale ?? this.fontScale,
      reduceMotion: reduceMotion ?? this.reduceMotion,
      exactAlarmGranted: exactAlarmGranted ?? this.exactAlarmGranted,
      onboardingComplete: onboardingComplete ?? this.onboardingComplete,
      alarmSoundUri: clearAlarmSound
          ? null
          : (alarmSoundUri ?? this.alarmSoundUri),
      alarmSoundLabel: clearAlarmSound
          ? null
          : (alarmSoundLabel ?? this.alarmSoundLabel),
      vibrationPattern: vibrationPattern ?? this.vibrationPattern,
      lastCelebratedDate: lastCelebratedDate ?? this.lastCelebratedDate,
      lastPartialCelebratedDate:
          lastPartialCelebratedDate ?? this.lastPartialCelebratedDate,
      snoozeMinutes: snoozeMinutes ?? this.snoozeMinutes,
      leadMinutes: leadMinutes ?? this.leadMinutes,
      lastMemoNudgeDate: lastMemoNudgeDate ?? this.lastMemoNudgeDate,
      homeViewMode: homeViewMode ?? this.homeViewMode,
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
    'lastPartialCelebratedDate': lastPartialCelebratedDate,
    'snoozeMinutes': snoozeMinutes,
    'leadMinutes': leadMinutes,
    'lastMemoNudgeDate': lastMemoNudgeDate,
    'homeViewMode': homeViewMode.name,
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
    lastPartialCelebratedDate: map['lastPartialCelebratedDate'] as String?,
    snoozeMinutes: (map['snoozeMinutes'] as num?)?.toInt() ?? 10,
    leadMinutes: (map['leadMinutes'] as num?)?.toInt() ?? 10,
    lastMemoNudgeDate: map['lastMemoNudgeDate'] as String?,
    homeViewMode: HomeViewMode.values.firstWhere(
      (v) => v.name == map['homeViewMode'],
      orElse: () => HomeViewMode.dial,
    ),
  );
}
