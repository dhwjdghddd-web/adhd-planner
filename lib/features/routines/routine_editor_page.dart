import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../memos/quick_add_button.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_icons.dart';
import 'routine_form_page.dart';
import 'routines_controller.dart';

/// Lists every routine across all segments, sorted by start time, with
/// add/edit/delete. Routines need a segment to belong to, so this screen
/// nudges the user to create one first if none exist yet.
class RoutineEditorPage extends ConsumerWidget {
  const RoutineEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final routinesAsync = ref.watch(routinesProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('루틴')),
      // Shrinks the visible body area itself (rather than padding inside
      // the list, which only shows up once scrolled all the way down) so
      // content never reaches the global bottom-left quick-add FAB (or
      // this page's own bottom-right one) even before scrolling.
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: segmentsAsync.when(
          data: (segments) => routinesAsync.when(
            data: (routines) => _Body(segments: segments, routines: routines),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, st) => Center(child: Text('오류: $e')),
          ),
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, st) => Center(child: Text('오류: $e')),
        ),
      ),
      floatingActionButton: MultiFabRow(
        left: const GlobalQuickAddButton(),
        right: FloatingActionButton.extended(
          onPressed: () => _openForm(context, ref),
          icon: const Icon(Icons.add),
          label: const Text('루틴 추가'),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  void _openForm(BuildContext context, WidgetRef ref) {
    final segments = ref.read(segmentsProvider).value ?? const <Segment>[];
    if (segments.isEmpty) {
      showAppSnackBar(context, const Text('먼저 구간을 만들어주세요.'));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RoutineFormPage()));
  }
}

class _Body extends ConsumerWidget {
  const _Body({required this.segments, required this.routines});

  final List<Segment> segments;
  final List<Routine> routines;

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
                '아직 구간이 없어요.\n루틴을 추가하려면 먼저 구간을 만들어주세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const SegmentEditorPage()),
                ),
                icon: const Icon(Icons.tune),
                label: const Text('구간 만들기'),
              ),
            ],
          ),
        ),
      );
    }

    if (routines.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                '아직 루틴이 없어요.\n구간 안에 할 일을 추가해보세요.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const RoutineFormPage()),
                ),
                icon: const Icon(Icons.add),
                label: const Text('루틴 추가'),
              ),
            ],
          ),
        ),
      );
    }

    final segmentsById = {for (final s in segments) s.id: s};
    final sorted = [...routines]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: sorted.length,
      itemBuilder: (context, index) {
        final routine = sorted[index];
        final segment = segmentsById[routine.segmentId];
        return _RoutineTile(
          routine: routine,
          segment: segment,
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => RoutineFormPage(existing: routine),
            ),
          ),
          onDelete: () => _confirmDelete(context, ref, routine),
        );
      },
    );
  }

  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref,
    Routine routine,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('루틴 삭제'),
        content: Text('"${routine.title}" 루틴을 삭제할까요?'),
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
      unawaited(ref.read(routinesControllerProvider).delete(routine.id));
    }
  }
}

class _RoutineTile extends StatelessWidget {
  const _RoutineTile({
    required this.routine,
    required this.segment,
    required this.onTap,
    required this.onDelete,
  });

  final Routine routine;
  final Segment? segment;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final startTime = TimeGeometry.formatMinute(routine.startMinute);
    final repeatLabel = routine.repeatDays.isEmpty
        ? '매일'
        : routine.repeatDays.map((d) => kWeekdayShortLabels[d - 1]).join(' ');
    final segmentName = segment?.name ?? '구간 없음';

    return Semantics(
      label: '${routine.title} 루틴, $segmentName, $startTime, 반복 $repeatLabel',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: CircleAvatar(
            backgroundColor: segment?.themeColor(context) ?? Colors.grey,
            child: Icon(
              iconForKey(segment?.iconKey ?? ''),
              color: Colors.white,
            ),
          ),
          title: Text(routine.title),
          subtitle: Text('$segmentName · $startTime · $repeatLabel'),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (routine.alarmEnabled)
                const Padding(
                  padding: EdgeInsets.only(right: 4),
                  child: Icon(Icons.alarm, size: 20),
                ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '삭제',
                onPressed: onDelete,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
