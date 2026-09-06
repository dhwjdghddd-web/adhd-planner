import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../../core/error_view.dart';
import '../../core/screen_mode.dart';
import '../../core/time_geometry.dart';
import '../../data/models/routine_preset.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../memos/quick_add_button.dart';
import 'mit_controller.dart';
import 'preset_management_sheet.dart';
import 'segment_form_page.dart';
import 'segment_icons.dart';
import 'segments_controller.dart';

class SegmentEditorPage extends ConsumerWidget {
  const SegmentEditorPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final settings = ref.watch(settingsProvider).value;
    final presets = settings?.presets ?? RoutinePreset.defaultPresets;

    return DefaultTabController(
      length: presets.length + 1,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('하루 구간 관리'),
          actions: [
            IconButton(
              icon: const Icon(Icons.settings_suggest_outlined),
              tooltip: '프리셋 관리',
              onPressed: () => PresetManagementSheet.show(context),
            ),
          ],
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              const Tab(text: '전체'),
              for (final p in presets)
                Tab(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: Color(p.colorValue),
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(p.name),
                    ],
                  ),
                ),
            ],
          ),
        ),
        body: Padding(
          padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
          child: segmentsAsync.when(
            data: (segments) => TabBarView(
              children: [
                _SegmentList(segments: segments),
                for (final p in presets)
                  _SegmentList(
                    segments: segments
                        .where((s) => s.presetId == p.id)
                        .toList(),
                    currentPresetId: p.id,
                  ),
              ],
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: errorView,
          ),
        ),
        floatingActionButton: isCompactLayout(context)
            ? compactCornerFabs(
                actions: [
                  Semantics(
                    label: '구간 추가',
                    child: FloatingActionButton.small(
                      heroTag: 'segment-add',
                      onPressed: () => _openForm(context),
                      child: const Icon(Icons.add),
                    ),
                  ),
                ],
              )
            : MultiFabRow(
                left: const GlobalQuickAddButton(),
                right: FloatingActionButton.extended(
                  onPressed: () => _openForm(context),
                  icon: const Icon(Icons.add),
                  label: const Text('구간 추가'),
                ),
              ),
        floatingActionButtonLocation: screenFabLocation(context),
      ),
    );
  }
}

void _openForm(BuildContext context, {Segment? existing, String? presetId}) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) =>
          SegmentFormPage(existing: existing, initialPresetId: presetId),
    ),
  );
}

class _SegmentList extends ConsumerWidget {
  const _SegmentList({required this.segments, this.currentPresetId});

  final List<Segment> segments;
  final String? currentPresetId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mits = ref.watch(mitsProvider).value ?? const [];
    final mitIds = mitBlockIdsOn(mits);

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
                onPressed: () => _openForm(context, presetId: currentPresetId),
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
        final isMit = mitIds.contains(segment.id);
        return _SegmentTile(
          key: ValueKey(segment.id),
          segment: segment,
          index: index,
          isMit: isMit,
          onTap: () => _openForm(context, existing: segment),
          onDelete: () => _confirmDelete(context, ref, segment),
          onToggleMit: () => ref
              .read(mitControllerProvider)
              .toggle(segment.id, isMitToday: isMit),
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
        content: Text('"${segment.name}" 구간과 그 안의 루틴이 삭제됩니다. 삭제할까요?'),
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
    required this.isMit,
    required this.onTap,
    required this.onDelete,
    required this.onToggleMit,
  });

  final Segment segment;
  final int index;
  final bool isMit;
  final VoidCallback onTap;
  final VoidCallback onDelete;
  final VoidCallback onToggleMit;

  @override
  Widget build(BuildContext context) {
    final range =
        '${TimeGeometry.formatMinute(segment.startMinute)} ~ '
        '${TimeGeometry.formatMinute(segment.endMinute)} · ${segment.lengthMinutes}분';

    return Semantics(
      label: '${segment.name} 구간, $range${isMit ? ', 오늘의 MIT' : ''}',
      child: Card(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: Builder(
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
          title: Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 6,
            runSpacing: 4,
            children: [
              Text(segment.name, style: const TextStyle(fontWeight: FontWeight.w600)),
              if (segment.isFirstBlock)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '🌅 기상',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
              Consumer(
                builder: (context, ref, child) {
                  final settings = ref.watch(settingsProvider).value;
                  final presets = settings?.presets ?? RoutinePreset.defaultPresets;
                  final preset = presets.firstWhere(
                    (p) => p.id == segment.presetId,
                    orElse: () => RoutinePreset.work,
                  );
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Color(preset.colorValue).withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Text(
                      preset.name,
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(preset.colorValue),
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                },
              ),
              if (segment.dateOverrides.isNotEmpty)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.orange.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    '📅 특정일 ${segment.dateOverrides.length}개',
                    style: const TextStyle(fontSize: 11, color: Colors.orange, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
          subtitle: Text(range),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // T7: today-only "오늘의 MIT" pick -- no cap on how many, by
              // design (see mit_controller.dart's class doc).
              IconButton(
                icon: Icon(isMit ? Icons.star : Icons.star_border),
                color: isMit ? Colors.amber[700] : null,
                tooltip: isMit ? '오늘의 MIT 해제' : '오늘의 MIT로 표시',
                onPressed: onToggleMit,
              ),
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
