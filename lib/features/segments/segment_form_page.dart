import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import 'segment_icons.dart';
import 'segments_controller.dart';

const _uuid = Uuid();

class SegmentFormPage extends ConsumerStatefulWidget {
  const SegmentFormPage({super.key, this.existing});

  final Segment? existing;

  @override
  ConsumerState<SegmentFormPage> createState() => _SegmentFormPageState();
}

class _SegmentFormPageState extends ConsumerState<SegmentFormPage> {
  late TextEditingController _nameController;
  late int _colorValue;
  late String _iconKey;
  late int _startMinute;
  late int _endMinute;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(text: existing?.name ?? '');
    _colorValue = existing?.colorValue ?? kSegmentPalette.first.toARGB32();
    _iconKey = existing?.iconKey ?? kSegmentIcons.keys.first;
    _startMinute = existing?.startMinute ?? 6 * 60;
    _endMinute = existing?.endMinute ?? 12 * 60;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  int get _lengthMinutes =>
      TimeGeometry.lengthMinutes(_startMinute, _endMinute);

  bool get _canSave => _nameController.text.trim().isNotEmpty && _lengthMinutes > 0;

  Future<void> _pickTime(bool isStart) async {
    final initial = isStart ? _startMinute : _endMinute;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: initial ~/ 60, minute: initial % 60),
    );
    if (picked == null) return;
    setState(() {
      final minute = picked.hour * 60 + picked.minute;
      if (isStart) {
        _startMinute = minute;
      } else {
        _endMinute = minute;
      }
    });
  }

  Future<void> _save() async {
    if (!_canSave) return;

    final segments = ref.read(segmentsProvider).value ?? const [];
    final controller = ref.read(segmentsControllerProvider);

    final segment = Segment(
      id: widget.existing?.id ?? _uuid.v4(),
      name: _nameController.text.trim(),
      colorValue: _colorValue,
      iconKey: _iconKey,
      startMinute: _startMinute,
      endMinute: _endMinute,
      order: widget.existing?.order ?? segments.length,
    );

    if (controller.overlapsAny(segment, segments)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('시간이 겹쳐요'),
          content: const Text('다른 구간과 시간이 겹칩니다. 그래도 저장할까요? (원형에서 안쪽 링으로 표시됩니다)'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('취소')),
            FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('저장')),
          ],
        ),
      );
      if (proceed != true) return;
    }

    await controller.upsert(segment);
    if (mounted) Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('구간 삭제'),
        content: Text('"${existing.name}" 구간을 삭제할까요?'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소')),
          FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('삭제')),
        ],
      ),
    );
    if (confirmed == true) {
      await ref.read(segmentsControllerProvider).delete(existing.id);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lengthOk = _lengthMinutes > 0;

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '구간 수정' : '구간 추가'),
        actions: [
          if (_isEditing)
            IconButton(
              icon: const Icon(Icons.delete_outline),
              tooltip: '삭제',
              onPressed: _confirmDelete,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Semantics(
            label: '구간 이름 입력',
            child: TextField(
              controller: _nameController,
              decoration: const InputDecoration(
                labelText: '이름',
                hintText: '예: 오전, 오후, 퇴근 후',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 24),
          const Text('색', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kSegmentPalette.map((color) {
              final value = color.toARGB32();
              final selected = value == _colorValue;
              return Semantics(
                label: '색상 선택',
                selected: selected,
                child: GestureDetector(
                  onTap: () => setState(() => _colorValue = value),
                  child: Container(
                    width: kMinTapTarget,
                    height: kMinTapTarget,
                    decoration: BoxDecoration(
                      color: color,
                      shape: BoxShape.circle,
                      border: selected
                          ? Border.all(
                              color: Theme.of(context).colorScheme.onSurface,
                              width: 3)
                          : null,
                    ),
                    child: selected
                        ? const Icon(Icons.check, color: Colors.white)
                        : null,
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('아이콘', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: kSegmentIcons.entries.map((entry) {
              final selected = entry.key == _iconKey;
              return Semantics(
                label: '아이콘 선택',
                selected: selected,
                child: GestureDetector(
                  onTap: () => setState(() => _iconKey = entry.key),
                  child: Container(
                    width: kMinTapTarget,
                    height: kMinTapTarget,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected
                          ? Theme.of(context).colorScheme.primaryContainer
                          : Theme.of(context).colorScheme.surfaceContainerHighest,
                    ),
                    child: Icon(entry.value),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('시작 시각'),
            subtitle: Text(TimeGeometry.formatMinute(_startMinute)),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(true),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('끝나는 시각'),
            subtitle: Text(TimeGeometry.formatMinute(_endMinute)),
            trailing: const Icon(Icons.access_time),
            onTap: () => _pickTime(false),
          ),
          const SizedBox(height: 8),
          Text(
            lengthOk ? '길이: $_lengthMinutes분' : '시작과 끝 시각이 같아요. 길이가 0분이 됩니다.',
            style: TextStyle(
              color: lengthOk
                  ? Theme.of(context).colorScheme.onSurfaceVariant
                  : Theme.of(context).colorScheme.error,
            ),
          ),
          const SizedBox(height: 32),
          SizedBox(
            height: 56,
            child: FilledButton(
              onPressed: _canSave ? _save : null,
              child: const Text('저장'),
            ),
          ),
        ],
      ),
    );
  }
}
