import 'package:flutter_test/flutter_test.dart';
import 'package:adhd_planner/core/time_geometry.dart';

void main() {
  group('TimeGeometry.minuteToDegrees', () {
    test('midnight is 0 degrees', () {
      expect(TimeGeometry.minuteToDegrees(0), 0.0);
    });

    test('6 hours is 90 degrees', () {
      expect(TimeGeometry.minuteToDegrees(360), closeTo(90.0, 1e-9));
    });

    test('12 hours is 180 degrees', () {
      expect(TimeGeometry.minuteToDegrees(720), closeTo(180.0, 1e-9));
    });

    test('wraps minutes beyond a day', () {
      expect(TimeGeometry.minuteToDegrees(1440 + 360), closeTo(90.0, 1e-9));
    });
  });

  group('TimeGeometry.lengthMinutes', () {
    test('same-day range', () => expect(TimeGeometry.lengthMinutes(360, 720), 360));

    test('wraps past midnight', () {
      // 22:00 (1320) -> 02:00 (120) should be 240 minutes.
      expect(TimeGeometry.lengthMinutes(1320, 120), 240);
    });

    test('zero length when start == end', () {
      expect(TimeGeometry.lengthMinutes(600, 600), 0);
    });
  });

  group('TimeGeometry round trip', () {
    const center = Offset(100, 100);
    const radius = 80.0;

    test('pointOnCircle -> offsetToMinute recovers the original minute', () {
      for (final minute in [0, 90, 180, 360, 540, 720, 900, 1080, 1260, 1439]) {
        final point = TimeGeometry.pointOnCircle(center, radius, minute);
        final recovered = TimeGeometry.offsetToMinute(center, point);
        // Allow +-1 minute due to floating point rounding.
        final diff = (recovered - minute).abs();
        expect(diff <= 1 || diff >= 1439, true,
            reason: 'minute=$minute recovered=$recovered');
      }
    });
  });

  group('TimeGeometry.formatMinute', () {
    test('formats as HH:mm', () {
      expect(TimeGeometry.formatMinute(0), '00:00');
      expect(TimeGeometry.formatMinute(90), '01:30');
      expect(TimeGeometry.formatMinute(1439), '23:59');
    });
  });
}
