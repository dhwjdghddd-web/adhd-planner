import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Which of a block's checklist items ("루틴") were checked off on a given
/// calendar day. Keyed by (segmentId, dateKey) the same way [Completion] is,
/// so a new day naturally starts with no record — and therefore no checks —
/// without any explicit reset logic.
@immutable
class MicroStepProgress {
  final String dateKey;
  final String segmentId;
  final List<int> checkedIndices;

  const MicroStepProgress({
    required this.dateKey,
    required this.segmentId,
    required this.checkedIndices,
  });

  /// Builds today's progress record (or [at]'s, for tests) for [segmentId].
  factory MicroStepProgress.today(
    String segmentId,
    Iterable<int> checkedIndices, {
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return MicroStepProgress(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      segmentId: segmentId,
      checkedIndices: checkedIndices.toList()..sort(),
    );
  }

  String get id => keyFor(dateKey, segmentId);

  static String keyFor(String dateKey, String segmentId) => '${dateKey}_$segmentId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'segmentId': segmentId,
        'checkedIndices': checkedIndices,
      };

  factory MicroStepProgress.fromMap(Map<String, dynamic> map) => MicroStepProgress(
        dateKey: map['dateKey'] as String,
        // Falls back to the legacy 'routineId' field so a pre-merge doc still
        // deserializes instead of crashing -- see Completion.fromMap.
        segmentId: (map['segmentId'] ?? map['routineId'] ?? '') as String,
        checkedIndices:
            (map['checkedIndices'] as List<dynamic>).map((e) => e as int).toList(),
      );
}
