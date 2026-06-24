import 'dart:async';
import 'dart:math' as math;

import 'package:confetti/confetti.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_geometry.dart';
import '../../data/block_status.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../memos/quick_add_sheet.dart';
import '../rewards/streak_badge.dart';
import 'completions_controller.dart';
import 'micro_step_progress_controller.dart';
import 'waiting_illustration.dart';

/// '지금' focus screen: shows exactly one block — whichever the clock is inside
/// right now — full-screen with its checklist of "루틴" items and a large
/// action. It stays "current" however long the block's range lasts. Everything
/// else is hidden so there's only one thing to look at.
///
/// [FocusPage.forBlock] opens the same screen pinned to one specific block
/// instead of whatever the clock says is current — the dial's arc tap uses this
/// so a block whose time already passed can still be reviewed and have its
/// items checked off.
class FocusPage extends ConsumerStatefulWidget {
  const FocusPage({super.key}) : pinnedBlock = null;
  const FocusPage.forBlock(Segment block, {super.key}) : pinnedBlock = block;

  final Segment? pinnedBlock;

  @override
  ConsumerState<FocusPage> createState() => _FocusPageState();
}

class _FocusPageState extends ConsumerState<FocusPage> {
  late int _currentMinute;
  Timer? _ticker;
  final Set<int> _checked = {};
  // "$segmentId|$dateKey" the above _checked currently reflects, so persisted
  // progress is only loaded into it once per block/day rather than stomping
  // local taps on every rebuild.
  String? _hydratedFor;
  late final ConfettiController _confettiController;
  bool _celebrating = false;

  @override
  void initState() {
    super.initState();
    _currentMinute = _minuteOfNow();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final minute = _minuteOfNow();
      if (minute != _currentMinute) {
        setState(() => _currentMinute = minute);
      }
    });
    _confettiController = ConfettiController(
      duration: const Duration(milliseconds: 600),
    );
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
    final segmentsAsync = ref.watch(segmentsProvider);
    final theme = Theme.of(context);
    final reduceMotion = ref.watch(settingsProvider).value?.reduceMotion ?? false;

    final pinned = widget.pinnedBlock;
    final segments = segmentsAsync.value;
    final status = pinned != null
        ? BlockStatus(segment: pinned, isCurrent: true)
        : segments == null
            ? null
            : _liveStatus(segments, _currentMinute);

    return Scaffold(
      body: SafeArea(
        child: Stack(
          children: [
            // Positioned.fill so the content always gets tight full-width
            // constraints: a non-positioned Stack child is laid out loose and
            // pinned top-start, so the body Column would otherwise shrink-wrap
            // to its widest child and hug the left edge whenever nothing in it
            // forces full width (e.g. a block with no checklist items).
            Positioned.fill(
              child: pinned != null
                  ? _buildContent(context, status!)
                  : segmentsAsync.when(
                      data: (_) => _buildContent(context, status!),
                      loading: () => const Center(child: CircularProgressIndicator()),
                      error: (e, st) => Center(child: Text('오류: $e')),
                    ),
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
      floatingActionButton: _buildFabRow(status),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  /// Combines the quick-add memo button with the block's 완료 action into a
  /// single floating row, so a snackbar raises them — and they line up — as one
  /// unit.
  Widget _buildFabRow(BlockStatus? status) {
    final segment = status?.segment;
    // A block with no checklist has nothing to mark done -- pressing 완료 on
    // one never moves the checked/total streak ratio either way (see
    // daily_achievement.dart), so there's no real action here to offer at all,
    // pinned/review mode included.
    final showComplete =
        segment != null && status!.isCurrent && segment.microSteps.isNotEmpty;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          Semantics(
            label: '빠른 메모 추가',
            child: FloatingActionButton(
              heroTag: 'focus-quick-add',
              onPressed: () => showQuickAddSheet(context),
              child: const Icon(Icons.edit_note),
            ),
          ),
          if (showComplete) ...[
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _complete(segment.id, microSteps: segment.microSteps),
                child: const Text('모두 완료'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// Loads today's persisted checks into [_checked] the first time this build
  /// sees this particular block+day — a new day (or a different block) has no
  /// record yet, which is exactly how the reset-next-day behaviour falls out.
  void _hydrateChecked(Segment segment, List<MicroStepProgress> allProgress) {
    final dateKey = dayKeyFor();
    final key = '${segment.id}|$dateKey';
    if (_hydratedFor == key) return;
    _hydratedFor = key;

    MicroStepProgress? existing;
    for (final p in allProgress) {
      if (p.segmentId == segment.id && p.dateKey == dateKey) {
        existing = p;
        break;
      }
    }
    _checked
      ..clear()
      ..addAll(existing?.checkedIndices ?? const []);
  }

  Widget _buildContent(BuildContext context, BlockStatus status) {
    final theme = Theme.of(context);
    final segment = status.segment;
    final reduceMotion = ref.watch(settingsProvider).value?.reduceMotion ?? false;

    if (segment == null) {
      return WaitingIllustration(
        reduceMotion: reduceMotion,
        message: '오늘 일정이 없어요\n지금은 편히 쉬셔도 좋습니다.',
      );
    }

    final allProgress = ref.watch(microStepProgressProvider).value ?? const [];
    _hydrateChecked(segment, allProgress);

    if (!status.isCurrent) {
      // Not inside any block right now -- show the next one and when it starts.
      final startTime = TimeGeometry.formatMinute(segment.startMinute);
      return Column(
        children: [
          Expanded(
            child: WaitingIllustration(
              reduceMotion: reduceMotion,
              message: '다음: ${segment.name}\n$startTime',
            ),
          ),
        ],
      );
    }

    return Column(
      children: [
        // Title/streak stay put rather than scrolling away with a long item
        // list — only the checklist below scrolls.
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 64, 24, 0),
          child: Semantics(
            label: '지금 집중: ${segment.name}',
            child: Column(
              children: [
                Icon(Icons.alarm, size: 64, color: theme.colorScheme.primary),
                const SizedBox(height: 16),
                Text(
                  segment.name,
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
          child: segment.microSteps.isEmpty
              ? WaitingIllustration(
                  reduceMotion: reduceMotion,
                  message: '체크할 항목이 없어요\n편히 보내도 좋아요.',
                )
              : SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
                  child: Column(
                    children: _microStepsChecklist(segment, autoCompleteWhenAllChecked: true),
                  ),
                ),
        ),
      ],
    );
  }

  /// The block's "루틴" items as a checklist. Persisted immediately (per
  /// block+day) so checks survive leaving and reopening, resetting next day.
  ///
  /// [autoCompleteWhenAllChecked]: checking off the last remaining item finishes
  /// the block the same way pressing 모두 완료 would.
  List<Widget> _microStepsChecklist(Segment segment, {bool autoCompleteWhenAllChecked = false}) {
    if (segment.microSteps.isEmpty) return const [];
    return [
      const SizedBox(height: 16),
      ...List.generate(segment.microSteps.length, (i) {
        final checked = _checked.contains(i);
        return CheckboxListTile(
          value: checked,
          title: Text(segment.microSteps[i]),
          onChanged: (_) => _toggleMicroStep(segment, i, autoCompleteWhenAllChecked),
        );
      }),
    ];
  }

  void _toggleMicroStep(Segment segment, int index, bool autoCompleteWhenAllChecked) {
    final wasChecked = _checked.contains(index);
    setState(() {
      if (wasChecked) {
        _checked.remove(index);
      } else {
        _checked.add(index);
      }
    });
    unawaited(ref.read(microStepProgressControllerProvider).save(segment.id, _checked));

    final justCompletedAll = !wasChecked && _checked.length == segment.microSteps.length;
    if (autoCompleteWhenAllChecked && justCompletedAll) {
      _complete(segment.id);
    }
  }

  Future<void> _complete(String segmentId, {List<String>? microSteps}) async {
    // 완료 finishes every item too — there's no real "done but some items
    // unchecked" state once the whole block is marked done.
    if (microSteps != null && microSteps.isNotEmpty) {
      setState(() {
        _checked.addAll(List.generate(microSteps.length, (i) => i));
      });
      unawaited(ref.read(microStepProgressControllerProvider).save(segmentId, _checked));
    }

    // Not awaited: Firestore's write Future only resolves once the backend
    // acknowledges it, which never happens while offline — the celebration
    // shouldn't wait on that, since the completion is already in the local
    // cache (and the streak badge reads from it) regardless of connectivity.
    unawaited(ref.read(completionsControllerProvider).complete(segmentId));

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
}

/// [findBlockStatus] for the live (unpinned) screen specifically: a block
/// with no checklist has nothing for this screen to do, so it shouldn't
/// surface as a "지금" completion screen here the way it still correctly does
/// on the dial's centre summary (which keeps using [findBlockStatus] directly,
/// unfiltered). Excluding it and re-resolving falls through to whatever block
/// is actually current underneath it (relevant for overlapping blocks) or,
/// failing that, the same "다음" preview [findBlockStatus] would already show
/// for a gap with nothing current at all — checklist-less or not, since that
/// preview is just informational and never offers a 완료 action.
BlockStatus _liveStatus(List<Segment> segments, int nowMinute) {
  var candidates = segments;
  while (true) {
    final status = findBlockStatus(candidates, nowMinute);
    final segment = status.segment;
    if (!status.isCurrent || segment == null || segment.microSteps.isNotEmpty) {
      return status;
    }
    candidates = candidates.where((s) => s.id != segment.id).toList();
  }
}
