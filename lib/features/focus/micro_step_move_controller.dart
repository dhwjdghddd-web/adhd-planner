import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/micro_step_move.dart';
import '../../data/providers.dart';

final microStepMoveControllerProvider = Provider<MicroStepMoveController>(
  (ref) => MicroStepMoveController(ref),
);

/// Write-side for "오늘만 여기서" moves: send a block's checklist item to a
/// different block just for today, or send it back home.
class MicroStepMoveController {
  MicroStepMoveController(this._ref);

  final Ref _ref;

  /// Show home block [homeSegmentId]'s item [stepIndex] under
  /// [targetSegmentId] for today. If the target IS the home block, this is a
  /// no-op move back home (the record is removed instead).
  Future<void> moveToday(
    String homeSegmentId,
    int stepIndex,
    String targetSegmentId, {
    DateTime? now,
  }) {
    final repo = _ref.read(plannerRepositoryProvider);
    if (repo == null) return Future.value();
    if (targetSegmentId == homeSegmentId) {
      return repo.removeMicroStepMove(homeSegmentId, stepIndex);
    }
    return repo.saveMicroStepMove(
      MicroStepMove.today(homeSegmentId, stepIndex, targetSegmentId, at: now),
    );
  }

  /// Return home block [homeSegmentId]'s item [stepIndex] to its home block.
  Future<void> returnHome(String homeSegmentId, int stepIndex) {
    final repo = _ref.read(plannerRepositoryProvider);
    if (repo == null) return Future.value();
    return repo.removeMicroStepMove(homeSegmentId, stepIndex);
  }
}
