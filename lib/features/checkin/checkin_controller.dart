import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/checkin.dart';
import '../../data/providers.dart';

final checkinControllerProvider = Provider<CheckinController>(
  (ref) => CheckinController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for T8's mood/energy
/// check-in, mirroring `MitController`/`MemosController`.
class CheckinController {
  CheckinController(this._ref);

  final Ref _ref;

  /// Saves a new check-in or updates an existing one when [id] is provided.
  Future<void> save({
    String? id,
    required int mood,
    required int energy,
    String? note,
    DateTime? at,
    String? dateKey,
    String? createdAtIso,
  }) {
    final repo = _ref.read(plannerRepositoryProvider)!;
    if (id != null) {
      final now = at ?? DateTime.now();
      return repo.saveCheckin(
        Checkin(
          id: id,
          dateKey: dateKey ?? Checkin.today(mood: mood, energy: energy, at: now).dateKey,
          mood: mood,
          energy: energy,
          note: note,
          createdAtIso: createdAtIso ?? now.toIso8601String(),
        ),
      );
    }
    return repo.saveCheckin(
      Checkin.today(mood: mood, energy: energy, note: note, at: at),
    );
  }

  /// Deletes a check-in record by [id].
  Future<void> delete(String id) {
    final repo = _ref.read(plannerRepositoryProvider)!;
    return repo.removeCheckin(id);
  }
}
