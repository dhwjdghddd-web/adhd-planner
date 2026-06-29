import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/checkin.dart';
import '../../data/providers.dart';

final checkinControllerProvider = Provider<CheckinController>(
  (ref) => CheckinController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for T8's daily
/// mood/energy check-in, mirroring `MitController`/`MemosController`.
class CheckinController {
  CheckinController(this._ref);

  final Ref _ref;

  /// Saves (or overwrites) today's check-in -- one per day, so doing this
  /// again today just updates the same record rather than creating another.
  Future<void> save({required int mood, required int energy, String? note}) {
    final repo = _ref.read(plannerRepositoryProvider)!;
    return repo.saveCheckin(
      Checkin.today(mood: mood, energy: energy, note: note),
    );
  }

  /// Deletes [dateKey]'s check-in -- swipe-to-delete in 최근 기록.
  Future<void> delete(String dateKey) {
    final repo = _ref.read(plannerRepositoryProvider)!;
    return repo.removeCheckin(dateKey);
  }
}
