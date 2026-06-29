import 'package:flutter/material.dart';

import '../../data/models/segment.dart';
import '../segments/segment_icons.dart';

/// T9: whether [segment] gets the wind-down treatment ([SleepWindDown])
/// instead of the usual checklist/rest screen -- the canonical 수면 template
/// icon (bedtime), or '수면' anywhere in the block's name, so a renamed or
/// re-iconed copy of it is still recognised without a separate model field
/// users would have to opt into by hand.
bool isSleepBlock(Segment segment) {
  return segment.iconKey == 'bedtime' || segment.name.contains('수면');
}

/// Sleep block's Focus screen: dims to near-black, guides a slow breathing
/// rhythm, and nudges the phone away -- the opposite of every other block's
/// checklist/timer engagement, since stopping looking at the screen *is* the
/// point. Applies whenever [isSleepBlock] is true, checklist or not -- a
/// checklist (or FocusTimerSection) would directly undercut the "폰
/// 내려놓아요" nudge, so this never falls back to either for a sleep block.
class SleepWindDown extends StatefulWidget {
  const SleepWindDown({
    super.key,
    required this.segment,
    required this.reduceMotion,
    this.remainingMessage,
  });

  final Segment segment;
  final bool reduceMotion;

  /// Null in review mode (FocusPage.forBlock) -- same rule _remainingMessage
  /// already applies for every other composition, since "20분 남음" against
  /// the wall clock is meaningless for a block tapped from the dial that may
  /// be well in the past or future.
  final String? remainingMessage;

  @override
  State<SleepWindDown> createState() => _SleepWindDownState();
}

class _SleepWindDownState extends State<SleepWindDown>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    );
    if (!widget.reduceMotion) {
      _controller.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segment = widget.segment;
    return Container(
      color: Colors.black,
      width: double.infinity,
      height: double.infinity,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                iconForKey(segment.iconKey),
                size: 32,
                color: Colors.white70,
              ),
              const SizedBox(height: 8),
              Text(
                segment.name,
                style: const TextStyle(color: Colors.white70, fontSize: 18),
              ),
              const SizedBox(height: 48),
              widget.reduceMotion
                  ? const _StaticBreathingGuide()
                  : _AnimatedBreathingGuide(controller: _controller),
              const SizedBox(height: 48),
              const Text(
                '이제 폰 내려놓아요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (widget.remainingMessage != null) ...[
                const SizedBox(height: 12),
                Text(
                  widget.remainingMessage!,
                  style: const TextStyle(color: Colors.white54, fontSize: 14),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

const _breathingCircleColor = Color(0x668C9EFF); // indigo-ish, low-opacity
const _breathingCircleBorder = Color(0xFFA7B4FF);

class _AnimatedBreathingGuide extends StatelessWidget {
  const _AnimatedBreathingGuide({required this.controller});

  final AnimationController controller;

  @override
  Widget build(BuildContext context) {
    final scale = CurvedAnimation(parent: controller, curve: Curves.easeInOut);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        // repeat(reverse: true) toggles status between forward (growing --
        // breathing in) and reverse (shrinking -- breathing out) every cycle.
        final breathingIn = controller.status != AnimationStatus.reverse;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Transform.scale(
              scale: 0.6 + (scale.value * 0.4),
              child: Container(
                width: 120,
                height: 120,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: _breathingCircleColor,
                  border: Border.all(color: _breathingCircleBorder, width: 2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              breathingIn ? '들이쉬세요' : '내쉬세요',
              style: const TextStyle(color: Colors.white70, fontSize: 16),
            ),
          ],
        );
      },
    );
  }
}

class _StaticBreathingGuide extends StatelessWidget {
  const _StaticBreathingGuide();

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 96,
          height: 96,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: _breathingCircleColor,
            border: Border.all(color: _breathingCircleBorder, width: 2),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          '천천히 숨을 쉬어보세요',
          style: TextStyle(color: Colors.white70, fontSize: 16),
        ),
      ],
    );
  }
}
