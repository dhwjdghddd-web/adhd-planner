import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';

/// Minutes left in [segment] counting from [currentMinute], accounting for a
/// midnight-wrapping block (e.g. 22:00~02:00). Only meaningful while
/// [currentMinute] actually falls inside the block (i.e. its
/// [BlockStatus.isCurrent] is true) -- pure (takes "now" as a parameter) so
/// it's testable without a real clock.
int blockRemainingMinutes(Segment segment, int currentMinute) {
  final end = segment.endMinute > segment.startMinute
      ? segment.endMinute
      : segment.endMinute + TimeGeometry.minutesPerDay;
  final now = currentMinute >= segment.startMinute
      ? currentMinute
      : currentMinute + TimeGeometry.minutesPerDay;
  final remaining = end - now;
  return remaining < 0 ? 0 : remaining;
}

/// "20분 남음" under an hour, "1시간 20분 남음" at or over one -- a whole-hour
/// remainder collapses to "1시간 남음" rather than "1시간 0분 남음".
String formatRemaining(int minutes) {
  if (minutes < 60) return '$minutes분 남음';
  final hours = minutes ~/ 60;
  final mins = minutes % 60;
  return mins == 0 ? '$hours시간 남음' : '$hours시간 $mins분 남음';
}

/// 0.0 (just started) to 1.0 (about to end) of [segment]'s range, counting
/// from [currentMinute] -- what [WaitingIllustration.progress] draws as the
/// ring composition's outermost arc. Only meaningful while [currentMinute]
/// actually falls inside the block, same caveat as [blockRemainingMinutes].
double blockProgressFraction(Segment segment, int currentMinute) {
  final total = segment.lengthMinutes;
  if (total == 0) return 0;
  final remaining = blockRemainingMinutes(segment, currentMinute);
  return (1 - remaining / total).clamp(0.0, 1.0);
}
