import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Single source of truth for converting between minute-of-day (0~1440) and
/// angles/points on the 24h circular dial. Shared by the dial painter, the
/// segment/routine editors, and the focus countdown ring so they never drift
/// out of sync with each other.
///
/// Convention: 0 minute (midnight) sits at the 12 o'clock position, and
/// minutes progress clockwise.
class TimeGeometry {
  static const int minutesPerDay = 1440;

  /// Minute-of-day (0~1440) -> radians, clockwise from 12 o'clock.
  /// Canvas angles are 0=3 o'clock with counter-clockwise positive, so we
  /// rotate by -90deg (-pi/2) to align 0 minute with 12 o'clock.
  static double minuteToRadians(int minute) {
    final frac = _wrapMinute(minute) / minutesPerDay;
    return frac * 2 * math.pi - math.pi / 2;
  }

  /// Minute-of-day -> degrees (0~360), 12 o'clock = 0, clockwise.
  static double minuteToDegrees(int minute) =>
      _wrapMinute(minute) / minutesPerDay * 360.0;

  /// Point on a circle of radius [r] centered at [center] for the given
  /// minute-of-day.
  static Offset pointOnCircle(Offset center, double r, int minute) {
    final a = minuteToRadians(minute);
    return Offset(center.dx + r * math.cos(a), center.dy + r * math.sin(a));
  }

  /// Inverse transform: a tapped/dragged point on the dial -> nearest
  /// minute-of-day. Used for drag-editing segments/routines on the circle.
  static int offsetToMinute(Offset center, Offset point) {
    final a = math.atan2(point.dy - center.dy, point.dx - center.dx) + math.pi / 2;
    final frac = (a / (2 * math.pi)) % 1.0;
    final f = frac < 0 ? frac + 1.0 : frac;
    return (f * minutesPerDay).round() % minutesPerDay;
  }

  /// Length in minutes from [startMinute] to [endMinute], wrapping past
  /// midnight (e.g. 22:00 -> 02:00 is 240 minutes, not negative).
  static int lengthMinutes(int startMinute, int endMinute) {
    return (_wrapMinute(endMinute) - _wrapMinute(startMinute) + minutesPerDay) %
        minutesPerDay;
  }

  /// Formats a minute-of-day as "HH:mm".
  static String formatMinute(int minute) {
    final m = _wrapMinute(minute);
    final h = m ~/ 60;
    final mm = m % 60;
    return '${h.toString().padLeft(2, '0')}:${mm.toString().padLeft(2, '0')}';
  }

  static int _wrapMinute(int minute) =>
      ((minute % minutesPerDay) + minutesPerDay) % minutesPerDay;
}
