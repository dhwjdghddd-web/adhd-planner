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

  /// Deletes a segment and re-homes every routine that belonged to it, so no
  /// routine is left pointing at a segment id that no longer exists. Each
  /// affected routine's segment is re-derived from its `startMinute` against
  /// the *remaining* segments -- the same "segment is just whichever range
  /// covers the start time" rule routines are created under -- which lands it
  /// on an overlapping segment if one still covers that minute, or on null
  /// (구간 없음) if none does. Without this the stale id would silently mis-place
  /// the routine's dial marker (it falls back to lane 0) until the routine
  /// happened to be edited and re-saved.
  Future<void> delete(String id) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    final routines = await repo.watchRoutines().first;
    final remaining =
        (await repo.watchSegments().first).where((s) => s.id != id).toList();
    for (final routine in routines) {
      if (routine.segmentId != id) continue;
      final rehomed = _segmentCovering(remaining, routine.startMinute)?.id;
      await repo.upsertRoutine(routine.copyWith(segmentId: rehomed));
    }
    await repo.deleteSegment(id);
  }

  /// The first remaining segment whose range covers [startMinute], or null --
  /// mirrors RoutineFormPage's auto-derivation so a re-homed routine matches a
  /// freshly created one at the same time.
  static Segment? _segmentCovering(List<Segment> segments, int startMinute) {
    for (final segment in segments) {
      if (segment.containsMinute(startMinute)) return segment;
    }
    return null;
  }

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
