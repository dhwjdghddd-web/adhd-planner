import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaitingIllustration extends StatefulWidget {
  const WaitingIllustration({
    super.key,
    required this.reduceMotion,
    this.message = '곧 알려드릴게요\n지금은 쉬어도 좋아요',
    this.center,
    this.size = 200,
  });

  final bool reduceMotion;
  final String message;

  /// Optional widget sat at the dead centre of the rings (inside the inner
  /// breathing ring), so the composition can read as one object — e.g. a
  /// block's icon + name at its heart, echoing the dial's centre hub — instead
  /// of a separate header floating above an empty graphic.
  final Widget? center;

  /// Square edge of the ring graphic. Bigger when something sits at the centre
  /// (it needs room inside the inner ring) than for a plain waiting state.
  final double size;

  @override
  State<WaitingIllustration> createState() => _WaitingIllustrationState();
}

class _WaitingIllustrationState extends State<WaitingIllustration>
    with TickerProviderStateMixin {
  late AnimationController _breatheController;
  late AnimationController _orbitController;
  late Animation<double> _breatheAnimation;

  bool get _shouldAnimate {
    if (widget.reduceMotion) return false;
    // Suppress infinite animations in test environment to avoid pumpAndSettle timeouts
    try {
      if (Platform.environment.containsKey('FLUTTER_TEST')) return false;
    } catch (_) {}
    return true;
  }

  @override
  void initState() {
    super.initState();
    
    // Breathe animation: scale 1.0 -> 1.04 -> 1.0, 4 seconds duration
    _breatheController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    _breatheAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(
        parent: _breatheController,
        curve: Curves.easeInOut,
      ),
    );

    // Orbit animation: 0.0 -> 1.0 (0 to 360 degrees), 12 seconds duration
    _orbitController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 12),
    );

    if (_shouldAnimate) {
      _breatheController.repeat(reverse: true);
      _orbitController.repeat();
    }
  }

  @override
  void didUpdateWidget(covariant WaitingIllustration oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.reduceMotion != oldWidget.reduceMotion) {
      if (_shouldAnimate) {
        _breatheController.repeat(reverse: true);
        _orbitController.repeat();
      } else {
        _breatheController.stop();
        _orbitController.stop();
      }
    }
  }

  @override
  void dispose() {
    _breatheController.dispose();
    _orbitController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    final hasMessage = widget.message.isNotEmpty;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Graphic container
          SizedBox(
            width: widget.size,
            height: widget.size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                AnimatedBuilder(
                  animation: Listenable.merge([_breatheController, _orbitController]),
                  builder: (context, _) {
                    return CustomPaint(
                      size: Size(widget.size, widget.size),
                      painter: _ConcentricRingsPainter(
                        breatheScale: _breatheAnimation.value,
                        orbitAngle: _orbitController.value * 2 * math.pi,
                        primaryColor: theme.colorScheme.primary,
                        outlineColor: theme.colorScheme.outline,
                        isDark: isDark,
                      ),
                    );
                  },
                ),
                if (widget.center != null) widget.center!,
              ],
            ),
          ),
          if (hasMessage) ...[
            const SizedBox(height: 32),
            Column(
              mainAxisSize: MainAxisSize.min,
              children: widget.message.split('\n').map((line) {
                return Text(
                  line,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68),
                    height: 1.3,
                  ),
                  textAlign: TextAlign.center,
                );
              }).toList(),
            ),
          ],
        ],
      ),
    );
  }
}

class _ConcentricRingsPainter extends CustomPainter {
  const _ConcentricRingsPainter({
    required this.breatheScale,
    required this.orbitAngle,
    required this.primaryColor,
    required this.outlineColor,
    required this.isDark,
  });

  final double breatheScale;
  final double orbitAngle;
  final Color primaryColor;
  final Color outlineColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    // Radius values. The whole composition is pushed a little larger (and an
    // extra ripple ring added beyond the old outer one) so it fills more of the
    // void instead of sitting as a small graphic in a lot of empty space —
    // PDF 10's "the void fills with calm concentric ripples".
    final rippleRadius = size.width * 0.49;
    final outerRadius = size.width * 0.42;
    final midRadius = size.width * 0.34;
    final innerRadius = size.width * 0.26 * breatheScale; // Breathes

    // Soft glow behind the rings so the centre reads as gently lit rather than
    // a flat hole — a blurred, low-alpha primary disc that breathes with the
    // inner ring.
    final glowPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primaryColor.withValues(alpha: isDark ? 0.13 : 0.08)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 28);
    canvas.drawCircle(center, midRadius * breatheScale, glowPaint);

    // Paints
    final ripplePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = outlineColor.withValues(alpha: 0.06);

    final faintPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0
      ..color = outlineColor.withValues(alpha: 0.12);

    final midPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = outlineColor.withValues(alpha: 0.2);

    final primaryInnerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = primaryColor.withValues(alpha: 0.35);

    final dotPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = primaryColor;

    // Draw concentric rings, faintest and widest first
    canvas.drawCircle(center, rippleRadius, ripplePaint);
    canvas.drawCircle(center, outerRadius, faintPaint);
    canvas.drawCircle(center, midRadius, midPaint);
    canvas.drawCircle(center, innerRadius, primaryInnerPaint);

    // Draw a single small dot on the mid orbit marking "what's next"
    final dotX = center.dx + midRadius * math.cos(orbitAngle);
    final dotY = center.dy + midRadius * math.sin(orbitAngle);
    canvas.drawCircle(Offset(dotX, dotY), 4.5, dotPaint);
  }

  @override
  bool shouldRepaint(covariant _ConcentricRingsPainter oldDelegate) {
    return oldDelegate.breatheScale != breatheScale ||
        oldDelegate.orbitAngle != orbitAngle ||
        oldDelegate.primaryColor != primaryColor ||
        oldDelegate.outlineColor != outlineColor ||
        oldDelegate.isDark != isDark;
  }
}
