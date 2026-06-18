import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Which of a [Routine]'s micro-steps were checked off on a given calendar
/// day. Keyed by (routineId, dateKey) the same way [Completion] is, so a new
/// day naturally starts with no record — and therefore no checks — without
/// any explicit reset logic.
@immutable
class MicroStepProgress {
  final String dateKey;
  final String routineId;
  final List<int> checkedIndices;

  const MicroStepProgress({
    required this.dateKey,
    required this.routineId,
    required this.checkedIndices,
  });

  /// Builds today's progress record (or [at]'s, for tests) for [routineId].
  factory MicroStepProgress.today(
    String routineId,
    Iterable<int> checkedIndices, {
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return MicroStepProgress(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      routineId: routineId,
      checkedIndices: checkedIndices.toList()..sort(),
    );
  }

  String get id => keyFor(dateKey, routineId);

  static String keyFor(String dateKey, String routineId) => '${dateKey}_$routineId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'routineId': routineId,
        'checkedIndices': checkedIndices,
      };

  factory MicroStepProgress.fromMap(Map<String, dynamic> map) => MicroStepProgress(
        dateKey: map['dateKey'] as String,
        routineId: map['routineId'] as String,
        checkedIndices:
            (map['checkedIndices'] as List<dynamic>).map((e) => e as int).toList(),
      );
}
