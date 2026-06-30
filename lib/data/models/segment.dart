import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';

/// A block of the day: a time range (rendered as a coloured arc on the dial)
/// that also carries its own checklist of tasks ("루틴" in the UI) and an
/// optional start-of-block alarm. This is the app's single scheduled entity --
/// there is no separate per-task entity. [startMinute]/[endMinute] are
/// minute-of-day (0~1440); a range that wraps past midnight is valid
/// (e.g. start=1320 end=120 means 22:00~02:00).
///
/// The alarm, when [alarmEnabled], fires once at [startMinute]. Blocks recur
/// every day (no weekday selection). [microSteps] are the checklist items the
/// Focus/checklist screens tick off; they drive completion and the streak.
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
  // Checklist items shown to the user as "루틴". Ticking them off drives
  // completion and the daily-achievement streak (see daily_achievement.dart).
  final List<String> microSteps;
  // Whether this block rings at [startMinute]. Off for blocks like 수면.
  final bool alarmEnabled;
  // Whether a quiet "전환 예고" heads-up notification fires
  // AppSettings.leadMinutes before [startMinute], in addition to the main
  // alarm. Per-block opt-out of the app-wide default (on); meaningless when
  // [alarmEnabled] is false (no alarm of any kind for this block then).
  final bool leadWarning;
  // Notification ids this block currently has scheduled, kept so a routine
  // delete/reschedule can cancel exactly what it created (see
  // NotificationService). Same role it had on the old Routine entity.
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
    this.alarmEnabled = true,
    this.leadWarning = true,
    this.notificationIds = const [],
  });

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

  /// Splits a (possibly midnight-wrapping) range into one or two
  /// non-wrapping half-open intervals for overlap comparison.
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

  Segment copyWith({
    String? name,
    int? colorValue,
    String? iconKey,
    int? startMinute,
    int? endMinute,
    int? order,
    String? note,
    List<String>? microSteps,
    bool? alarmEnabled,
    bool? leadWarning,
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
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      leadWarning: leadWarning ?? this.leadWarning,
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
        'alarmEnabled': alarmEnabled,
        'leadWarning': leadWarning,
        'notificationIds': notificationIds,
      };

  /// Defensive against malformed stored data so one bad document can't error
  /// the whole segments stream: numbers tolerate num/missing, times are clamped
  /// to a valid minute-of-day (0~1440 -- an out-of-range value would otherwise
  /// break the dial painter / containsMinute), and list elements of the wrong
  /// type are dropped rather than throwing.
  factory Segment.fromMap(Map<String, dynamic> map) {
    int intOr(Object? v, int fallback) => v is num ? v.toInt() : fallback;
    final start = intOr(
      map['startMinute'],
      0,
    ).clamp(0, TimeGeometry.minutesPerDay);
    final end = intOr(map['endMinute'], 0).clamp(0, TimeGeometry.minutesPerDay);
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
      alarmEnabled: (map['alarmEnabled'] as bool?) ?? true,
      leadWarning: (map['leadWarning'] as bool?) ?? true,
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
