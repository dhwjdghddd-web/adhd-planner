import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../memos/quick_add_button.dart';
import 'segment_form_page.dart';
import 'segment_icons.dart';
import 'segments_controller.dart';

class SegmentEditorPage extends ConsumerWidget {
  const SegmentEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(segmentsProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('하루 구간')),
      // Shrinks the visible body area itself (rather than padding inside
      // the list, which only shows up once scrolled all the way down) so
      // content never reaches the global bottom-left quick-add FAB (or
      // this page's own bottom-right one) even before scrolling.
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: segmentsAsync.when(
          data: (segments) => _SegmentList(segments: segments),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('오류: $e')),
        ),
      ),
      floatingActionButton: MultiFabRow(
        left: const GlobalQuickAddButton(),
        right: FloatingActionButton.extended(
          onPressed: () => _openForm(context),
          icon: const Icon(Icons.add),
          label: const Text('구간 추가'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

void _openForm(BuildContext context, {Segment? existing}) {
  Navigator.of(context).push(
    MaterialPageRoute(builder: (_) => SegmentFormPage(existing: existing)),
  );
}

class _SegmentList extends ConsumerWidget {
  const _SegmentList({required this.segments});

  final List<Segment> segments;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (segments.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '아직 구간이 없어요.\n하루를 오전·오후·퇴근 후처럼 나눠보세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => _openForm(context),
                icon: const Icon(Icons.add),
                label: const Text('구간 추가'),
              ),
            ],
          ),
        ),
      );
    }

    final sorted = [...segments]..sort((a, b) => a.order.compareTo(b.order));

    return ReorderableListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      onReorderItem: (oldIndex, newIndex) async {
        final list = [...sorted];
        final item = list.removeAt(oldIndex);
        list.insert(newIndex, item);
        await ref.read(segmentsControllerProvider).reorder(list);
      },
      itemBuilder: (context, index) {
        final segment = sorted[index];
        return _SegmentTile(
          key: ValueKey(segment.id),
          segment: segment,
          index: index,
          onTap: () => _openForm(context, existing: segment),
          onDelete: () => _confirmDelete(context, ref, segment),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Segment segment,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('구간 삭제'),
        content: Text('"${segment.name}" 구간을 삭제할까요? 소속된 루틴은 사라지지 않고, '
            '시간대가 겹치는 다른 구간으로 옮겨지거나 구간 없이 남습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      unawaited(ref.read(segmentsControllerProvider).delete(segment.id));
    }
  }
}

class _SegmentTile extends StatelessWidget {
  const _SegmentTile({
    super.key,
    required this.segment,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final Segment segment;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final range =
        '${TimeGeometry.formatMinute(segment.startMinute)} ~ '
        '${TimeGeometry.formatMinute(segment.endMinute)} · ${segment.lengthMinutes}분';

    return Semantics(
      label: '${segment.name} 구간, $range',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: Builder(builder: (context) {
            final avatarColor = segment.themeColor(context);
            return CircleAvatar(
              backgroundColor: avatarColor,
              child: Icon(iconForKey(segment.iconKey), color: onSegmentColor(avatarColor)),
            );
          }),
          title: Text(segment.name),
          subtitle: Text(range),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
                onPressed: onDelete,
              ),
              ReorderableDragStartListener(
                index: index,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: Icon(Icons.drag_handle),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
