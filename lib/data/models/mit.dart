import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// Records that a block was deliberately marked "오늘의 MIT" (Most Important
/// Task) for one calendar day -- a conscious "this is one of the few things
/// that matter most today" pick, separate from the block's own permanent
/// identity (today's priorities don't have to be tomorrow's). Keyed by
/// (dateKey, segmentId) the same way [AlarmSkip]/[Completion] are, so a new
/// day naturally starts with none marked rather than silently carrying
/// yesterday's picks forward.
@immutable
class Mit {
  final String dateKey;
  final String segmentId;

  const Mit({required this.dateKey, required this.segmentId});

  /// Builds today's mark (or [at]'s, for tests) for [segmentId].
  factory Mit.today(String segmentId, {DateTime? at}) {
    final n = at ?? DateTime.now();
    return Mit(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      segmentId: segmentId,
    );
  }

  String get id => keyFor(dateKey, segmentId);

  static String keyFor(String dateKey, String segmentId) =>
      '${dateKey}_$segmentId';

  Map<String, dynamic> toMap() => {'dateKey': dateKey, 'segmentId': segmentId};

  factory Mit.fromMap(Map<String, dynamic> map) => Mit(
    dateKey: map['dateKey'] as String,
    segmentId: map['segmentId'] as String,
  );
}
