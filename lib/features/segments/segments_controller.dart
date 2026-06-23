import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../services/notification_service.dart';

final segmentsControllerProvider = Provider<SegmentsController>(
  (ref) => SegmentsController(ref),
);

/// Thin write-side wrapper around [PlannerRepository] for blocks (segments):
/// keeps overlap detection and reordering logic out of the widgets so it can
/// be unit-tested on its own. Every write re-runs
/// [NotificationService.rescheduleAll] against the fresh block list, so the
/// start-of-block alarms always match whatever the user just saved or deleted.
class SegmentsController {
  SegmentsController(this._ref);

  final Ref _ref;

  Future<void> upsert(Segment segment) async {
    await _ref.read(plannerRepositoryProvider)!.upsertSegment(segment);
    await _rescheduleAll();
  }

  /// Deletes a block, cancelling its still-armed alarms first -- rescheduleAll
  /// only rebuilds from blocks still in the list, so a deleted block's alarms
  /// (and the Vibrator alarms riding alongside them) would otherwise never get
  /// cancelled. See [NotificationService.cancelBlockAlarms].
  Future<void> delete(String id) async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    final segments = await repo.watchSegments().first;
    for (final segment in segments) {
      if (segment.id == id) {
        await _ref.read(notificationServiceProvider).cancelBlockAlarms(segment);
        break;
      }
    }
    await repo.deleteSegment(id);
    await _rescheduleAll();
  }

  Future<void> _rescheduleAll() async {
    final repo = _ref.read(plannerRepositoryProvider)!;
    final segments = await repo.watchSegments().first;
    final settings = await repo.watchSettings().first;
    await _ref.read(notificationServiceProvider).rescheduleAll(segments, settings);
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
