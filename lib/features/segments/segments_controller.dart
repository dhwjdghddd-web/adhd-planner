import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/segment.dart';
import '../../data/providers.dart';

final segmentsControllerProvider = Provider<SegmentsController>(
  (ref) => SegmentsController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for the segments
/// feature: keeps overlap detection and reordering logic out of the
/// widgets so it can be unit-tested on its own.
class SegmentsController {
  SegmentsController(this._ref);

  final Ref _ref;

  Future<void> upsert(Segment segment) =>
      _ref.read(plannerRepositoryProvider)!.upsertSegment(segment);

  Future<void> delete(String id) =>
      _ref.read(plannerRepositoryProvider)!.deleteSegment(id);

  /// Persists a new ordering by rewriting the `order` field of every
  /// segment whose position changed.
  Future<void> reorder(List<Segment> orderedSegments) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    for (var i = 0; i < orderedSegments.length; i++) {
      final segment = orderedSegments[i];
      if (segment.order != i) {
        await repo.upsertSegment(segment.copyWith(order: i));
      }
    }
  }

  /// Overlap is allowed by design (the dial renders overlapping arcs on
  /// separate rings) but the editor surfaces a warning so it's a deliberate
  /// choice rather than an accident.
  bool overlapsAny(Segment candidate, List<Segment> others) {
    return others.any((o) => o.id != candidate.id && candidate.overlaps(o));
  }
}
