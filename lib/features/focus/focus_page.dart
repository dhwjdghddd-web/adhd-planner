import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../rewards/streak_badge.dart';
import 'completions_controller.dart';
import 'focus_countdown_painter.dart';

/// '지금' focus screen: shows exactly one routine — whichever covers the
/// current minute — full-screen with a countdown ring, a micro-steps
/// checklist, and three large actions. Everything else is hidden so there's
/// only one thing to look at.
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key});

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  late int _currentMinute;
  late int _isoWeekday;
  Timer? _ticker;
  final Set<int> _checked = {};
  late final ConfettiController _confettiController;
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    _updateClock();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final minute = _minuteOfNow();
      if (minute != _currentMinute) {
        setState(_updateClock);
      }
    });
    _confettiController = ConfettiController(duration: const Duration(milliseconds: 600));
  }

  void _updateClock() {
    _currentMinute = _minuteOfNow();
    _isoWeekday = DateTime.now().weekday;
  }

  int _minuteOfNow() {
    final now = TimeOfDay.now();
    return now.hour * 60 + now.minute;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _confettiController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final routinesAsync = ref.watch(routinesProvider);
    final theme = Theme.of(context);
    final reduceMotion = ref.watch(settingsProvider).value?.reduceMotion ?? false;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            routinesAsync.when(
              data: (routines) => _buildContent(
                context,
                findRoutineStatus(routines, _currentMinute, _isoWeekday),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('오류: $e')),
            ),
            Positioned(
              top: 4,
              left: 4,
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                tooltip: '닫기',
                onPressed: () => Navigator.of(context).pop(),
              ),
            ),
            if (_celebrating)
              Positioned.fill(
                child: IgnorePointer(
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (!reduceMotion)
                        Align(
                          alignment: Alignment.topCenter,
                          child: ConfettiWidget(
                            confettiController: _confettiController,
                            blastDirection: math.pi / 2,
                            numberOfParticles: 24,
                            gravity: 0.3,
                            shouldLoop: false,
                          ),
                        ),
                      reduceMotion
                          ? Icon(Icons.check_circle, size: 96, color: theme.colorScheme.primary)
                          : TweenAnimationBuilder<double>(
                              tween: Tween(begin: 0.4, end: 1.0),
                              duration: const Duration(milliseconds: 350),
                              curve: Curves.elasticOut,
                              builder: (context, scale, child) =>
                                  Transform.scale(scale: scale, child: child),
                              child: Icon(Icons.check_circle, size: 96, color: theme.colorScheme.primary),
                            ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context, RoutineStatus status) {
    final theme = Theme.of(context);
    final routine = status.routine;

    if (routine == null) {
      return Center(
        child: Text('오늘 일정이 없어요', style: theme.textTheme.titleMedium),
      );
    }

    if (!status.isCurrent) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Semantics(
            label: '다음 할 일: ${routine.title}, ${status.remainingMinutes}분 후 시작',
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '다음 루틴까지 ${status.remainingMinutes}분',
                  style: theme.textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 12),
                Text(
                  routine.title,
                  style: theme.textTheme.titleMedium,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      );
    }

    final progress =
        routine.durationMin <= 0 ? 0.0 : status.remainingMinutes / routine.durationMin;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
      child: Semantics(
        label: '지금 집중: ${routine.title}, ${status.remainingMinutes}분 남음',
        child: Column(
          children: [
            SizedBox(
              width: 220,
              height: 220,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  CustomPaint(
                    size: const Size(220, 220),
                    painter: FocusCountdownPainter(
                      progress: progress,
                      trackColor: theme.colorScheme.surfaceContainerHighest,
                      progressColor: theme.colorScheme.primary,
                      strokeWidth: 14,
                    ),
                  ),
                  // Fixed-size ring (matches the dial's own center circle in
                  // planner_page.dart) — clamp locally so this can't grow
                  // past the ring at 200% system text scale.
                  MediaQuery.withClampedTextScaling(
                    maxScaleFactor: 1.3,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            '${status.remainingMinutes}분',
                            style: theme.textTheme.headlineMedium,
                          ),
                          Text('남음', style: theme.textTheme.bodyMedium),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            Text(
              routine.title,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            const StreakBadge(),
            if (routine.microSteps.isNotEmpty) ...[
              const SizedBox(height: 16),
              ...List.generate(routine.microSteps.length, (i) {
                final checked = _checked.contains(i);
                return CheckboxListTile(
                  value: checked,
                  title: Text(routine.microSteps[i]),
                  onChanged: (_) => setState(() {
                    if (checked) {
                      _checked.remove(i);
                    } else {
                      _checked.add(i);
                    }
                  }),
                );
              }),
            ],
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: () => _complete(routine.id),
                child: const Text('완료'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.tonal(
                onPressed: _snooze,
                child: const Text('스누즈'),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(minimumSize: const Size(64, 56)),
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('다음 할 일'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _complete(String routineId) async {
    // Not awaited: Firestore's write Future only resolves once the backend
    // acknowledges it, which never happens while offline — the celebration
    // below shouldn't wait on that, since the completion is already
    // recorded in the local cache (and the streak badge above already
    // reads from it) regardless of connectivity.
    unawaited(ref.read(completionsControllerProvider).complete(routineId));

    final reduceMotion = ref.read(settingsProvider).value?.reduceMotion ?? false;
    HapticFeedback.mediumImpact();
    setState(() => _celebrating = true);
    if (reduceMotion) {
      await Future.delayed(const Duration(milliseconds: 250));
    } else {
      _confettiController.play();
      await Future.delayed(const Duration(milliseconds: 900));
    }

    if (mounted) Navigator.of(context).pop();
  }

  void _snooze() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('알람 스누즈는 STEP 8에서 알림 기능과 함께 추가됩니다.')),
    );
  }
}
