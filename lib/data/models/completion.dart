import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Records that a block (segment) was completed on a given calendar day --
/// "completed" meaning all its checklist items ("루틴") were ticked off. Drives
/// the streak/reward logic. [dateKey] is "yyyy-MM-dd" in local time so streaks
/// line up with the user's wall-clock day.
@immutable
class Completion {
  final String dateKey;
  final String segmentId;
  final String completedAtIso;

  const Completion({
    required this.dateKey,
    required this.segmentId,
    required this.completedAtIso,
  });

  /// Builds a completion for "right now" (or [at], for tests) — shared by
  /// the in-app focus screen and the background notification action handler
  /// so both compute [dateKey] the same way.
  factory Completion.now(String segmentId, {DateTime? at}) {
    final n = at ?? DateTime.now();
    return Completion(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      segmentId: segmentId,
      completedAtIso: n.toIso8601String(),
    );
  }

  String get id => keyFor(dateKey, segmentId);

  static String keyFor(String dateKey, String segmentId) => '${dateKey}_$segmentId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'segmentId': segmentId,
        'completedAtIso': completedAtIso,
      };

  factory Completion.fromMap(Map<String, dynamic> map) => Completion(
        dateKey: map['dateKey'] as String,
        segmentId: map['segmentId'] as String,
        completedAtIso: map['completedAtIso'] as String,
      );
}
