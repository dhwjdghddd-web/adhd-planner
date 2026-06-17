import 'package:flutter/foundation.dart';

/// Records that a [Routine] was completed on a given calendar day. Drives
/// the streak/reward logic in STEP 10. [dateKey] is "yyyy-MM-dd" in local
/// time so streaks line up with the user's wall-clock day.
@immutable
class Completion {
  final String dateKey;
  final String routineId;
  final String completedAtIso;

  const Completion({
    required this.dateKey,
    required this.routineId,
    required this.completedAtIso,
  });

  String get id => keyFor(dateKey, routineId);

  static String keyFor(String dateKey, String routineId) => '${dateKey}_$routineId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'routineId': routineId,
        'completedAtIso': completedAtIso,
      };

  factory Completion.fromMap(Map<String, dynamic> map) => Completion(
        dateKey: map['dateKey'] as String,
        routineId: map['routineId'] as String,
        completedAtIso: map['completedAtIso'] as String,
      );
}
