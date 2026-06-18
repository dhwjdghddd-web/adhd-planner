import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/micro_step_progress.dart';
import '../../data/providers.dart';

final microStepProgressControllerProvider = Provider<MicroStepProgressController>(
  (ref) => MicroStepProgressController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for persisting which
/// micro-steps were checked off today, mirroring `CompletionsController`.
class MicroStepProgressController {
  MicroStepProgressController(this._ref);

  final Ref _ref;

  Future<void> save(String routineId, Iterable<int> checkedIndices, {DateTime? now}) {
    return _ref
        .read(plannerRepositoryProvider)
        .saveMicroStepProgress(MicroStepProgress.today(routineId, checkedIndices, at: now));
  }
}
