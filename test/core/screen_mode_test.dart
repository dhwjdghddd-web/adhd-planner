import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/screen_mode.dart';

void main() {
  group('computeCompactLayout', () {
    test('compact when on a cover display, whatever the height', () {
      expect(computeCompactLayout(heightDp: 840, onCoverDisplay: true), true);
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
