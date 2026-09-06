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
      await repo.saveRestDay(RestDay(dateKey: dateKey, presetId: 'rest'));
    } else {
      await repo.removeRestDay(dateKey);
    }
  }

  /// Sets a specific preset for a single [dateKey].
  Future<void> setPreset(String dateKey, String presetId) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    await repo.saveRestDay(RestDay(dateKey: dateKey, presetId: presetId));
  }

  /// Sets a specific preset for multiple [dateKeys] at once.
  Future<void> setPresetForDates(Iterable<String> dateKeys, String presetId) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    for (final key in dateKeys) {
      await repo.saveRestDay(RestDay(dateKey: key, presetId: presetId));
    }
  }

  /// Clears assigned presets for multiple [dateKeys] (resets to default work day).
  Future<void> clearDates(Iterable<String> dateKeys) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    for (final key in dateKeys) {
      await repo.removeRestDay(key);
    }
  }
}
