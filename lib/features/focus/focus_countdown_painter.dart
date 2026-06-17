import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Draws a single circular countdown ring: a faint full-circle track plus a
/// sweep arc for the remaining-time fraction. Deliberately has no tween/
/// animation controller of its own — callers just repaint with a fresh
/// [progress] value on each clock tick, which is how this respects
/// `AppSettings.reduceMotion` (there is no motion to begin with).
class FocusCountdownPainter extends CustomPainter {
  FocusCountdownPainter({
    required this.progress,
    required this.trackColor,
    required this.progressColor,
    required this.strokeWidth,
  });

  /// Remaining-time fraction, 0.0 (done) .. 1.0 (just started).
  final double progress;
  final Color trackColor;
  final Color progressColor;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = math.min(size.width, size.height) / 2 - strokeWidth / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final trackPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = trackColor;
    canvas.drawCircle(center, radius, trackPaint);

    final clamped = progress.clamp(0.0, 1.0);
    if (clamped <= 0) return;
    final progressPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..color = progressColor;
    const startAngle = -math.pi / 2;
    final sweep = clamped * 2 * math.pi;
    canvas.drawArc(rect, startAngle, sweep, false, progressPaint);
  }

  @override
  bool shouldRepaint(FocusCountdownPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.trackColor != trackColor ||
        oldDelegate.progressColor != progressColor ||
        oldDelegate.strokeWidth != strokeWidth;
  }
}
