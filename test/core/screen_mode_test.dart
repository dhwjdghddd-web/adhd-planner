import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/screen_mode.dart';

void main() {
  group('computeCompactLayout', () {
    test('on-cover flag makes an ambiguous mid-height compact', () {
      // Between the compact breakpoint and the main-display ceiling, the OS
      // display signal decides.
      expect(computeCompactLayout(heightDp: 600, onCoverDisplay: true), true);
      expect(computeCompactLayout(heightDp: 600, onCoverDisplay: false), false);
    });

    test('a stale on-cover flag never keeps a tall main screen compact', () {
      // Regression: after unfolding, coverDisplayActive can lag true for a
      // moment; a clearly-tall screen (Z Flip7 main ≈ 840dp) must still drop
      // back to the full layout rather than staying stuck in cover mode.
      expect(computeCompactLayout(heightDp: 840, onCoverDisplay: true), false);
    });

    test(
      'compact when shorter than the breakpoint, even on the primary display',
      () {
        // Z Flip7 cover ≈ 399dp tall.
        expect(
          computeCompactLayout(heightDp: 399, onCoverDisplay: false),
          true,
        );
      },
    );

    test('not compact on a normal tall phone main screen', () {
      // Z Flip7 main ≈ 840dp tall.
      expect(computeCompactLayout(heightDp: 840, onCoverDisplay: false), false);
    });

    test('breakpoint boundary: exactly the threshold is NOT compact', () {
      expect(
        computeCompactLayout(heightDp: kCompactHeightDp, onCoverDisplay: false),
        false,
      );
      expect(
        computeCompactLayout(
          heightDp: kCompactHeightDp - 1,
          onCoverDisplay: false,
        ),
        true,
      );
    });
  });
}
