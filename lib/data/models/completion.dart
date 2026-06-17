import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

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

  /// Builds a completion for "right now" (or [at], for tests) — shared by
  /// the in-app focus screen and the background notification action handler
  /// so both compute [dateKey] the same way.
  factory Completion.now(String routineId, {DateTime? at}) {
    final n = at ?? DateTime.now();
    return Completion(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      routineId: routineId,
      completedAtIso: n.toIso8601String(),
    );
  }

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
