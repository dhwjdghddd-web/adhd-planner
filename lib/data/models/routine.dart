import 'package:flutter/foundation.dart';

/// A scheduled task placed inside a [Segment]. Carries everything the
/// notification service (STEP 8) needs to schedule the main alarm, the
/// transition warning, and snooze behaviour.
///
/// Deliberately has no length/duration field: [findRoutineStatus] treats a
/// routine as "current" from its [startMinute] until whichever other
/// routine starts next, however long that actually takes, rather than
/// expiring it after some fixed duration and leaving it impossible to
/// check off late. ADHD time-blindness means routines already run long or
/// short unpredictably -- penalizing that with a hard cutoff fights the
/// whole point of this app.
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
    this.alarmEnabled = true,
    this.leadWarningMin = 5,
    this.snoozeMin = 5,
    this.repeatDays = const [],
    this.notificationIds = const [],
  });

  /// True if this routine repeats on [isoWeekday] (1=Mon..7=Sun). An empty
  /// [repeatDays] means "every day".
  bool occursOn(int isoWeekday) =>
      repeatDays.isEmpty || repeatDays.contains(isoWeekday);

  // Sentinel so copyWith can tell "omitted" (keep current segmentId) apart
  // from "explicitly cleared" (segmentId: null) -- the plain `?? this` pattern
  // can't, and a routine's segment legitimately becomes null when the segment
  // it belonged to is deleted (see SegmentsController.delete).
  static const Object _unset = Object();

  Routine copyWith({
    Object? segmentId = _unset,
    String? title,
    String? note,
    List<String>? microSteps,
    int? startMinute,
    bool? alarmEnabled,
    int? leadWarningMin,
    int? snoozeMin,
    List<int>? repeatDays,
    List<int>? notificationIds,
  }) {
    return Routine(
      id: id,
      segmentId: identical(segmentId, _unset) ? this.segmentId : segmentId as String?,
      title: title ?? this.title,
      note: note ?? this.note,
      microSteps: microSteps ?? this.microSteps,
      startMinute: startMinute ?? this.startMinute,
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
        alarmEnabled: (map['alarmEnabled'] as bool?) ?? true,
        leadWarningMin: (map['leadWarningMin'] as int?) ?? 5,
        snoozeMin: (map['snoozeMin'] as int?) ?? 5,
        repeatDays: List<int>.from(map['repeatDays'] as List? ?? const []),
        notificationIds: List<int>.from(map['notificationIds'] as List? ?? const []),
      );
}
