import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// How many minutes today's "미루기" (postpone) presses have pushed a
/// routine's effective start time back by, cumulative across however many
/// times the lead-warning or main alarm's 미루기 button was pressed today.
/// Keyed by (routineId, dateKey) the same way [Completion]/[MicroStepProgress]
/// are, so a new day naturally starts with no record — and therefore no
/// offset — without any explicit reset logic. Never touches the routine's
/// own stored `startMinute`, which stays the permanent recurring schedule.
@immutable
class RoutinePostponement {
  final String dateKey;
  final String routineId;
  final int offsetMinutes;

  const RoutinePostponement({
    required this.dateKey,
    required this.routineId,
    required this.offsetMinutes,
  });

  /// Builds today's postponement record (or [at]'s, for tests) for [routineId].
  factory RoutinePostponement.today(
    String routineId,
    int offsetMinutes, {
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return RoutinePostponement(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      routineId: routineId,
      offsetMinutes: offsetMinutes,
    );
  }

  String get id => keyFor(dateKey, routineId);

  static String keyFor(String dateKey, String routineId) => '${dateKey}_$routineId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'routineId': routineId,
        'offsetMinutes': offsetMinutes,
      };

  factory RoutinePostponement.fromMap(Map<String, dynamic> map) => RoutinePostponement(
        dateKey: map['dateKey'] as String,
        routineId: map['routineId'] as String,
        offsetMinutes: map['offsetMinutes'] as int,
      );
}
