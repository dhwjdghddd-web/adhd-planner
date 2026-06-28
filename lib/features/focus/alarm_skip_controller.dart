import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/alarm_skip.dart';
import '../../data/providers.dart';

final alarmSkipControllerProvider = Provider<AlarmSkipController>(
  (ref) => AlarmSkipController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for "오늘은 건너뛰기" on
/// [AlarmScreen], mirroring `MicroStepProgressController`.
class AlarmSkipController {
  AlarmSkipController(this._ref);

  final Ref _ref;

  Future<void> skipToday(String segmentId, {DateTime? now}) {
    return _ref
        .read(plannerRepositoryProvider)!
        .saveAlarmSkip(AlarmSkip.today(segmentId, at: now));
  }
}
