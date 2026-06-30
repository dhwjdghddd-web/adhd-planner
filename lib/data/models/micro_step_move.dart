import 'package:flutter/foundation.dart';
import 'package:intl/intl.dart';

/// A "오늘만 여기서" move: for ONE calendar day, a single checklist item ("루틴")
/// is shown under a different block than the one it permanently belongs to
/// (e.g. a morning item done in the afternoon instead). Only its *display*
/// location moves -- the item's checked state still lives in its home block's
/// [MicroStepProgress], so streak/achievement counting (which is keyed by the
/// home block's item indices) is unaffected, and a new day naturally reverts
/// to the configured layout since this record is per-[dateKey].
///
/// Identified by (dateKey, homeSegmentId, stepIndex): a given item can be moved
/// at most once per day. [targetSegmentId] is where it shows today; moving it
/// back home is represented by deleting the record, not by target == home.
@immutable
class MicroStepMove {
  final String dateKey;
  final String homeSegmentId;
  final int stepIndex;
  final String targetSegmentId;

  const MicroStepMove({
    required this.dateKey,
    required this.homeSegmentId,
    required this.stepIndex,
    required this.targetSegmentId,
  });

  /// Builds today's move (or [at]'s, for tests).
  factory MicroStepMove.today(
    String homeSegmentId,
    int stepIndex,
    String targetSegmentId, {
    DateTime? at,
  }) {
    final n = at ?? DateTime.now();
    return MicroStepMove(
      dateKey: DateFormat('yyyy-MM-dd').format(n),
      homeSegmentId: homeSegmentId,
      stepIndex: stepIndex,
      targetSegmentId: targetSegmentId,
    );
  }

  String get id => keyFor(dateKey, homeSegmentId, stepIndex);

  static String keyFor(String dateKey, String homeSegmentId, int stepIndex) =>
      '${dateKey}_${homeSegmentId}_$stepIndex';

  Map<String, dynamic> toMap() => {
    'dateKey': dateKey,
    'homeSegmentId': homeSegmentId,
    'stepIndex': stepIndex,
    'targetSegmentId': targetSegmentId,
  };

  factory MicroStepMove.fromMap(Map<String, dynamic> map) => MicroStepMove(
    dateKey: map['dateKey'] as String,
    homeSegmentId: map['homeSegmentId'] as String,
    stepIndex: (map['stepIndex'] as num).toInt(),
    targetSegmentId: map['targetSegmentId'] as String,
  );
}
