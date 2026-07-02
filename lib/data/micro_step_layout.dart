import 'package:flutter/foundation.dart';

import 'models/completion.dart';
import 'models/micro_step_move.dart';
import 'models/micro_step_progress.dart';
import 'models/segment.dart';
import 'today.dart';

/// One checklist item as it should appear under some block *today*, after
/// "오늘만 여기서" moves are applied. [homeSegmentId]/[index] are the item's
/// permanent identity (its progress lives under the home block, keyed by this
/// index), regardless of which block it's currently shown under -- so checking
/// it writes to the home block's [MicroStepProgress] and a new day reverts to
/// the configured layout for free.
@immutable
class DisplayedStep {
  final String homeSegmentId;
  final int index;
  final String text;

  /// True when this item is being shown under a block other than its home
  /// (i.e. it was moved here today) -- lets the UI mark it and offer "되돌리기".
  final bool movedHere;

  const DisplayedStep({
    required this.homeSegmentId,
    required this.index,
    required this.text,
    required this.movedHere,
  });
}

/// The checklist items shown under [block] today: the block's own items that
/// weren't moved away, plus any items moved in from other blocks. [moves] may
/// contain other days' records (they're filtered to [now]'s day here).
List<DisplayedStep> displayedStepsFor({
  required Segment block,
  required List<Segment> allSegments,
  required List<MicroStepMove> moves,
  DateTime? now,
}) {
  final todayKey = dayKeyFor(now);
  final todayMoves = moves.where((m) => m.dateKey == todayKey).toList();

  final movedAwayFromBlock = <int>{
    for (final m in todayMoves)
      if (m.homeSegmentId == block.id) m.stepIndex,
  };

  final result = <DisplayedStep>[
    for (var i = 0; i < block.microSteps.length; i++)
      if (!movedAwayFromBlock.contains(i))
        DisplayedStep(
          homeSegmentId: block.id,
          index: i,
          text: block.microSteps[i],
          movedHere: false,
        ),
  ];

  final byId = {for (final s in allSegments) s.id: s};
  for (final m in todayMoves) {
    if (m.targetSegmentId != block.id) continue;
    final home = byId[m.homeSegmentId];
    // Skip stale moves whose home block or item no longer exists (e.g. the
    // block's items were edited after the move was made).
    if (home == null) continue;
    if (m.stepIndex < 0 || m.stepIndex >= home.microSteps.length) continue;
    result.add(
      DisplayedStep(
        homeSegmentId: home.id,
        index: m.stepIndex,
        text: home.microSteps[m.stepIndex],
        movedHere: true,
      ),
    );
  }

  return result;
}

/// Which blocks' [Completion] should be flipped so each block is complete
/// exactly when all its *displayed* items (after moves) are checked today.
@immutable
class CompletionReconciliation {
  final Set<String> toComplete;
  final Set<String> toUncomplete;
  const CompletionReconciliation(this.toComplete, this.toUncomplete);
}

/// Computes the completion changes needed so a block's ✓ tracks its displayed
/// checklist. Handles the two gaps the per-action logic missed: un-checking an
/// item must clear the ✓, and moving the last unchecked item away ("오늘만
/// 여기서") must leave the source block complete (and the target, now holding an
/// unchecked item, not). Blocks with no displayed items are left untouched --
/// their completion is explicit (the 완료 button on a checklist-less block).
CompletionReconciliation reconcileBlockCompletions({
  required List<Segment> segments,
  required List<MicroStepProgress> progress,
  required List<MicroStepMove> moves,
  required List<Completion> completions,
  DateTime? now,
}) {
  final todayKey = dayKeyFor(now);
  final completed = completedBlockIdsOn(completions, now: now);
  final checkedByHome = <String, Set<int>>{
    for (final p in progress)
      if (p.dateKey == todayKey) p.segmentId: p.checkedIndices.toSet(),
  };

  final toComplete = <String>{};
  final toUncomplete = <String>{};
  for (final block in segments) {
    final displayed = displayedStepsFor(
      block: block,
      allSegments: segments,
      moves: moves,
      now: now,
    );
    if (displayed.isEmpty) continue;
    final allChecked = displayed.every(
      (d) => checkedByHome[d.homeSegmentId]?.contains(d.index) ?? false,
    );
    final isComplete = completed.contains(block.id);
    if (allChecked && !isComplete) {
      toComplete.add(block.id);
    } else if (!allChecked && isComplete) {
      toUncomplete.add(block.id);
    }
  }
  return CompletionReconciliation(toComplete, toUncomplete);
}
