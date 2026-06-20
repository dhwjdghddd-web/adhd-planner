import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// "넘기기": today's occurrence of a routine has been explicitly skipped --
/// unlike [RoutinePostponement] (shifts today's time) or `Completion`
/// (marks today's occurrence done), a skip removes the routine from
/// today's candidate set entirely: it can't show as either 지금 or 다음 for
/// the rest of today (see `excludeTodaysSkips`), and its still-armed alarms
/// for today are cancelled outright. Tomorrow's (or its next scheduled
/// weekday's) occurrence is unaffected. Keyed by (routineId, dateKey) the
/// same way [RoutinePostponement]/`Completion`/`MicroStepProgress` are, so
/// a new day naturally starts with no record.
@immutable
class RoutineSkip {
  final String dateKey;
  final String routineId;

  const RoutineSkip({required this.dateKey, required this.routineId});

  /// Builds today's skip record (or [at]'s, for tests) for [routineId].
  factory RoutineSkip.today(String routineId, {DateTime? at}) {
    final n = at ?? DateTime.now();
    return RoutineSkip(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      routineId: routineId,
    );
  }

  String get id => keyFor(dateKey, routineId);

  static String keyFor(String dateKey, String routineId) => '${dateKey}_$routineId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'routineId': routineId,
      };

  factory RoutineSkip.fromMap(Map<String, dynamic> map) => RoutineSkip(
        dateKey: map['dateKey'] as String,
        routineId: map['routineId'] as String,
      );
}
