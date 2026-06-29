import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';

import '../focus/rest_quotes.dart';

/// Streak lengths (in days, counting today) that get a special line in the
/// completion celebration instead of the plain "다 끝냈어요" message alone.
/// Deliberately sparse and front-loaded (3/7 come quickly, then spread out) so
/// the celebration doesn't habituate into "just another number" -- a varied,
/// occasional bonus reads as more meaningful than a constant daily counter.
const Set<int> celebrationMilestones = {3, 7, 14, 30, 60, 100};

/// Full-screen "you finished everything today" celebration: a burst of confetti
/// over a warm one-line message. Shown at most once a day (the caller gates on a
/// persisted day-key — see _CompletionCelebrator in app.dart), the moment the
/// last of today's checklist items is ticked, wherever that happens.
///
/// [reduceMotion] swaps the confetti for a calm static badge so the celebration
/// still lands for users who turned animations off. [streakDays] is the
/// current streak length (today included) -- when it lands on
/// [celebrationMilestones], an extra line celebrates the streak itself rather
/// than just today; on any other day the celebration looks exactly as before
/// (no streak number shown, so non-milestone days never feel like "only N,
/// not enough").
Future<void> showCompletionCelebration(
  BuildContext context, {
  required bool reduceMotion,
  int streakDays = 0,
}) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '오늘 완료 축하',
    barrierColor: Colors.black.withValues(alpha: 0.55),
    transitionDuration: const Duration(milliseconds: 250),
    pageBuilder: (context, _, _) => _CompletionCelebration(
      reduceMotion: reduceMotion,
      streakDays: streakDays,
    ),
  );
}

class _CompletionCelebration extends StatefulWidget {
  const _CompletionCelebration({
    required this.reduceMotion,
    this.streakDays = 0,
  });

  final bool reduceMotion;
  final int streakDays;

  @override
  State<_CompletionCelebration> createState() => _CompletionCelebrationState();
}

class _CompletionCelebrationState extends State<_CompletionCelebration> {
  late final ConfettiController _confetti;

  @override
  void initState() {
    super.initState();
    _confetti = ConfettiController(duration: const Duration(seconds: 2));
    if (!widget.reduceMotion) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _confetti.play());
    }
  }

  @override
  void dispose() {
    _confetti.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        onTap: () => Navigator.of(context).maybePop(),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Confetti rains from the top-centre downward.
            if (!widget.reduceMotion)
              Align(
                alignment: Alignment.topCenter,
                child: ConfettiWidget(
                  confettiController: _confetti,
                  blastDirection: math.pi / 2,
                  emissionFrequency: 0.05,
                  numberOfParticles: 20,
                  maxBlastForce: 22,
                  minBlastForce: 8,
                  gravity: 0.25,
                  shouldLoop: false,
                ),
              ),
            LayoutBuilder(
              builder: (context, constraints) => SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          widget.reduceMotion
                              ? Icon(
                                  Icons.celebration,
                                  size: 96,
                                  color: theme.colorScheme.primary,
                                )
                              : TweenAnimationBuilder<double>(
                                  tween: Tween(begin: 0.4, end: 1.0),
                                  duration: const Duration(milliseconds: 400),
                                  curve: Curves.elasticOut,
                                  builder: (context, scale, child) =>
                                      Transform.scale(
                                        scale: scale,
                                        child: child,
                                      ),
                                  child: Icon(
                                    Icons.celebration,
                                    size: 96,
                                    color: theme.colorScheme.primary,
                                  ),
                                ),
                          const SizedBox(height: 24),
                          Text(
                            '오늘 할 일을 다 끝냈어요!',
                            style: theme.textTheme.headlineSmall?.copyWith(
                              color: Colors.white,
                              fontWeight: FontWeight.w700,
                            ),
                            textAlign: TextAlign.center,
                          ),
                          if (celebrationMilestones.contains(
                            widget.streakDays,
                          )) ...[
                            const SizedBox(height: 8),
                            Text(
                              '${widget.streakDays}일 연속, 정말 멋져요!',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: theme.colorScheme.primary,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                          const SizedBox(height: 12),
                          Text(
                            restQuoteForToday(),
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: Colors.white.withValues(alpha: 0.85),
                            ),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 32),
                          FilledButton(
                            onPressed: () => Navigator.of(context).maybePop(),
                            child: const Text('고마워요'),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
