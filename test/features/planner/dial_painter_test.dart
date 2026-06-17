import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/features/planner/dial_painter.dart';

Segment _segment(String id, int start, int end) => Segment(
      id: id,
      name: id,
      colorValue: 0xFF000000,
      iconKey: 'wb_sunny',
      startMinute: start,
      endMinute: end,
      order: 0,
    );

DialPainter _painter({
  required List<Segment> segments,
  required int currentMinute,
}) {
  return DialPainter(
    segments: segments,
    routines: const [],
    currentMinute: currentMinute,
    tickColor: Colors.black,
    labelStyle: const TextStyle(fontSize: 11),
    handColor: Colors.red,
  );
}

void main() {
  group('DialPainter.shouldRepaint', () {
    test('false when nothing relevant changed', () {
      final segments = [_segment('a', 0, 60)];
      final oldPainter = _painter(segments: segments, currentMinute: 5);
      final newPainter = _painter(segments: segments, currentMinute: 5);
      expect(newPainter.shouldRepaint(oldPainter), false);
    });

    test('true when current minute changes', () {
      final segments = [_segment('a', 0, 60)];
      final oldPainter = _painter(segments: segments, currentMinute: 5);
      final newPainter = _painter(segments: segments, currentMinute: 6);
      expect(newPainter.shouldRepaint(oldPainter), true);
    });

    test('true when a segment time changes', () {
      final oldPainter =
          _painter(segments: [_segment('a', 0, 60)], currentMinute: 5);
      final newPainter =
          _painter(segments: [_segment('a', 0, 90)], currentMinute: 5);
      expect(newPainter.shouldRepaint(oldPainter), true);
    });
  });
}
