import '../core/time_geometry.dart';
import 'models/segment.dart';

/// Whatever the home dial's centre summary and the Focus screen agree is the
/// block "happening now" (or coming up next), for a given moment. Both call
/// [findBlockStatus] rather than keep their own copy so they never disagree.
class BlockStatus {
  const BlockStatus({this.segment, this.isCurrent = false, this.remainingMinutes = 0});

  final Segment? segment;
  final bool isCurrent;
  final int remainingMinutes;
}

/// The block that contains [nowMinute] (its time range covers now), or — if
/// none does (a gap between blocks) — the soonest block still ahead today.
///
/// When several overlapping blocks contain now, the one that started most
/// recently wins, so the summary reflects the most specific/innermost block
/// the user just entered rather than a long outer one. Blocks recur every day,
/// so there's no weekday filtering.
BlockStatus findBlockStatus(List<Segment> segments, int nowMinute) {
  // 1. Current: the most-recently-started block whose range covers now.
  Segment? current;
  var bestElapsed = TimeGeometry.minutesPerDay + 1;
  for (final segment in segments) {
    if (segment.lengthMinutes <= 0) continue;
    if (!segment.containsMinute(nowMinute)) continue;
    // Minutes since this block started (mod day, so a wrapping block that
    // began last night still measures correctly).
    final elapsed = (nowMinute - segment.startMinute + TimeGeometry.minutesPerDay) %
        TimeGeometry.minutesPerDay;
    if (elapsed < bestElapsed) {
      bestElapsed = elapsed;
      current = segment;
    }
  }
  if (current != null) return BlockStatus(segment: current, isCurrent: true);

  // 2. No current block: the soonest block still ahead today.
  Segment? next;
  var bestDelta = TimeGeometry.minutesPerDay + 1;
  for (final segment in segments) {
    if (segment.lengthMinutes <= 0) continue;
    final delta = (segment.startMinute - nowMinute + TimeGeometry.minutesPerDay) %
        TimeGeometry.minutesPerDay;
    if (delta >= 0 && delta < bestDelta) {
      bestDelta = delta;
      next = segment;
    }
  }
  if (next == null) return const BlockStatus();
  return BlockStatus(segment: next, isCurrent: false, remainingMinutes: bestDelta);
}
