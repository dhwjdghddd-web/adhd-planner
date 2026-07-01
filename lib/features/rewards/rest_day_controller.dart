import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rest_day.dart';
import '../../data/providers.dart';
import '../../data/today.dart';

final restDayControllerProvider = Provider<RestDayController>(
  (ref) => RestDayController(ref),
);

/// Write-side for "오늘은 쉬기": mark/unmark today as a rest day. The alarm
/// rescheduling that follows a toggle is driven by app.dart watching
/// restDaysProvider (so today's alarms are suppressed / restored), not here.
class RestDayController {
  RestDayController(this._ref);

  final Ref _ref;

  Future<void> setToday(bool resting, {DateTime? now}) {
    final repo = _ref.read(plannerRepositoryProvider);
    if (repo == null) return Future.value();
    return resting
        ? repo.saveRestDay(RestDay.today(at: now))
        : repo.removeRestDay(dayKeyFor(now));
  }
}
