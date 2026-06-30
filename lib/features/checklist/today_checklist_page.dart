import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/error_view.dart';
import '../../core/time_geometry.dart';
import '../../data/micro_step_layout.dart';
import '../../data/models/completion.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../focus/completions_controller.dart';
import '../focus/micro_step_progress_controller.dart';
import '../segments/segment_icons.dart';

/// Every block of today -- past, current, and upcoming -- each with a checkbox
/// to mark it done, and (for blocks that have them) their "루틴" items right
/// below so those can be corrected too. Unlike Focus, which only ever shows the
/// single block that's "current" right now, this is the catch-up surface: once
/// a block's time has passed there's no other way back to it, so forgetting to
/// check it off at the time would otherwise be permanent.
class TodayChecklistPage extends ConsumerWidget {
  const TodayChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final completions = ref.watch(completionsProvider).value ?? const [];
    final microStepProgress =
        ref.watch(microStepProgressProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 체크리스트')),
      body: segmentsAsync.when(
        data: (segments) => _Body(
          segments: segments,
          completions: completions,
          microStepProgress: microStepProgress,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: errorView,
      ),
    );
  }
}

class _Body extends ConsumerWidget {
  const _Body({
    required this.segments,
    required this.completions,
    required this.microStepProgress,
  });

  final List<Segment> segments;
  final List<Completion> completions;
  final List<MicroStepProgress> microStepProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dateKey = dayKeyFor();
    final moves = ref.watch(microStepMovesProvider).value ?? const [];
    final completedIds = completedBlockIdsOn(completions);
    final checkedBySegmentId = {
      for (final p in microStepProgress)
        if (p.dateKey == dateKey) p.segmentId: p.checkedIndices.toSet(),
    };

    final sorted = [...segments]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    if (sorted.isEmpty) {
      return const Center(child: Text('오늘 일정이 없어요'));
    }

    bool isItemChecked(DisplayedStep ds) =>
        checkedBySegmentId[ds.homeSegmentId]?.contains(ds.index) ?? false;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final segment = sorted[index];
        // Same "오늘만 여기서" composition Focus uses, so a moved item shows
        // under its today-block here too (its check state already syncs, since
        // it's stored under the home block).
        final displayed = displayedStepsFor(
          block: segment,
          allSegments: segments,
          moves: moves,
        );
        return _ChecklistTile(
          segment: segment,
          isCompleted: completedIds.contains(segment.id),
          displayedSteps: displayed,
          isItemChecked: isItemChecked,
          onChanged: (checked) => _toggleBlock(
            ref,
            segment,
            displayed,
            checkedBySegmentId,
            checked,
          ),
          onItemChanged: (ds, checked) => _toggleItem(
            ref,
            segment,
            displayed,
            checkedBySegmentId,
            ds,
            checked,
          ),
        );
      },
    );
  }

  // Each displayed item is saved under its OWN home block (a moved-in item
  // stays the home's), so progress/streak counting is unaffected by the move.
  void _toggleBlock(
    WidgetRef ref,
    Segment segment,
    List<DisplayedStep> displayed,
    Map<String, Set<int>> checkedBySegmentId,
    bool checked,
  ) {
    final controller = ref.read(completionsControllerProvider);
    final progressCtrl = ref.read(microStepProgressControllerProvider);

    final byHome = <String, Set<int>>{};
    for (final ds in displayed) {
      byHome.putIfAbsent(ds.homeSegmentId, () => <int>{}).add(ds.index);
    }
    for (final entry in byHome.entries) {
      final next = Set<int>.from(checkedBySegmentId[entry.key] ?? const {});
      if (checked) {
        next.addAll(entry.value);
      } else {
        next.removeAll(entry.value);
      }
      unawaited(progressCtrl.save(entry.key, next));
    }

    if (checked) {
      unawaited(controller.complete(segment.id));
    } else {
      unawaited(controller.uncomplete(segment.id));
    }
  }

  void _toggleItem(
    WidgetRef ref,
    Segment segment,
    List<DisplayedStep> displayed,
    Map<String, Set<int>> checkedBySegmentId,
    DisplayedStep ds,
    bool checked,
  ) {
    final current = Set<int>.from(
      checkedBySegmentId[ds.homeSegmentId] ?? const {},
    );
    if (checked) {
      current.add(ds.index);
    } else {
      current.remove(ds.index);
    }
    unawaited(
      ref
          .read(microStepProgressControllerProvider)
          .save(ds.homeSegmentId, current),
    );

    final completionsController = ref.read(completionsControllerProvider);
    // "All of this block's displayed items checked?" using the post-toggle state.
    final allChecked = displayed.every((d) {
      if (d.homeSegmentId == ds.homeSegmentId && d.index == ds.index) {
        return checked;
      }
      return checkedBySegmentId[d.homeSegmentId]?.contains(d.index) ?? false;
    });
    if (checked && displayed.isNotEmpty && allChecked) {
      // Checking the last remaining item finishes the block, same as Focus.
      unawaited(completionsController.complete(segment.id));
    } else if (!checked) {
      // Stepping back from "all done" -- this screen exists to correct the
      // record, so an unchecked item should also undo a block marked complete.
      unawaited(completionsController.uncomplete(segment.id));
    }
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.segment,
    required this.isCompleted,
    required this.displayedSteps,
    required this.isItemChecked,
    required this.onChanged,
    required this.onItemChanged,
  });

  final Segment segment;
  final bool isCompleted;
  final List<DisplayedStep> displayedSteps;
  final bool Function(DisplayedStep) isItemChecked;
  final ValueChanged<bool> onChanged;
  final void Function(DisplayedStep step, bool checked) onItemChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeGeometry.formatMinute(segment.startMinute);
    final subtitleText = segment.alarmEnabled ? time : '$time · 알람 꺼짐';
    final mutedColor = Theme.of(context).colorScheme.outline;

    return Column(
      children: [
        Semantics(
          label:
              '${segment.name} 구간, $subtitleText, ${isCompleted ? "완료됨" : "미완료"}',
          child: CheckboxListTile(
            value: isCompleted,
            onChanged: (checked) => onChanged(checked ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Builder(
              builder: (context) {
                final avatarColor = segment.themeColor(context);
                return CircleAvatar(
                  backgroundColor: avatarColor,
                  child: Icon(
                    iconForKey(segment.iconKey),
                    color: onSegmentColor(avatarColor),
                  ),
                );
              },
            ),
            title: Text(
              segment.name,
              style: isCompleted
                  ? const TextStyle(decoration: TextDecoration.lineThrough)
                  : null,
            ),
            subtitle: Text(
              subtitleText,
              style: segment.alarmEnabled ? null : TextStyle(color: mutedColor),
            ),
          ),
        ),
        for (final ds in displayedSteps)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: isItemChecked(ds),
              onChanged: (checked) => onItemChanged(ds, checked ?? false),
              secondary: ds.movedHere
                  ? Tooltip(
                      message: '오늘만 여기로 옮긴 항목',
                      child: Icon(
                        Icons.swap_horiz,
                        size: 18,
                        color: mutedColor,
                      ),
                    )
                  : null,
              title: Text(
                ds.text,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }
}
