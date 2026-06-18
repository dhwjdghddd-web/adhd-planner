import 'package:flutter/foundation.dart';

import '../../core/time_geometry.dart';

/// A scheduled task placed inside a [Segment]. Carries everything the
/// notification service (STEP 8) needs to schedule the main alarm, the
/// transition warning, and snooze behaviour.
///
/// [repeatDays] uses ISO-8601 weekday numbers (1=Mon .. 7=Sun). An empty
/// list means "every day".
@immutable
class Routine {
  final String id;
  // null means the routine's startMinute doesn't fall inside any current
  // segment (e.g. a gap between segments) — segmentId is derived from
  // startMinute automatically rather than user-chosen, see
  // routine_form_page.dart's _autoSegmentId.
  final String? segmentId;
  final String title;
  final String note;
  final List<String> microSteps;
  final int startMinute;
  final int durationMin;
  final bool alarmEnabled;
  final int leadWarningMin;
  final int snoozeMin;
  final List<int> repeatDays;
  final List<int> notificationIds;

  const Routine({
    required this.id,
    required this.segmentId,
    required this.title,
    this.note = '',
    this.microSteps = const [],
    required this.startMinute,
    this.durationMin = 30,
    this.alarmEnabled = true,
    this.leadWarningMin = 5,
    this.snoozeMin = 5,
    this.repeatDays = const [],
    this.notificationIds = const [],
  });

  int get endMinute => (startMinute + durationMin) % TimeGeometry.minutesPerDay;

  /// True if [minute] falls inside this routine's [startMinute, endMinute)
  /// span, accounting for midnight-wrapping spans.
  bool containsMinute(int minute) {
    if (durationMin <= 0) return false;
    if (durationMin % TimeGeometry.minutesPerDay == 0) return true;
    final m = minute % TimeGeometry.minutesPerDay;
    final start = startMinute % TimeGeometry.minutesPerDay;
    final end = endMinute;
    if (start < end) return m >= start && m < end;
    return m >= start || m < end;
  }

  /// True if this routine repeats on [isoWeekday] (1=Mon..7=Sun). An empty
  /// [repeatDays] means "every day".
  bool occursOn(int isoWeekday) =>
      repeatDays.isEmpty || repeatDays.contains(isoWeekday);

  Routine copyWith({
    String? segmentId,
    String? title,
    String? note,
    List<String>? microSteps,
    int? startMinute,
    int? durationMin,
    bool? alarmEnabled,
    int? leadWarningMin,
    int? snoozeMin,
    List<int>? repeatDays,
    List<int>? notificationIds,
  }) {
    return Routine(
      id: id,
      segmentId: segmentId ?? this.segmentId,
      title: title ?? this.title,
      note: note ?? this.note,
      microSteps: microSteps ?? this.microSteps,
      startMinute: startMinute ?? this.startMinute,
      durationMin: durationMin ?? this.durationMin,
      alarmEnabled: alarmEnabled ?? this.alarmEnabled,
      leadWarningMin: leadWarningMin ?? this.leadWarningMin,
      snoozeMin: snoozeMin ?? this.snoozeMin,
      repeatDays: repeatDays ?? this.repeatDays,
      notificationIds: notificationIds ?? this.notificationIds,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'segmentId': segmentId,
        'title': title,
        'note': note,
        'microSteps': microSteps,
        'startMinute': startMinute,
        'durationMin': durationMin,
        'alarmEnabled': alarmEnabled,
        'leadWarningMin': leadWarningMin,
        'snoozeMin': snoozeMin,
        'repeatDays': repeatDays,
        'notificationIds': notificationIds,
      };

  factory Routine.fromMap(Map<String, dynamic> map) => Routine(
        id: map['id'] as String,
        segmentId: map['segmentId'] as String?,
        title: map['title'] as String,
        note: (map['note'] as String?) ?? '',
        microSteps: List<String>.from(map['microSteps'] as List? ?? const []),
        startMinute: map['startMinute'] as int,
        durationMin: (map['durationMin'] as int?) ?? 30,
        alarmEnabled: (map['alarmEnabled'] as bool?) ?? true,
        leadWarningMin: (map['leadWarningMin'] as int?) ?? 5,
        snoozeMin: (map['snoozeMin'] as int?) ?? 5,
        repeatDays: List<int>.from(map['repeatDays'] as List? ?? const []),
        notificationIds: List<int>.from(map['notificationIds'] as List? ?? const []),
      );
}
