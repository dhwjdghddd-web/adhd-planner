import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/app_settings.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/routine.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../../services/notification_service.dart';
import '../memos/quick_add_button.dart';
import '../memos/quick_add_sheet.dart';
import '../rewards/streak_badge.dart';
import 'completions_controller.dart';
import 'focus_countdown_painter.dart';
import 'micro_step_progress_controller.dart';

/// '지금' focus screen: shows exactly one routine — whichever covers the
/// current minute — full-screen with a countdown ring, a micro-steps
/// checklist, and large actions. Everything else is hidden so there's only
/// one thing to look at.
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
  // "$routineId|$dateKey" the above _checked currently reflects, so
  // persisted progress is only loaded into it once per routine/day rather
  // than stomping local taps on every rebuild.
  String? _hydratedFor;
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
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 600),
    );
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
    final postponements = ref.watch(routinePostponementsProvider).value ?? const [];
    final theme = Theme.of(context);
    final reduceMotion =
        ref.watch(settingsProvider).value?.reduceMotion ?? false;

    return SuppressGlobalFab(
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              routinesAsync.when(
                data: (routines) => _buildContent(
                  context,
                  findRoutineStatus(
                    applyTodaysPostponements(routines, postponements),
                    _currentMinute,
                    _isoWeekday,
                  ),
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
              // The global quick-add FAB is suppressed on this screen (see
              // SuppressGlobalFab above) and replaced with this one, in the
              // exact same bottom-left spot and shape as everywhere else —
              // reached directly through this page's own context rather
              // than the navigatorKey workaround the global one needs,
              // since this page is already inside the real Navigator.
              // _buildContent reserves room for it in the action buttons
              // below so the two never overlap.
              Align(
                alignment: Alignment.bottomLeft,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Semantics(
                    label: '빠른 메모 추가',
                    child: FloatingActionButton(
                      heroTag: 'focus-quick-add',
                      onPressed: () => showQuickAddSheet(context),
                      child: const Icon(Icons.edit_note),
                    ),
                  ),
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
                            ? Icon(
                                Icons.check_circle,
                                size: 96,
                                color: theme.colorScheme.primary,
                              )
                            : TweenAnimationBuilder<double>(
                                tween: Tween(begin: 0.4, end: 1.0),
                                duration: const Duration(milliseconds: 350),
                                curve: Curves.elasticOut,
                                builder: (context, scale, child) =>
                                    Transform.scale(scale: scale, child: child),
                                child: Icon(
                                  Icons.check_circle,
                                  size: 96,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  /// Loads today's persisted checks into [_checked] the first time this
  /// build sees this particular routine+day — a new day (or a different
  /// routine) has no record yet, which is exactly how the reset-next-day
  /// behaviour falls out without any explicit "clear" step.
  void _hydrateChecked(Routine routine, List<MicroStepProgress> allProgress) {
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final key = '${routine.id}|$dateKey';
    if (_hydratedFor == key) return;
    _hydratedFor = key;

    MicroStepProgress? existing;
    for (final p in allProgress) {
      if (p.routineId == routine.id && p.dateKey == dateKey) {
        existing = p;
        break;
      }
    }
    _checked
      ..clear()
      ..addAll(existing?.checkedIndices ?? const []);
  }

  Widget _buildContent(BuildContext context, RoutineStatus status) {
    final theme = Theme.of(context);
    final routine = status.routine;

    if (routine == null) {
      return Center(
        child: Text('오늘 일정이 없어요', style: theme.textTheme.titleMedium),
      );
    }

    final allProgress = ref.watch(microStepProgressProvider).value ?? const [];
    _hydrateChecked(routine, allProgress);

    if (!status.isCurrent) {
      // Inside the routine's own lead-warning window (the same "5분 전"
      // setting that drives the 전환 예고 notification): not current yet,
      // but close enough that prep micro-steps (e.g. "퇴근준비하기") are
      // worth checking off now, before the official start time. Staying on
      // this screen as the clock crosses into "current" keeps whatever was
      // already checked — _checked isn't reset by that transition.
      final upcoming =
          routine.leadWarningMin > 0 && status.remainingMinutes <= routine.leadWarningMin;

      if (!upcoming) {
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

      return Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 64, 24, 24),
              child: Semantics(
                label: '곧 시작: ${routine.title}, ${status.remainingMinutes}분 후 시작',
                child: Column(
                  children: [
                    Text(
                      '${status.remainingMinutes}분 후 시작',
                      style: theme.textTheme.headlineMedium,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      routine.title,
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    ..._microStepsChecklist(routine),
                  ],
                ),
              ),
            ),
          ),
          _bottomActions([
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('닫기'),
            ),
          ]),
        ],
      );
    }

    final progress = routine.durationMin <= 0
        ? 0.0
        : status.remainingMinutes / routine.durationMin;

    return Column(
      children: [
        // Ring/title/streak stay put rather than scrolling away with a long
        // micro-steps list — only the checklist below scrolls.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
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
                      // Fixed-size ring (matches the dial's own center
                      // circle in planner_page.dart) — clamp locally so
                      // this can't grow past the ring at 200% system text
                      // scale.
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
              ],
            ),
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: _microStepsChecklist(routine, autoCompleteWhenAllChecked: true),
            ),
          ),
        ),
        _bottomActions([
          FilledButton(
            onPressed: () => _complete(routine.id, microSteps: routine.microSteps),
            child: const Text('완료'),
          ),
          FilledButton.tonal(
            onPressed: () => _postpone(routine),
            child: const Text('미루기'),
          ),
        ]),
      ],
    );
  }

  /// Action buttons pinned to the bottom of the screen — never pushed off
  /// by a long micro-steps list — side by side rather than stacked, with
  /// room reserved on the left so they never sit under the quick-add FAB
  /// in the same corner.
  Widget _bottomActions(List<Widget> buttons) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(88, 0, 24, 24),
      child: Row(
        children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: buttons[i]),
          ],
        ],
      ),
    );
  }

  /// Shared between the "곧 시작" (lead-warning window) and "지금" (current)
  /// states so checking a step in one carries straight into the other as
  /// the clock crosses the routine's start time. Persisted immediately
  /// (per routine+day) so it also survives leaving and reopening this
  /// screen, resetting automatically the next day.
  ///
  /// [autoCompleteWhenAllChecked]: only meaningful for the actual "지금"
  /// state — checking off the last remaining step finishes the routine the
  /// same way pressing 완료 would, since at that point there's nothing left
  /// 완료 itself would add.
  List<Widget> _microStepsChecklist(Routine routine, {bool autoCompleteWhenAllChecked = false}) {
    if (routine.microSteps.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      ...List.generate(routine.microSteps.length, (i) {
        final checked = _checked.contains(i);
        return CheckboxListTile(
          value: checked,
          title: Text(routine.microSteps[i]),
          onChanged: (_) => _toggleMicroStep(routine, i, autoCompleteWhenAllChecked),
        );
      }),
    ];
  }

  void _toggleMicroStep(Routine routine, int index, bool autoCompleteWhenAllChecked) {
    final wasChecked = _checked.contains(index);
    setState(() {
      if (wasChecked) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
    unawaited(ref.read(microStepProgressControllerProvider).save(routine.id, _checked));

    // Only fires when *checking* the last box, not when un-checking one
    // that happened to leave the set "full" (it can't, but be explicit).
    final justCompletedAll = !wasChecked && _checked.length == routine.microSteps.length;
    if (autoCompleteWhenAllChecked && justCompletedAll) {
      _complete(routine.id);
    }
  }

  Future<void> _complete(String routineId, {List<String>? microSteps}) async {
    // 완료 finishes every micro-step too — there's no real "done but some
    // prep steps unchecked" state once the whole routine is marked done.
    if (microSteps != null && microSteps.isNotEmpty) {
      setState(() {
        _checked.addAll(List.generate(microSteps.length, (i) => i));
      });
      unawaited(ref.read(microStepProgressControllerProvider).save(routineId, _checked));
    }

    // Not awaited: Firestore's write Future only resolves once the backend
    // acknowledges it, which never happens while offline — the celebration
    // below shouldn't wait on that, since the completion is already
    // recorded in the local cache (and the streak badge above already
    // reads from it) regardless of connectivity.
    unawaited(ref.read(completionsControllerProvider).complete(routineId));

    final reduceMotion =
        ref.read(settingsProvider).value?.reduceMotion ?? false;
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

  // Pushes today's effective start time forward via NotificationService
  // (same logic a notification's own 미루기 action triggers) and cancels
  // today's still-showing alarm notification, if any -- not just a
  // SnackBar, since this button used to be a STEP 7 stub that never got
  // wired up once the real alarm plumbing landed in STEP 8.
  void _postpone(Routine routine) {
    final settings = ref.read(settingsProvider).value ?? const AppSettings.defaults();
    final today = DateTime.now().weekday;
    final service = ref.read(notificationServiceProvider);
    unawaited(_tryPostpone(service, routine.id, settings, today));

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${routine.snoozeMin}분 미뤘어요')),
    );
    Navigator.of(context).pop();
  }

  Future<void> _tryPostpone(
    NotificationService service,
    String routineId,
    AppSettings settings,
    int today,
  ) async {
    try {
      await service.postpone(routineId, settings);
      await service.cancelNotification(notificationIdFor(routineId, today, 0));
    } catch (_) {
      // No platform channel available (e.g. under flutter test) -- the
      // postpone just won't visibly do anything there.
    }
  }
}
