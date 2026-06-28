import 'dart:math' as math;

import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';

/// One brain-dumped item with a suggested time slot, before the user reviews
/// and (optionally) adjusts it in the preview step.
class SuggestedSlot {
  const SuggestedSlot({
    required this.text,
    required this.startMinute,
    required this.endMinute,
  });

  final String text;
  final int startMinute;
  final int endMinute;

  SuggestedSlot copyWith({int? startMinute, int? endMinute}) => SuggestedSlot(
        text: text,
        startMinute: startMinute ?? this.startMinute,
        endMinute: endMinute ?? this.endMinute,
      );
}

/// Default length given to each brain-dumped item, in minutes.
const int kSuggestedSlotMinutes = 30;

/// The first reasonable minute to start suggesting slots from: the later of
/// "[nowMinute] rounded up to the next half hour" and the end of today's
/// latest existing block -- so a brain-dump never suggests a time that's
/// already passed, or before the day's current last block has even ended.
/// Pure (takes "now" as a parameter) so it's testable without a real clock.
int anchorMinuteFor(int nowMinute, List<Segment> existingSegments) {
  final roundedNow = ((nowMinute + 29) ~/ 30) * 30;
  var anchor = roundedNow;
  for (final segment in existingSegments) {
    // Same-day blocks only (end > start) -- a midnight-wrapping block's end
    // is tomorrow morning, not "later today", so it shouldn't push the
    // anchor forward as if it were.
    if (segment.endMinute > segment.startMinute && segment.endMinute > anchor) {
      anchor = segment.endMinute;
    }
  }
  return math.min(anchor, TimeGeometry.minutesPerDay);
}

/// Pure, deterministic: suggests a same-day time slot for each of [items] in
/// order, starting after [anchorMinute] and pushed later still to skip past
/// any of [existingSegments]'s ranges -- so a brain-dump never silently lands
/// on top of a block that's already on the dial. Each item gets
/// [kSuggestedSlotMinutes] by default.
///
/// Stops placing (returning fewer slots than [items]) the moment a candidate
/// would run past midnight -- the caller surfaces that as "the rest didn't
/// fit today" rather than wrapping into a nonsensical end < start range.
List<SuggestedSlot> suggestSlots(
  List<String> items,
  List<Segment> existingSegments, {
  required int anchorMinute,
}) {
  final slots = <SuggestedSlot>[];
  var cursor = anchorMinute;

  for (final text in items) {
    cursor = _nextFreeStart(cursor, existingSegments);
    final end = cursor + kSuggestedSlotMinutes;
    if (end > TimeGeometry.minutesPerDay) break;

    slots.add(SuggestedSlot(text: text, startMinute: cursor, endMinute: end));
    cursor = end;
  }

  return slots;
}

/// The next minute at or after [from] that doesn't fall inside any of
/// [segments]' ranges -- walks forward past whichever block a candidate start
/// lands inside, repeating until clear (a candidate could land inside more
/// than one overlapping block in a row). Bounded to one pass over
/// [minutesPerDay] worth of pushes so a pathological overlap pattern can't
/// loop forever.
int _nextFreeStart(int from, List<Segment> segments) {
  var candidate = from;
  for (var guard = 0; guard < TimeGeometry.minutesPerDay; guard++) {
    var moved = false;
    for (final segment in segments) {
      if (!segment.containsMinute(candidate)) continue;
      // A same-day block always pushes candidate strictly forward
      // (end > start, and candidate is inside it, so end > candidate too).
      // A midnight-wrapping block (end < start) could otherwise push
      // candidate *backward* into tomorrow's early minutes -- treat that as
      // "blocked for the rest of today" instead, which the caller's
      // end > minutesPerDay check turns into "stop suggesting more today".
      candidate = segment.endMinute > candidate
          ? segment.endMinute
          : TimeGeometry.minutesPerDay;
      moved = true;
    }
    if (!moved) break;
  }
  return candidate;
}
