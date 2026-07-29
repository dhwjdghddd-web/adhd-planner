import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rest_day.dart';
import '../../data/providers.dart';
import '../../data/today.dart';

final restDayControllerProvider = Provider<RestDayController>(
  (ref) => RestDayController(ref),
);

/// Write-side for 쉬는 날: mark/unmark a day as a rest day. The alarm
/// rescheduling that follows a toggle is driven by app.dart watching
/// restDaysProvider (so that day's alarms are suppressed / restored), not here.
class RestDayController {
  RestDayController(this._ref);

  final Ref _ref;

  /// "오늘은 쉬기" -- mark/unmark [now]'s day (defaults to today).
  Future<void> setToday(bool resting, {DateTime? now}) =>
      _setDay(resting, now ?? DateTime.now());

  /// "내일 쉬기" -- mark/unmark the day *after* [now] (defaults to tomorrow).
  /// Meant to be set the night before, so the morning's alarms never fire.
  Future<void> setTomorrow(bool resting, {DateTime? now}) =>
      _setDay(resting, tomorrowOf(now));

  Future<void> _setDay(bool resting, DateTime day) {
    final repo = _ref.read(plannerRepositoryProvider);
    if (repo == null) return Future.value();
    return resting
        ? repo.saveRestDay(RestDay.today(at: day))
        : repo.removeRestDay(dayKeyFor(day));
  }
}
