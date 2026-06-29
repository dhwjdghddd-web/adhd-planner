import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/mit.dart';
import '../../data/providers.dart';
import '../../data/today.dart';

final mitControllerProvider = Provider<MitController>(
  (ref) => MitController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for T7's "오늘의 MIT"
/// star toggle, mirroring `SegmentsController`/`MemosController`. No cap on
/// how many blocks can be marked at once -- the star itself is the only
/// "keep it to a few" nudge.
class MitController {
  MitController(this._ref);

  final Ref _ref;

  /// Flips today's mark for [segmentId]: removes it if already marked,
  /// otherwise adds it. [isMitToday] is the caller's own current read (it
  /// already has to watch [mitsProvider] to render the star correctly, so
  /// passing that same boolean in avoids this also needing to re-derive it).
  Future<void> toggle(String segmentId, {required bool isMitToday}) {
    final repo = _ref.read(plannerRepositoryProvider)!;
    final todayKey = dayKeyFor();
    return isMitToday
        ? repo.removeMit(todayKey, segmentId)
        : repo.saveMit(Mit(dateKey: todayKey, segmentId: segmentId));
  }
}
