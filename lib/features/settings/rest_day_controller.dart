import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/rest_day.dart';
import '../../data/providers.dart';

final restDayControllerProvider = Provider<RestDayController>(
  (ref) => RestDayController(ref),
);

/// Controller for managing deliberate rest days (Off-Days / Holidays).
class RestDayController {
  RestDayController(this._ref);

  final Ref _ref;

  /// Toggles the rest day status for a given [dateKey] (yyyy-MM-dd).
  Future<void> toggle(String dateKey) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    final restDays = await repo.watchRestDays().first;
    final isAlreadyRest = restDays.any((r) => r.dateKey == dateKey);

    if (isAlreadyRest) {
      await repo.removeRestDay(dateKey);
    } else {
      await repo.saveRestDay(RestDay(dateKey: dateKey));
    }
  }

  /// Sets whether [dateKey] is a rest day.
  Future<void> setRestDay(String dateKey, bool isRest) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    if (isRest) {
      await repo.saveRestDay(RestDay(dateKey: dateKey));
    } else {
      await repo.removeRestDay(dateKey);
    }
  }
}
