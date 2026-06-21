import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time_geometry.dart';
import '../../data/models/completion.dart';
import '../../data/models/micro_step_progress.dart';
import '../../data/models/routine.dart';
import '../../data/models/routine_postponement.dart';
import '../../data/models/routine_skip.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../focus/completions_controller.dart';
import '../focus/micro_step_progress_controller.dart';
import '../segments/segment_icons.dart';

/// Every routine scheduled for today -- past, current, and upcoming,
/// including ones already 넘기기'd -- each with a checkbox to mark it
/// done, and (for routines that have them) their micro-steps right below
/// so those can be corrected too. Unlike Focus, which only ever shows the
/// single routine that's "current" right now, this is the catch-up
/// surface: once a routine has been superseded by a later one there's no
/// other way back to it, so forgetting to check it off at the time would
/// otherwise be permanent.
class TodayChecklistPage extends ConsumerWidget {
  const TodayChecklistPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final routinesAsync = ref.watch(routinesProvider);
    final postponements = ref.watch(routinePostponementsProvider).value ?? const [];
    final skips = ref.watch(routineSkipsProvider).value ?? const [];
    final completions = ref.watch(completionsProvider).value ?? const [];
    final microStepProgress = ref.watch(microStepProgressProvider).value ?? const [];

    return Scaffold(
      appBar: AppBar(title: const Text('오늘의 체크리스트')),
      body: segmentsAsync.when(
        data: (segments) => routinesAsync.when(
          data: (routines) => _Body(
            segments: segments,
            routines: routines,
            postponements: postponements,
            skips: skips,
            completions: completions,
            microStepProgress: microStepProgress,
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('오류: $e')),
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
    required this.routines,
    required this.postponements,
    required this.skips,
    required this.completions,
    required this.microStepProgress,
  });

  final List<Segment> segments;
  final List<Routine> routines;
  final List<RoutinePostponement> postponements;
  final List<RoutineSkip> skips;
  final List<Completion> completions;
  final List<MicroStepProgress> microStepProgress;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isoWeekday = DateTime.now().weekday;
    final dateKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final skippedIds = {
      for (final s in skips) if (s.dateKey == dateKey) s.routineId,
    };
    final completedIds = {
      for (final c in completions) if (c.dateKey == dateKey) c.routineId,
    };
    final checkedByRoutineId = {
      for (final p in microStepProgress)
        if (p.dateKey == dateKey) p.routineId: p.checkedIndices.toSet(),
    };

    final todays = routines.where((r) => r.occursOn(isoWeekday)).toList();
    // Postponement only shifts *display* time, same as the home dial --
    // skipped routines stay in this list (rather than being filtered out
    // like they are on the dial/Focus) since the whole point here is
    // catching up on something done despite being skipped or forgotten.
    final displayed = applyTodaysPostponements(todays, postponements)
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    if (displayed.isEmpty) {
      return const Center(child: Text('오늘 일정이 없어요'));
    }

    final segmentsById = {for (final s in segments) s.id: s};

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: displayed.length,
      itemBuilder: (context, index) {
        final routine = displayed[index];
        return _ChecklistTile(
          routine: routine,
          segment: segmentsById[routine.segmentId],
          isSkipped: skippedIds.contains(routine.id),
          isCompleted: completedIds.contains(routine.id),
          checkedMicroSteps: checkedByRoutineId[routine.id] ?? const {},
          onChanged: (checked) => _toggleRoutine(ref, routine, checked),
          onMicroStepChanged: (i, checked) => _toggleMicroStep(
            ref,
            routine,
            checkedByRoutineId[routine.id] ?? const {},
            i,
            checked,
          ),
        );
      },
    );
  }

  void _toggleRoutine(WidgetRef ref, Routine routine, bool checked) {
    final controller = ref.read(completionsControllerProvider);
    if (checked) {
      // 완료 finishes every micro-step too -- mirrors Focus's 완료 button,
      // there's no real "done but some steps unchecked" state.
      if (routine.microSteps.isNotEmpty) {
        unawaited(ref.read(microStepProgressControllerProvider).save(
              routine.id,
              List.generate(routine.microSteps.length, (i) => i),
            ));
      }
      unawaited(controller.complete(routine.id));
    } else {
      // Un-checking the routine is the exact mirror of checking it: checking
      // filled every micro-step, so un-checking clears them all again. Without
      // this the tile would drop back to "미완료" while its steps stayed fully
      // ticked -- a contradictory state that also kept dragging the day's
      // achievement ratio up off steps the user just said weren't done.
      if (routine.microSteps.isNotEmpty) {
        unawaited(ref.read(microStepProgressControllerProvider).save(routine.id, const {}));
      }
      unawaited(controller.uncomplete(routine.id));
    }
  }

  void _toggleMicroStep(
    WidgetRef ref,
    Routine routine,
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
    unawaited(ref.read(microStepProgressControllerProvider).save(routine.id, current));

    final completionsController = ref.read(completionsControllerProvider);
    if (checked && current.length == routine.microSteps.length) {
      // Checking the last remaining step finishes the routine, same as Focus.
      unawaited(completionsController.complete(routine.id));
    } else if (!checked) {
      // Stepping back from "all done" -- this screen exists to correct the
      // record, so an unchecked step should also undo a routine marked
      // complete on the strength of every step being done.
      unawaited(completionsController.uncomplete(routine.id));
    }
  }
}

class _ChecklistTile extends StatelessWidget {
  const _ChecklistTile({
    required this.routine,
    required this.segment,
    required this.isSkipped,
    required this.isCompleted,
    required this.checkedMicroSteps,
    required this.onChanged,
    required this.onMicroStepChanged,
  });

  final Routine routine;
  final Segment? segment;
  final bool isSkipped;
  final bool isCompleted;
  final Set<int> checkedMicroSteps;
  final ValueChanged<bool> onChanged;
  final void Function(int index, bool checked) onMicroStepChanged;

  @override
  Widget build(BuildContext context) {
    final time = TimeGeometry.formatMinute(routine.startMinute);
    final segmentName = segment?.name ?? '구간 없음';
    final subtitleText =
        isSkipped ? '$segmentName · $time · 오늘 건너뜀' : '$segmentName · $time';
    final mutedColor = Theme.of(context).colorScheme.outline;

    return Column(
      children: [
        Semantics(
          label: '${routine.title} 루틴, $subtitleText, ${isCompleted ? "완료됨" : "미완료"}',
          child: CheckboxListTile(
            value: isCompleted,
            onChanged: (checked) => onChanged(checked ?? false),
            controlAffinity: ListTileControlAffinity.leading,
            secondary: CircleAvatar(
              backgroundColor: segment?.themeColor(context) ?? Colors.grey,
              child: Icon(iconForKey(segment?.iconKey ?? ''), color: Colors.white),
            ),
            title: Text(
              routine.title,
              style: isCompleted ? const TextStyle(decoration: TextDecoration.lineThrough) : null,
            ),
            subtitle: Text(
              subtitleText,
              style: isSkipped ? TextStyle(color: mutedColor) : null,
            ),
          ),
        ),
        for (var i = 0; i < routine.microSteps.length; i++)
          Padding(
            padding: const EdgeInsets.only(left: 40),
            child: CheckboxListTile(
              dense: true,
              visualDensity: VisualDensity.compact,
              controlAffinity: ListTileControlAffinity.leading,
              value: checkedMicroSteps.contains(i),
              onChanged: (checked) => onMicroStepChanged(i, checked ?? false),
              title: Text(
                routine.microSteps[i],
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
          ),
      ],
    );
  }
}
