import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Records that a block's alarm was explicitly skipped for one calendar day --
/// the "오늘은 건너뛰기" action on [AlarmScreen]. Keyed by (segmentId, dateKey)
/// the same way [MicroStepProgress]/[Completion] are, so a new day naturally
/// has no skip record and the alarm rings normally again without any explicit
/// reset logic.
@immutable
class AlarmSkip {
  final String dateKey;
  final String segmentId;

  const AlarmSkip({required this.dateKey, required this.segmentId});

  /// Builds today's skip record (or [at]'s, for tests) for [segmentId].
  factory AlarmSkip.today(String segmentId, {DateTime? at}) {
    final n = at ?? DateTime.now();
    return AlarmSkip(dateKey: DateFormat('yyyy-MM-dd').format(n), segmentId: segmentId);
  }

  String get id => keyFor(dateKey, segmentId);

  static String keyFor(String dateKey, String segmentId) => '${dateKey}_$segmentId';

  Map<String, dynamic> toMap() => {
        'dateKey': dateKey,
        'segmentId': segmentId,
      };

  factory AlarmSkip.fromMap(Map<String, dynamic> map) => AlarmSkip(
        dateKey: map['dateKey'] as String,
        segmentId: map['segmentId'] as String,
      );
}
