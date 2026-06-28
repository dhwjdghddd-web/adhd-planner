import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/memo.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../segments/segment_form_page.dart';
import '../segments/segment_icons.dart';
import '../segments/segments_controller.dart';
import 'memos_controller.dart';
import 'quick_add_button.dart';

/// Lets a memo "close the loop" into something actionable: either a brand
/// new block (its text becomes the block's name) or one more checklist item
/// on a block that already exists. Either way, a successful promotion marks
/// the memo reviewed -- it's been handled, just not by ticking its own
/// checkbox.
Future<void> showPromoteMemoSheet(BuildContext context, Memo memo) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (_) => _PromoteMemoSheet(memo: memo),
  );
}

class _PromoteMemoSheet extends ConsumerWidget {
  const _PromoteMemoSheet({required this.memo});

  final Memo memo;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ListTile(
            title: Text(memo.text, maxLines: 2, overflow: TextOverflow.ellipsis),
            subtitle: const Text('이 메모를 어떻게 처리할까요?'),
          ),
          const Divider(height: 1),
          ListTile(
            leading: const Icon(Icons.add_box_outlined),
            title: const Text('새 블록으로 만들기'),
            onTap: () => _promoteToNewBlock(context, ref),
          ),
          ListTile(
            leading: const Icon(Icons.playlist_add),
            title: const Text('기존 블록에 항목으로 추가'),
            onTap: () => _promoteToExistingBlock(context, ref),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Future<void> _promoteToNewBlock(BuildContext context, WidgetRef ref) async {
    final memosController = ref.read(memosControllerProvider);
    // Captured before popping: a NavigatorState (unlike this sheet's own
    // BuildContext) stays valid after the sheet closes, so it's safe to push
    // the next route on it below.
    final navigator = Navigator.of(context);
    navigator.pop();
    final saved = await navigator.push<bool>(
      MaterialPageRoute(builder: (_) => SegmentFormPage(initialName: memo.text)),
    );
    if (saved == true) {
      await memosController.setReviewed(memo, true);
    }
  }

  Future<void> _promoteToExistingBlock(BuildContext context, WidgetRef ref) async {
    final memosController = ref.read(memosControllerProvider);
    final segmentsController = ref.read(segmentsControllerProvider);
    final repo = ref.read(plannerRepositoryProvider)!;
    // Captured before the await below: a NavigatorState (unlike this sheet's
    // own BuildContext) stays valid across the async gap, so it's safe to
    // pop/push on it once the repository read resolves.
    final navigator = Navigator.of(context);
    // Read straight from the repository rather than segmentsProvider's
    // cached .value -- if nothing else in the tree happens to be watching it
    // yet, that first read can race ahead of its own initial async
    // resolution and see an empty list even with real data already saved.
    // Same hazard SegmentsController's own _rescheduleAll/delete already
    // guard against the same way.
    final segments = await repo.watchSegments().first;
    if (!navigator.mounted) return;
    navigator.pop();

    if (segments.isEmpty) {
      showAppSnackBar(navigator.context, const Text('추가할 블록이 없어요. 먼저 블록을 만들어주세요.'));
      return;
    }

    final picked = await showModalBottomSheet<Segment>(
      context: navigator.context,
      builder: (_) => _SegmentPickerSheet(segments: segments),
    );
    if (picked == null) return;

    await segmentsController.upsert(
      picked.copyWith(microSteps: [...picked.microSteps, memo.text]),
    );
    await memosController.setReviewed(memo, true);
  }
}

class _SegmentPickerSheet extends StatelessWidget {
  const _SegmentPickerSheet({required this.segments});

  final List<Segment> segments;

  @override
  Widget build(BuildContext context) {
    final sorted = [...segments]..sort((a, b) => a.order.compareTo(b.order));
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text('어느 블록에 추가할까요?', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
          for (final segment in sorted)
            ListTile(
              leading: Builder(builder: (context) {
                final color = segment.themeColor(context);
                return CircleAvatar(
                  backgroundColor: color,
                  child: Icon(iconForKey(segment.iconKey), color: onSegmentColor(color)),
                );
              }),
              title: Text(segment.name),
              subtitle: Text(
                '${TimeGeometry.formatMinute(segment.startMinute)} ~ '
                '${TimeGeometry.formatMinute(segment.endMinute)}',
              ),
              onTap: () => Navigator.pop(context, segment),
            ),
        ],
      ),
    );
  }
}
