import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../segments/segment_icons.dart';

/// Geometry constants shared between [DialPainter] and the page that hosts
/// it (so tap handling and drawing never disagree on where the ring is).
class DialGeometry {
  const DialGeometry._();

  static const double ringThickness = 28;
  static const double laneGap = 6;
  static const double tickLength = 10;
  static const double routineMarkerRadius = 11;

  /// Outer radius of the first (outermost) segment ring for a dial that
  /// fills a square of [side] pixels.
  static double outerRadius(double side) => side / 2 - 28;

  static double laneRadius(double outerR, int lane) =>
      outerR - lane * (ringThickness + laneGap);

  /// Greedily assigns each segment to the first lane whose existing members
  /// don't overlap it, so overlapping segments render on separate inner
  /// rings instead of stacking on top of each other. Exposed here (rather
  /// than kept private to [DialPainter]) so the planner page's tap
  /// hit-testing can compute the exact same routine-marker positions the
  /// painter drew.
  static Map<String, int> assignLanes(List<Segment> segments) {
    final lanes = <List<Segment>>[];
    final laneOf = <String, int>{};
    for (final segment in segments) {
      var placedLane = -1;
      for (var i = 0; i < lanes.length; i++) {
        if (lanes[i].every((existing) => !existing.overlaps(segment))) {
          placedLane = i;
          break;
        }
      }
      if (placedLane == -1) {
        lanes.add([]);
        placedLane = lanes.length - 1;
      }
      lanes[placedLane].add(segment);
      laneOf[segment.id] = placedLane;
    }
    return laneOf;
  }
}

/// Paints the 24h circular dial: outer rim, hour ticks + labels, coloured
/// segment arcs (overlapping segments pushed onto inner lanes), routine
/// markers, and the red current-time hand.
class DialPainter extends CustomPainter {
  DialPainter({
    required this.segments,
    required this.routines,
    required this.currentMinute,
    required this.tickColor,
    required this.labelStyle,
    required this.handColor,
  }) : _lanes = DialGeometry.assignLanes(segments);

  final List<Segment> segments;
  final List<Routine> routines;
  final int currentMinute;
  final Color tickColor;
  final TextStyle labelStyle;
  final Color handColor;

  final Map<String, int> _lanes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = DialGeometry.outerRadius(math.min(size.width, size.height));

    _paintRim(canvas, center, outerR);
    _paintTicks(canvas, center, outerR);
    _paintSegmentArcs(canvas, center, outerR);
    _paintRoutineMarkers(canvas, center, outerR);
    _paintHand(canvas, center, outerR);
  }

  void _paintRim(Canvas canvas, Offset center, double outerR) {
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = tickColor.withValues(alpha: 0.4);
    canvas.drawCircle(center, outerR + DialGeometry.ringThickness / 2 + 4, rimPaint);
  }

  void _paintTicks(Canvas canvas, Offset center, double outerR) {
    final tickRadius = outerR + DialGeometry.ringThickness / 2 + 4;
    final tickPaint = Paint()
      ..style = PaintingStyle.stroke
      ..color = tickColor;

    for (var hour = 0; hour < 24; hour++) {
      final minute = hour * 60;
      final isMajor = hour % 6 == 0;
      tickPaint.strokeWidth = isMajor ? 2.5 : 1.2;
      final inner = TimeGeometry.pointOnCircle(
          center, tickRadius - (isMajor ? DialGeometry.tickLength : DialGeometry.tickLength * 0.55), minute);
      final outer = TimeGeometry.pointOnCircle(center, tickRadius, minute);
      canvas.drawLine(inner, outer, tickPaint);

      if (isMajor) {
        final labelPoint =
            TimeGeometry.pointOnCircle(center, tickRadius + 16, minute);
        final tp = TextPainter(
          text: TextSpan(text: '$hour시', style: labelStyle),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, labelPoint - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  void _paintSegmentArcs(Canvas canvas, Offset center, double outerR) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = DialGeometry.ringThickness
      ..strokeCap = StrokeCap.butt;

    for (final segment in segments) {
      if (segment.lengthMinutes <= 0) continue;
      final lane = _lanes[segment.id] ?? 0;
      final radius = DialGeometry.laneRadius(outerR, lane);
      final rect = Rect.fromCircle(center: center, radius: radius);
      final startAngle = TimeGeometry.minuteToRadians(segment.startMinute);
      final sweep = segment.lengthMinutes / TimeGeometry.minutesPerDay * 2 * math.pi;
      paint.color = segment.color;
      canvas.drawArc(rect, startAngle, sweep, false, paint);
    }
  }

  void _paintRoutineMarkers(Canvas canvas, Offset center, double outerR) {
    final segmentsById = {for (final s in segments) s.id: s};
    for (final routine in routines) {
      final segment = segmentsById[routine.segmentId];
      final lane = segment != null ? (_lanes[segment.id] ?? 0) : 0;
      final radius = DialGeometry.laneRadius(outerR, lane);
      final point = TimeGeometry.pointOnCircle(center, radius, routine.startMinute);
      final color = segment?.color ?? Colors.grey;

      final dotPaint = Paint()..color = color;
      final borderPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..color = Colors.white;
      canvas.drawCircle(point, DialGeometry.routineMarkerRadius, dotPaint);
      canvas.drawCircle(point, DialGeometry.routineMarkerRadius, borderPaint);

      final icon = iconForKey(segment?.iconKey ?? '');
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(icon.codePoint),
          style: TextStyle(
            fontSize: DialGeometry.routineMarkerRadius * 1.2,
            fontFamily: icon.fontFamily,
            package: icon.fontPackage,
            color: Colors.white,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, point - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _paintHand(Canvas canvas, Offset center, double outerR) {
    final handPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = handColor;
    final tip = TimeGeometry.pointOnCircle(
        center, outerR + DialGeometry.ringThickness / 2 + 4, currentMinute);
    canvas.drawLine(center, tip, handPaint);
    canvas.drawCircle(center, 5, Paint()..color = handColor);
  }

  @override
  bool shouldRepaint(DialPainter oldDelegate) {
    return oldDelegate.currentMinute != currentMinute ||
        !_sameSegments(oldDelegate.segments, segments) ||
        !_sameRoutines(oldDelegate.routines, routines) ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.handColor != handColor;
  }

  static bool _sameSegments(List<Segment> a, List<Segment> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.startMinute != y.startMinute ||
          x.endMinute != y.endMinute ||
          x.colorValue != y.colorValue ||
          x.iconKey != y.iconKey) {
        return false;
      }
    }
    return true;
  }

  static bool _sameRoutines(List<Routine> a, List<Routine> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      final x = a[i];
      final y = b[i];
      if (x.id != y.id ||
          x.startMinute != y.startMinute ||
          x.durationMin != y.durationMin ||
          x.segmentId != y.segmentId) {
        return false;
      }
    }
    return true;
  }
}
