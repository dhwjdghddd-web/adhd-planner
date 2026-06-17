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
      _ref.read(plannerRepositoryProvider).upsertSegment(segment);

  Future<void> delete(String id) =>
      _ref.read(plannerRepositoryProvider).deleteSegment(id);

  /// Persists a new ordering by rewriting the `order` field of every
  /// segment whose position changed.
  Future<void> reorder(List<Segment> orderedSegments) async {
    final repo = _ref.read(plannerRepositoryProvider);
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
    return others.any((o) => o.id != candidate.id && _overlaps(candidate, o));
  }

  bool _overlaps(Segment a, Segment b) {
    for (final ia in _intervalsOf(a)) {
      for (final ib in _intervalsOf(b)) {
        if (ia.start < ib.end && ib.start < ia.end) return true;
      }
    }
    return false;
  }

  /// Splits a (possibly midnight-wrapping) segment into one or two
  /// non-wrapping half-open intervals for overlap comparison.
  List<_Interval> _intervalsOf(Segment s) {
    if (s.startMinute == s.endMinute) return const [];
    if (s.startMinute < s.endMinute) {
      return [_Interval(s.startMinute, s.endMinute)];
    }
    return [_Interval(s.startMinute, 1440), _Interval(0, s.endMinute)];
  }
}

class _Interval {
  const _Interval(this.start, this.end);
  final int start;
  final int end;
}
