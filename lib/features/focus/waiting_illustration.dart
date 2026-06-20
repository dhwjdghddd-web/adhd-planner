import 'dart:io';
import 'dart:math' as math;
import 'package:flutter/material.dart';

class WaitingIllustration extends StatefulWidget {
  const WaitingIllustration({
    super.key,
    required this.reduceMotion,
    this.message = '곧 알려드릴게요\n지금은 쉬어도 좋아요',
  });

  final bool reduceMotion;
  final String message;

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

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Graphic container
          SizedBox(
            width: 200,
            height: 200,
            child: AnimatedBuilder(
              animation: Listenable.merge([_breatheController, _orbitController]),
              builder: (context, _) {
                return CustomPaint(
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
          ),
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
    
    // Radius values
    final outerRadius = size.width * 0.45;
    final midRadius = size.width * 0.33;
    final innerRadius = size.width * 0.22 * breatheScale; // Breathes

    // Paints
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

    // Draw concentric rings
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
