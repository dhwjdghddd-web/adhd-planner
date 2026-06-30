import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/minute_ticker.dart';

void main() {
  group('millisUntilNextMinute', () {
    test('at the very start of a minute, waits ~a full minute', () {
      final t = DateTime(2026, 6, 30, 10, 15, 0, 0);
      expect(millisUntilNextMinute(t), 60000 + 50);
    });

    test('mid-minute, waits the remainder plus the buffer', () {
      final t = DateTime(2026, 6, 30, 10, 15, 30, 0); // 30s in
      expect(millisUntilNextMinute(t), 30000 + 50);
    });

    test('accounts for sub-second millis', () {
      final t = DateTime(2026, 6, 30, 10, 15, 45, 250); // 45.250s in
      expect(millisUntilNextMinute(t), 60000 - 45250 + 50);
    });

    test('just before the boundary, still positive (never zero/negative)', () {
      final t = DateTime(2026, 6, 30, 10, 15, 59, 999);
      final ms = millisUntilNextMinute(t);
      expect(ms, greaterThan(0));
      expect(ms, 60000 - 59999 + 50); // = 51ms
    });
  });

  testWidgets('MinuteTicker fires across a minute boundary and re-arms', (
    tester,
  ) async {
    var fires = 0;
    final ticker = MinuteTicker(() => fires++)..start();
    addTearDown(ticker.cancel);

    // testWidgets runs in a fake-async zone, so advancing the clock fires the
    // scheduled Timer. Two minutes should produce at least two fires (proving
    // it re-arms rather than firing once and stopping). The exact count can be
    // 2-3 depending on where real DateTime.now() sat at start, so assert >=2.
    await tester.pump(const Duration(minutes: 2, seconds: 1));
    expect(fires, greaterThanOrEqualTo(2));

    final afterCancel = fires;
    ticker.cancel();
    await tester.pump(const Duration(minutes: 2));
    expect(fires, afterCancel); // no more fires once cancelled
  });
}
