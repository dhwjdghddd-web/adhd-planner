import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time_geometry.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/routine.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../../services/notification_service.dart';
import '../memos/quick_add_button.dart';
import '../memos/quick_add_sheet.dart';
import '../rewards/streak_badge.dart';
import 'completions_controller.dart';
import 'micro_step_progress_controller.dart';
import 'waiting_illustration.dart';

/// '지금' focus screen: shows exactly one routine — whichever started most
/// recently and hasn't been superseded by a later one yet — full-screen
/// with a micro-steps checklist and large actions. It stays "current"
/// however long it actually takes (no length to set, no expiry), since
/// running out of time isn't a state this app wants to put anyone in.
/// Everything else is hidden so there's only one thing to look at.
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
    final skips = ref.watch(routineSkipsProvider).value ?? const [];
    final completions = ref.watch(completionsProvider).value ?? const [];
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final completedRoutineIds = {
      for (final c in completions)
        if (c.dateKey == todayKey) c.routineId,
    };
    final theme = Theme.of(context);
    final reduceMotion =
        ref.watch(settingsProvider).value?.reduceMotion ?? false;

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            routinesAsync.when(
              data: (routines) => _buildContent(
                context,
                findRoutineStatus(
                  excludeTodaysSkips(
                    applyTodaysPostponements(routines, postponements),
                    skips,
                  ),
                  _currentMinute,
                  _isoWeekday,
                  completedRoutineIds: completedRoutineIds,
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
      floatingActionButton: MultiFabRow(
        left: Semantics(
          label: '빠른 메모 추가',
          child: FloatingActionButton(
            heroTag: 'focus-quick-add',
            onPressed: () => showQuickAddSheet(context),
            child: const Icon(Icons.edit_note),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
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
      final reduceMotion = ref.watch(settingsProvider).value?.reduceMotion ?? false;
      return WaitingIllustration(
        reduceMotion: reduceMotion,
        message: '오늘 일정이 없어요\n지금은 편히 쉬셔도 좋습니다.',
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
        final startTime = TimeGeometry.formatMinute(routine.startMinute);
        final reduceMotion = ref.watch(settingsProvider).value?.reduceMotion ?? false;
        return Column(
          children: [
            Expanded(
              child: WaitingIllustration(
                reduceMotion: reduceMotion,
                message: '다음: ${routine.title}\n$startTime',
              ),
            ),
            _bottomActions([
              OutlinedButton(
                onPressed: () => _skip(routine),
                child: const Text('넘기기'),
              ),
            ]),
          ],
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
            OutlinedButton(
              onPressed: () => _skip(routine),
              child: const Text('넘기기'),
            ),
          ]),
        ],
      );
    }

    return Column(
      children: [
        // Title/streak stay put rather than scrolling away with a long
        // micro-steps list — only the checklist below scrolls.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
          child: Semantics(
            label: '지금 집중: ${routine.title}',
            child: Column(
              children: [
                Icon(
                  Icons.alarm,
                  size: 64,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(height: 16),
                Text(
                  routine.title,
                  style: theme.textTheme.headlineMedium,
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
            // "모두" since this button does what checking off the last
            // remaining micro-step itself already does (see
            // _toggleMicroStep's autoCompleteWhenAllChecked) -- pressing it
            // marks every micro-step checked too, not just the routine.
            child: const Text('모두 완료'),
          ),
          OutlinedButton(
            onPressed: () => _skip(routine),
            child: const Text('넘기기'),
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

  // "넘기기": skips today's occurrence of [routine] entirely -- it drops
  // out of both 지금/다음 here and the dial's center summary for the rest
  // of today (see NotificationService.skipToday), and today's still-armed
  // alarms for it are cancelled so it doesn't ring later today either.
  // Stays open (doesn't pop) so the screen can immediately show whatever
  // comes next, since that's the whole point of pressing it from here.
  void _skip(Routine routine) {
    unawaited(_trySkipToday(routine.id));
    showAppSnackBar(context, Text('${routine.title}을(를) 내일로 넘겼어요'));
  }

  Future<void> _trySkipToday(String routineId) async {
    try {
      await ref.read(notificationServiceProvider).skipToday(routineId);
    } catch (_) {
      // No platform channel available (e.g. under flutter test).
    }
  }
}
