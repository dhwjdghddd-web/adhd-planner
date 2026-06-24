import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';

/// Geometry constants shared between [DialPainter] and the page that hosts
/// it (so tap handling and drawing never disagree on where the ring is).
class DialGeometry {
  const DialGeometry._();

  static const double ringThickness = 24;
  static const double laneGap = 6;
  static const double tickLength = 10;

  /// Outer radius of the first (outermost) segment ring for a dial that
  /// fills a square of [side] pixels.
  static double outerRadius(double side) => side / 2 - 24;

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
/// block arcs (overlapping blocks pushed onto inner lanes, completed ones
/// badged), and the primary current-time hand.
class DialPainter extends CustomPainter {
  DialPainter({
    required this.segments,
    required this.currentMinute,
    required this.tickColor,
    required this.labelStyle,
    required this.handColor,
    required this.brightness,
    this.completedSegmentIds = const {},
  }) : _lanes = DialGeometry.assignLanes(segments);

  final List<Segment> segments;
  final int currentMinute;
  final Color tickColor;
  final TextStyle labelStyle;
  final Color handColor;
  final Brightness brightness;
  // Blocks with a completion recorded for today -- drawn with a small checkmark
  // badge at their arc's midpoint so "did I do this today" is visible at a
  // glance.
  final Set<String> completedSegmentIds;

  final Map<String, int> _lanes;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final outerR = DialGeometry.outerRadius(math.min(size.width, size.height));

    _paintTracks(canvas, center, outerR);
    _paintRim(canvas, center, outerR);
    _paintTicks(canvas, center, outerR);
    _paintSegmentArcs(canvas, center, outerR);
    _paintHand(canvas, center, outerR);
  }

  void _paintTracks(Canvas canvas, Offset center, double outerR) {
    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = DialGeometry.ringThickness
      ..color = tickColor.withValues(alpha: 0.05);

    final outlinePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = tickColor.withValues(alpha: 0.12);

    final lanesCount = _lanes.values.isEmpty ? 1 : _lanes.values.reduce(math.max) + 1;
    for (var lane = 0; lane < lanesCount; lane++) {
      final radius = DialGeometry.laneRadius(outerR, lane);
      // Main track body
      canvas.drawCircle(center, radius, trackPaint);
      // Inner outline
      canvas.drawCircle(center, radius - DialGeometry.ringThickness / 2, outlinePaint);
      // Outer outline
      canvas.drawCircle(center, radius + DialGeometry.ringThickness / 2, outlinePaint);
    }
  }

  void _paintRim(Canvas canvas, Offset center, double outerR) {
    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = tickColor.withValues(alpha: 0.15);
    canvas.drawCircle(center, outerR + DialGeometry.ringThickness / 2 + 4, rimPaint);
  }

  void _paintTicks(Canvas canvas, Offset center, double outerR) {
    final tickRadius = outerR + DialGeometry.ringThickness / 2 + 4;
    final majorHours = [0, 6, 12, 18];

    // 1. Dashed ring effect using fine dots/dashes every 15 minutes
    final dashPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = tickColor.withValues(alpha: 0.2);

    for (var min = 0; min < TimeGeometry.minutesPerDay; min += 15) {
      final inner = TimeGeometry.pointOnCircle(center, tickRadius - 1.5, min);
      final outer = TimeGeometry.pointOnCircle(center, tickRadius + 1.5, min);
      canvas.drawLine(inner, outer, dashPaint);
    }

    // 2. On-the-hour ticks: longer and brighter than the 15-min dashes so
    // every hour boundary (not just 0/6/12/18) reads as a distinct mark.
    final hourPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = tickColor.withValues(alpha: 0.4);

    for (var hour = 0; hour < 24; hour++) {
      if (majorHours.contains(hour)) continue;
      final minute = hour * 60;
      final inner = TimeGeometry.pointOnCircle(center, tickRadius - 5, minute);
      final outer = TimeGeometry.pointOnCircle(center, tickRadius + 1.5, minute);
      canvas.drawLine(inner, outer, hourPaint);
    }

    // 3. 4 major ticks: 0, 6, 12, 18
    final majorPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..color = tickColor.withValues(alpha: 0.5);

    for (final hour in majorHours) {
      final minute = hour * 60;
      final inner = TimeGeometry.pointOnCircle(
          center, tickRadius - DialGeometry.tickLength, minute);
      final outer = TimeGeometry.pointOnCircle(center, tickRadius, minute);
      canvas.drawLine(inner, outer, majorPaint);

      // Major labels (0시, 6시, 12시, 18시). A single fixed radial offset
      // can't clear the tick band for every label: at 0시/12시 the text's
      // width runs tangentially, so only its (small) height eats into the
      // radial gap, but at 6시/18시 the text's width runs radially, so the
      // full glyph width does -- a "1" pulled in close enough to clear the
      // screen edge then lands on top of the tick marks instead. Measure
      // each label and push it out by its own radius-aligned half-extent
      // (half-height at top/bottom, half-width at left/right) so every
      // label clears the outermost tick (tickRadius + 1.5) by the same
      // visual gap, regardless of glyph count.
      final tp = TextPainter(
        text: TextSpan(text: '$hour시', style: labelStyle),
        textDirection: TextDirection.ltr,
      )..layout();
      final isHorizontal = hour == 6 || hour == 18;
      final halfExtent = isHorizontal ? tp.width / 2 : tp.height / 2;
      const clearanceGap = 3.0;
      final labelRadius = tickRadius + 1.5 + clearanceGap + halfExtent;
      final labelPoint = TimeGeometry.pointOnCircle(center, labelRadius, minute);
      tp.paint(canvas, labelPoint - Offset(tp.width / 2, tp.height / 2));
    }
  }

  void _paintSegmentArcs(Canvas canvas, Offset center, double outerR) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = DialGeometry.ringThickness
      ..strokeCap = StrokeCap.round; // Round-cap spec

    for (final segment in segments) {
      if (segment.lengthMinutes <= 0) continue;
      final lane = _lanes[segment.id] ?? 0;
      final radius = DialGeometry.laneRadius(outerR, lane);
      final rect = Rect.fromCircle(center: center, radius: radius);
      
      // Calculate start angle and sweep in radians
      final startAngle = TimeGeometry.minuteToRadians(segment.startMinute);
      final sweep = segment.lengthMinutes / TimeGeometry.minutesPerDay * 2 * math.pi;
      
      paint.color = getEffectiveSegmentColor(segment.color, brightness);
      canvas.drawArc(rect, startAngle, sweep, false, paint);
      _paintSegmentLabel(canvas, center, radius, segment);

      if (segment.microSteps.isNotEmpty && completedSegmentIds.contains(segment.id)) {
        final midMinute = (segment.startMinute + segment.lengthMinutes / 2).round();
        _paintCompletedBadge(canvas, TimeGeometry.pointOnCircle(center, radius, midMinute));
      }
    }
  }

  /// A short, horizontal (not curved) label at the midpoint of the
  /// segment's own arc.
  void _paintSegmentLabel(Canvas canvas, Offset center, double radius, Segment segment) {
    final arcLength = radius * (segment.lengthMinutes / TimeGeometry.minutesPerDay) * 2 * math.pi;
    const minArcLength = 34.0; // Increased due to larger font & padding
    if (arcLength < minArcLength) return;

    final midMinute = (segment.startMinute + segment.lengthMinutes / 2).round();
    final point = TimeGeometry.pointOnCircle(center, radius, midMinute);
    
    final themeColor = getEffectiveSegmentColor(segment.color, brightness);
    final textColor = onSegmentColor(themeColor);
    final tp = TextPainter(
      text: TextSpan(
        text: segment.name,
        style: TextStyle(fontSize: 10, color: textColor, fontWeight: FontWeight.w600, fontFamily: 'Pretendard'),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: arcLength - 6);
    tp.paint(canvas, point - Offset(tp.width / 2, tp.height / 2));
  }

  /// Small checkmark badge centred on a completed block's arc midpoint.
  void _paintCompletedBadge(Canvas canvas, Offset markerPoint) {
    final badgeCenter = markerPoint;
    const badgeRadius = 9.0;
    canvas.drawCircle(badgeCenter, badgeRadius + 1.5, Paint()..color = Colors.white);
    
    // Use the theme's success color if available, or a fallback green
    final greenColor = brightness == Brightness.dark ? const Color(0xFF8FD0A6) : const Color(0xFF3F9D6A);
    canvas.drawCircle(badgeCenter, badgeRadius, Paint()..color = greenColor);

    final tp = TextPainter(
      text: TextSpan(
        text: String.fromCharCode(Icons.check.codePoint),
        style: TextStyle(
          fontSize: badgeRadius * 1.3,
          fontFamily: Icons.check.fontFamily,
          package: Icons.check.fontPackage,
          color: Colors.white,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, badgeCenter - Offset(tp.width / 2, tp.height / 2));
  }

  void _paintHand(Canvas canvas, Offset center, double outerR) {
    final handPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0 // 3px hand spec
      ..color = handColor;
    
    final tip = TimeGeometry.pointOnCircle(
        center, outerR + DialGeometry.ringThickness / 2 + 4, currentMinute);
    canvas.drawLine(center, tip, handPaint);
    canvas.drawCircle(center, 6, Paint()..color = handColor);
  }

  @override
  bool shouldRepaint(DialPainter oldDelegate) {
    return oldDelegate.currentMinute != currentMinute ||
        oldDelegate.brightness != brightness ||
        !_sameSegments(oldDelegate.segments, segments) ||
        oldDelegate.tickColor != tickColor ||
        oldDelegate.handColor != handColor ||
        !oldDelegate.completedSegmentIds.containsAll(completedSegmentIds) ||
        !completedSegmentIds.containsAll(oldDelegate.completedSegmentIds);
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
}
