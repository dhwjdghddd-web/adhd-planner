import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
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
    final microStepProgress = ref.watch(microStepProgressProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 체크리스트')),
      body: segmentsAsync.when(
        data: (segments) => _Body(
          segments: segments,
          completions: completions,
          microStepProgress: microStepProgress,
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, st) => Center(child: Text('오류: $e')),
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
    final completedIds = completedBlockIdsOn(completions);
    final checkedBySegmentId = {
      for (final p in microStepProgress)
        if (p.dateKey == dateKey) p.segmentId: p.checkedIndices.toSet(),
    };

    final displayed = [...segments]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    if (displayed.isEmpty) {
      return const Center(child: Text('오늘 일정이 없어요'));
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: displayed.length,
      itemBuilder: (context, index) {
        final segment = displayed[index];
        return _ChecklistTile(
          segment: segment,
          isCompleted: completedIds.contains(segment.id),
          checkedItems: checkedBySegmentId[segment.id] ?? const {},
          onChanged: (checked) => _toggleBlock(ref, segment, checked),
          onItemChanged: (i, checked) => _toggleItem(
            ref,
            segment,
            checkedBySegmentId[segment.id] ?? const {},
            i,
            checked,
          ),
        );
      },
    );
  }

  void _toggleBlock(WidgetRef ref, Segment segment, bool checked) {
    final controller = ref.read(completionsControllerProvider);
    if (checked) {
      // 완료 finishes every item too -- mirrors Focus's 완료 button, there's no
      // real "done but some items unchecked" state.
      if (segment.microSteps.isNotEmpty) {
        unawaited(ref.read(microStepProgressControllerProvider).save(
              segment.id,
              List.generate(segment.microSteps.length, (i) => i),
            ));
      }
      unawaited(controller.complete(segment.id));
    } else {
      // Un-checking the block is the exact mirror of checking it: checking
      // filled every item, so un-checking clears them all again.
      if (segment.microSteps.isNotEmpty) {
        unawaited(ref.read(microStepProgressControllerProvider).save(segment.id, const {}));
      }
      unawaited(controller.uncomplete(segment.id));
    }
  }

  void _toggleItem(
    WidgetRef ref,
    Segment segment,
    Set<int> currentChecked,
    int index,
    bool checked,
  ) {
    final current = Set<int>.from(currentChecked);
    if (checked) {
      current.add(index);
    } else {
      current.remove(index);
    }
    unawaited(ref.read(microStepProgressControllerProvider).save(segment.id, current));

    final completionsController = ref.read(completionsControllerProvider);
    if (checked && current.length == segment.microSteps.length) {
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
    required this.checkedItems,
    required this.onChanged,
    required this.onItemChanged,
  });

  final Segment segment;
  final bool isCompleted;
  final Set<int> checkedItems;
  final ValueChanged<bool> onChanged;
  final void Function(int index, bool checked) onItemChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeGeometry.formatMinute(segment.startMinute);
    final subtitleText = segment.alarmEnabled ? time : '$time · 알람 꺼짐';
    final mutedColor = Theme.of(context).colorScheme.outline;

    return Column(
      children: [
        Semantics(
          label: '${segment.name} 구간, $subtitleText, ${isCompleted ? "완료됨" : "미완료"}',
          child: CheckboxListTile(
            value: isCompleted,
            onChanged: (checked) => onChanged(checked ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: Builder(builder: (context) {
              final avatarColor = segment.themeColor(context);
              return CircleAvatar(
                backgroundColor: avatarColor,
                child: Icon(iconForKey(segment.iconKey), color: onSegmentColor(avatarColor)),
              );
            }),
            title: Text(
              segment.name,
              style: isCompleted ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
            ),
            subtitle: Text(
              subtitleText,
              style: segment.alarmEnabled ? null : TextStyle(color: mutedColor),
            ),
          ),
        ),
        for (var i = 0; i < segment.microSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: checkedItems.contains(i),
              onChanged: (checked) => onItemChanged(i, checked ?? false),
              title: Text(
                segment.microSteps[i],
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }
}
