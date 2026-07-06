import 'dart:convert';

import 'package:flutter/services.dart';

import '../data/micro_step_layout.dart';
import '../data/models/micro_step_move.dart';
import '../data/models/micro_step_progress.dart';
import '../data/models/segment.dart';
import '../data/today.dart';

const _wearChannel = MethodChannel('com.adhdplanner.adhd_planner/wear');

/// Sends today's checklist JSON to the native side, which relays it onto the
/// Wearable Data Layer for the watch companion. Silently no-ops when there's no
/// platform channel (widget tests) or no watch.
Future<void> pushChecklistToWatch(String json) async {
  try {
    await _wearChannel.invokeMethod('pushChecklist', {'json': json});
  } catch (_) {
    // No native side / no watch -- fine.
  }
}

/// Serialises today's blocks and their (post-"오늘만 여기서") checklist items with
/// their checked state, in the shape the watch renders and echoes back on
/// toggle. Each item carries its home (segmentId, index) identity so a toggle
/// from the watch writes to the right [MicroStepProgress] doc. [restToday] tells
/// the watch to show its "쉬는 날" screen instead of the checklist.
String buildChecklistJson({
  required List<Segment> segments,
  required List<MicroStepProgress> progress,
  required List<MicroStepMove> moves,
  bool restToday = false,
  DateTime? now,
}) {
  final todayKey = dayKeyFor(now);
  final checkedByHome = <String, Set<int>>{
    for (final p in progress)
      if (p.dateKey == todayKey) p.segmentId: p.checkedIndices.toSet(),
  };

  final sorted = [...segments]
    ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

  // Each block's start/end minute-of-day travel with it so the WATCH decides
  // (from its own clock) which blocks are "current" (in progress) and which are
  // "starting now" (alarm) -- independent of when this was pushed, so a
  // minute-boundary lag can't show a stale/wrong set.
  // ALL blocks (not just ones with checklist items): the alarm names every
  // block *starting* now even if it has no items, and the watch decides
  // current/starting from the times below.
  final blocks = <Map<String, dynamic>>[];
  for (final block in sorted) {
    final displayed = displayedStepsFor(
      block: block,
      allSegments: segments,
      moves: moves,
      now: now,
    );
    blocks.add({
      'blockId': block.id,
      'name': block.name,
      'start': block.startMinute,
      'end': block.endMinute,
      'items': [
        for (final ds in displayed)
          {
            'segmentId': ds.homeSegmentId,
            'index': ds.index,
            'text': ds.text,
            'checked':
                checkedByHome[ds.homeSegmentId]?.contains(ds.index) ?? false,
          },
      ],
    });
  }

  return jsonEncode({
    'dateKey': todayKey,
    'restToday': restToday,
    'blocks': blocks,
  });
}
