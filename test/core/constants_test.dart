import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/core/constants.dart';

void main() {
  group('onSegmentColor', () {
    test('uses a dark glyph on clearly light fills (the wash-out case)', () {
      // The light end — pure white and the lightest dark-mode pastel (amber) —
      // is exactly where a hardcoded white glyph disappears.
      expect(onSegmentColor(Colors.white), Colors.black87);
      expect(onSegmentColor(const Color(0xFFDBC084)), Colors.black87); // dark-mode amber
    });

    test('uses a white glyph on clearly dark fills', () {
      // Light-mode teal/slate are dark enough that white reads cleanly.
      expect(onSegmentColor(const Color(0xFF3E9A92)), Colors.white); // light-mode teal
      expect(onSegmentColor(const Color(0xFF717C89)), Colors.white); // light-mode slate
      expect(onSegmentColor(Colors.black), Colors.white);
    });
  });
}
