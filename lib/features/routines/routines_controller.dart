import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/routine.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';

final routinesControllerProvider = Provider<RoutinesController>(
  (ref) => RoutinesController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for the routines
/// feature, mirroring `SegmentsController`. Every write here re-runs
/// [NotificationService.rescheduleAll] against the fresh routine list, so
/// alarms always match whatever the user just saved or deleted.
class RoutinesController {
  RoutinesController(this._ref);

  final Ref _ref;

  Future<void> upsert(Routine routine) async {
    await _ref.read(plannerRepositoryProvider).upsertRoutine(routine);
    await _rescheduleAll();
  }

  Future<void> delete(String id) async {
    await _ref.read(plannerRepositoryProvider).deleteRoutine(id);
    await _rescheduleAll();
  }

  Future<void> _rescheduleAll() async {
    final repo = _ref.read(plannerRepositoryProvider);
    final routines = await repo.watchRoutines().first;
    final settings = await repo.watchSettings().first;
    await _ref.read(notificationServiceProvider).rescheduleAll(routines, settings);
  }
}
