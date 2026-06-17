import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/routine.dart';
import '../../data/providers.dart';

final routinesControllerProvider = Provider<RoutinesController>(
  (ref) => RoutinesController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for the routines
/// feature, mirroring `SegmentsController`. Every write here is the trigger
/// point STEP 8 will hook `NotificationService.rescheduleAll` into, so
/// alarms stay in sync with whatever the user just saved.
class RoutinesController {
  RoutinesController(this._ref);

  final Ref _ref;

  Future<void> upsert(Routine routine) =>
      _ref.read(plannerRepositoryProvider).upsertRoutine(routine);

  Future<void> delete(String id) =>
      _ref.read(plannerRepositoryProvider).deleteRoutine(id);
}
