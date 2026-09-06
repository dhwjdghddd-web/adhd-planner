import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';

/// Intensity and UI presentation of the block's alarm.
enum SegmentAlarmType {
  fullScreen, // 🚨 강력 알람: 잠금화면 위 전체화면 + 1분간 반복 알람/진동
  gentle,     // 🔔 부드러운 알림: 상단 배너 푸시 + 1회 알림음
  hapticOnly, // 📳 조용한 진동: 무음 햅틱 진동만 1회
  none,       // 🚫 알람 없음: 다이얼에만 표시
}

/// Work-day vs Rest-day (holiday) condition for when this block rings.
enum SegmentScheduleTarget {
  everyday,     // 🔄 매일 항상 울림
  workDaysOnly, // 🏢 근무일에만 울림 (쉬는 날/휴일에는 알람 억제)
  restDaysOnly, // 🏖️ 쉬는 날(휴일)에만 울림 (근무일에는 알람 억제)
}

/// A block of the day: a time range (rendered as a coloured arc on the dial)
/// that also carries its own checklist of tasks ("루틴" in the UI) and an
/// optional start-of-block alarm. This is the app's single scheduled entity --
/// there is no separate per-task entity. [startMinute]/[endMinute] are
/// minute-of-day (0~1440); a range that wraps past midnight is valid
/// (e.g. start=1320 end=120 means 22:00~02:00).
@immutable
class Segment {
  final String id;
  final String name;
  final int colorValue;
  final String iconKey;
  final int startMinute;
  final int endMinute;
  final int order;
  final String note;
  // Checklist items shown to the user as "루틴".
  final List<String> microSteps;
  // Alarm intensity and UI takeover mode (fullScreen, gentle, hapticOnly, none).
  final SegmentAlarmType alarmType;
  // Target days when this block's alarm is active (everyday, workDaysOnly, restDaysOnly).
  final SegmentScheduleTarget scheduleTarget;
  // Minutes before [startMinute] to fire a quiet transition warning (0 = disabled, 5, 10, 15, 30).
  final int leadWarningMinutes;
  // Whether this block is designated as the first block (wake-up block) of the day.
  final bool isFirstBlock;
  // Specific calendar date overrides for start minute: {"yyyy-MM-dd": minuteOfDay}.
  final Map<String, int> dateOverrides;
  // Notification ids this block currently has scheduled.
  final List<int> notificationIds;

  const Segment({
    required this.id,
    required this.name,
    required this.colorValue,
    required this.iconKey,
    required this.startMinute,
    required this.endMinute,
    required this.order,
    this.note = '',
    this.microSteps = const [],
    SegmentAlarmType? alarmType,
    this.scheduleTarget = SegmentScheduleTarget.everyday,
    int? leadWarningMinutes,
    bool? alarmEnabled,
    bool? leadWarning,
    this.isFirstBlock = false,
    this.dateOverrides = const {},
    this.notificationIds = const [],
  }) : alarmType = alarmType ??
           (alarmEnabled != null
               ? (alarmEnabled ? SegmentAlarmType.fullScreen : SegmentAlarmType.none)
               : SegmentAlarmType.fullScreen),
       leadWarningMinutes = leadWarningMinutes ??
           (leadWarning != null ? (leadWarning ? 10 : 0) : 10);

  /// Backward-compatible getter for whether any alarm is active.
  bool get alarmEnabled => alarmType != SegmentAlarmType.none;

  /// Backward-compatible getter for lead warning.
  bool get leadWarning => leadWarningMinutes > 0 && alarmEnabled;

  Color get color => Color(colorValue);

  Color themeColor(BuildContext context) {
    return getEffectiveSegmentColor(Color(colorValue), Theme.of(context).brightness);
  }

  int get lengthMinutes => TimeGeometry.lengthMinutes(startMinute, endMinute);

  /// True if [minute] falls inside this segment's range, accounting for
  /// midnight-wrapping ranges (e.g. 22:00~02:00 contains 23:30 and 01:00).
  bool containsMinute(int minute) {
    if (startMinute == endMinute) return false;
    final m = minute % TimeGeometry.minutesPerDay;
    if (startMinute < endMinute) {
      return m >= startMinute && m < endMinute;
    }
    return m >= startMinute || m < endMinute;
  }

  /// True if this segment's time range overlaps [other]'s, accounting for
  /// midnight-wrapping ranges. Shared by the segment editor's overlap
  /// warning and the dial painter's lane assignment for overlapping arcs.
  bool overlaps(Segment other) {
    for (final a in _intervals) {
      for (final b in other._intervals) {
        if (a.start < b.end && b.start < a.end) return true;
      }
    }
    return false;
  }

  List<_SegmentInterval> get _intervals {
    if (startMinute == endMinute) return const [];
    if (startMinute < endMinute) {
      return [_SegmentInterval(startMinute, endMinute)];
    }
    return [
      _SegmentInterval(startMinute, TimeGeometry.minutesPerDay),
      _SegmentInterval(0, endMinute),
    ];
  }

  static const int noAlarmMinute = -1;

  /// True if alarm is explicitly suppressed on [dateKey].
  bool isAlarmSuppressedOn(String dateKey) => dateOverrides[dateKey] == noAlarmMinute;

  /// Returns the start minute for [dateKey] ("yyyy-MM-dd"), respecting date overrides if set.
  int startMinuteFor([String? dateKey]) {
    if (dateKey != null && dateOverrides.containsKey(dateKey)) {
      final val = dateOverrides[dateKey]!;
      if (val != noAlarmMinute) return val;
    }
    return startMinute;
  }

  /// Returns the end minute for [dateKey], keeping block duration if overridden.
  int endMinuteFor([String? dateKey]) {
    if (dateKey != null && dateOverrides.containsKey(dateKey)) {
      final val = dateOverrides[dateKey]!;
      if (val != noAlarmMinute) {
        return (val + lengthMinutes) % TimeGeometry.minutesPerDay;
      }
    }
    return endMinute;
  }

  Segment copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? startMinute,
    int? endMinute,
    int? order,
    String? note,
    List<String>? microSteps,
    SegmentAlarmType? alarmType,
    SegmentScheduleTarget? scheduleTarget,
    int? leadWarningMinutes,
    bool? alarmEnabled,
    bool? leadWarning,
    bool? isFirstBlock,
    Map<String, int>? dateOverrides,
    List<int>? notificationIds,
  }) {
    return Segment(
      id: id,
      name: name ?? this.name,
      colorValue: colorValue ?? this.colorValue,
      iconKey: iconKey ?? this.iconKey,
      startMinute: startMinute ?? this.startMinute,
      endMinute: endMinute ?? this.endMinute,
      order: order ?? this.order,
      note: note ?? this.note,
      microSteps: microSteps ?? this.microSteps,
      alarmType: alarmType ?? (alarmEnabled != null ? (alarmEnabled ? SegmentAlarmType.fullScreen : SegmentAlarmType.none) : this.alarmType),
      scheduleTarget: scheduleTarget ?? this.scheduleTarget,
      leadWarningMinutes: leadWarningMinutes ?? (leadWarning != null ? (leadWarning ? 10 : 0) : this.leadWarningMinutes),
      isFirstBlock: isFirstBlock ?? this.isFirstBlock,
      dateOverrides: dateOverrides ?? this.dateOverrides,
      notificationIds: notificationIds ?? this.notificationIds,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'name': name,
        'colorValue': colorValue,
        'iconKey': iconKey,
        'startMinute': startMinute,
        'endMinute': endMinute,
        'order': order,
        'note': note,
        'microSteps': microSteps,
        'alarmType': alarmType.name,
        'scheduleTarget': scheduleTarget.name,
        'leadWarningMinutes': leadWarningMinutes,
        'alarmEnabled': alarmEnabled,
        'leadWarning': leadWarning,
        'isFirstBlock': isFirstBlock,
        'dateOverrides': dateOverrides,
        'notificationIds': notificationIds,
      };

  factory Segment.fromMap(Map<String, dynamic> map) {
    int intOr(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final start = intOr(
      map['startMinute'],
      0,
    ).clamp(0, TimeGeometry.minutesPerDay);
    final end = intOr(map['endMinute'], 0).clamp(0, TimeGeometry.minutesPerDay);

    // Backward compatibility for alarmType
    SegmentAlarmType alarmType;
    if (map['alarmType'] is String) {
      alarmType = SegmentAlarmType.values.firstWhere(
        (e) => e.name == map['alarmType'],
        orElse: () => SegmentAlarmType.fullScreen,
      );
    } else {
      final enabled = (map['alarmEnabled'] as bool?) ?? true;
      alarmType = enabled ? SegmentAlarmType.fullScreen : SegmentAlarmType.none;
    }

    // Backward compatibility for scheduleTarget
    SegmentScheduleTarget scheduleTarget = SegmentScheduleTarget.everyday;
    if (map['scheduleTarget'] is String) {
      scheduleTarget = SegmentScheduleTarget.values.firstWhere(
        (e) => e.name == map['scheduleTarget'],
        orElse: () => SegmentScheduleTarget.everyday,
      );
    }

    // Backward compatibility for leadWarningMinutes
    int leadWarningMinutes = 10;
    if (map['leadWarningMinutes'] is num) {
      leadWarningMinutes = (map['leadWarningMinutes'] as num).toInt();
    } else if (map['leadWarning'] is bool) {
      leadWarningMinutes = (map['leadWarning'] as bool) ? 10 : 0;
    }

    final dateOverridesRaw = map['dateOverrides'];
    final dateOverrides = <String, int>{};
    if (dateOverridesRaw is Map) {
      for (final entry in dateOverridesRaw.entries) {
        if (entry.value is num) {
          dateOverrides[entry.key.toString()] = (entry.value as num).toInt();
        }
      }
    }

    return Segment(
      id: (map['id'] as String?) ?? '',
      name: (map['name'] as String?) ?? '',
      colorValue: intOr(map['colorValue'], 0xFF000000),
      iconKey: (map['iconKey'] as String?) ?? 'wb_sunny',
      startMinute: start,
      endMinute: end,
      order: intOr(map['order'], 0),
      note: (map['note'] as String?) ?? '',
      microSteps: (map['microSteps'] as List? ?? const [])
          .whereType<String>()
          .toList(),
      alarmType: alarmType,
      scheduleTarget: scheduleTarget,
      leadWarningMinutes: leadWarningMinutes,
      isFirstBlock: (map['isFirstBlock'] as bool?) ?? false,
      dateOverrides: dateOverrides,
      notificationIds: (map['notificationIds'] as List? ?? const [])
          .whereType<num>()
          .map((n) => n.toInt())
          .toList(),
    );
  }
}

class _SegmentInterval {
  const _SegmentInterval(this.start, this.end);
  final int start;
  final int end;
}
