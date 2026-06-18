import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../segments/segment_icons.dart';
import 'routines_controller.dart';

const _uuid = Uuid();
const List<int> _durationPresets = [15, 30, 45, 60, 90];

/// Add/edit form for a single [Routine]. Reachable from
/// [RoutineEditorPage]'s list or by tapping a routine marker on the home
/// dial. One screen, one flow: fill in the fields top to bottom, save.
class RoutineFormPage extends ConsumerStatefulWidget {
  const RoutineFormPage({super.key, this.existing});

  final Routine? existing;

  @override
  ConsumerState<RoutineFormPage> createState() => _RoutineFormPageState();
}

class _RoutineFormPageState extends ConsumerState<RoutineFormPage> {
  late TextEditingController _titleController;
  late TextEditingController _noteController;
  late TextEditingController _microStepController;
  String? _segmentId;
  late int _startMinute;
  late int _durationMin;
  late bool _alarmEnabled;
  late int _leadWarningMin;
  late int _snoozeMin;
  late Set<int> _repeatDays;
  late List<String> _microSteps;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final segments = ref.read(segmentsProvider).value ?? const <Segment>[];
    final now = TimeOfDay.now();

    _titleController = TextEditingController(text: existing?.title ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _microStepController = TextEditingController();
    _segmentId = existing?.segmentId;
    if (_segmentId == null || !segments.any((s) => s.id == _segmentId)) {
      _segmentId = segments.isNotEmpty ? segments.first.id : null;
    }
    _startMinute = existing?.startMinute ?? now.hour * 60 + now.minute;
    _durationMin = existing?.durationMin ?? 30;
    _alarmEnabled = existing?.alarmEnabled ?? true;
    _leadWarningMin = existing?.leadWarningMin ?? 5;
    _snoozeMin = existing?.snoozeMin ?? 5;
    _repeatDays = {...(existing?.repeatDays ?? const <int>[])};
    _microSteps = [...(existing?.microSteps ?? const <String>[])];
  }

  @override
  void dispose() {
    _titleController.dispose();
    _noteController.dispose();
    _microStepController.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  bool get _canSave =>
      _titleController.text.trim().isNotEmpty &&
      _segmentId != null &&
      _durationMin > 0;

  Future<void> _pickStartTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: _startMinute ~/ 60, minute: _startMinute % 60),
    );
    if (picked == null) return;
    setState(() => _startMinute = picked.hour * 60 + picked.minute);
  }

  void _changeDuration(int delta) {
    setState(() => _durationMin = (_durationMin + delta).clamp(5, 24 * 60));
  }

  void _addMicroStep() {
    final text = _microStepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _microSteps.add(text);
      _microStepController.clear();
    });
  }

  // Not awaited: Firestore's write Future only resolves once the backend
  // acknowledges it, which never happens while offline. The local cache
  // updates synchronously either way, so blocking the pop on it would just
  // leave the form stuck open with no feedback when there's no connection.
  void _save() {
    if (!_canSave) return;

    final controller = ref.read(routinesControllerProvider);
    final routine = Routine(
      id: widget.existing?.id ?? _uuid.v4(),
      segmentId: _segmentId!,
      title: _titleController.text.trim(),
      note: _noteController.text.trim(),
      microSteps: _microSteps,
      startMinute: _startMinute,
      durationMin: _durationMin,
      alarmEnabled: _alarmEnabled,
      leadWarningMin: _leadWarningMin,
      snoozeMin: _snoozeMin,
      repeatDays: _repeatDays.toList()..sort(),
      notificationIds: widget.existing?.notificationIds ?? const [],
    );

    unawaited(controller.upsert(routine));
    Navigator.pop(context);
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('루틴 삭제'),
        content: Text('"${existing.title}" 루틴을 삭제할까요?'),
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
      unawaited(ref.read(routinesControllerProvider).delete(existing.id));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider).value ?? const <Segment>[];
    final theme = Theme.of(context);

    // initState reads the segments provider before its first StreamProvider
    // emission can land (always async, even when data is already cached),
    // so self-heal the default selection here once the data actually shows up.
    if (segments.isNotEmpty && !segments.any((s) => s.id == _segmentId)) {
      _segmentId = segments.first.id;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_isEditing ? '루틴 수정' : '루틴 추가'),
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
            label: '루틴 제목 입력',
            child: TextField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: '제목',
                hintText: '예: 약 먹기, 운동, 보고서 작성',
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          const SizedBox(height: 16),
          Semantics(
            label: '메모 입력',
            child: TextField(
              controller: _noteController,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: '메모 (선택)',
                alignLabelWithHint: true,
              ),
            ),
          ),
          const SizedBox(height: 24),
          const Text('소속 구간', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          if (segments.isEmpty)
            Text(
              '구간이 없어요. 먼저 구간을 만들어주세요.',
              style: TextStyle(color: theme.colorScheme.error),
            )
          else
            Semantics(
              label: '소속 구간 선택',
              child: DropdownButtonFormField<String>(
                initialValue: _segmentId,
                items: segments
                    .map((s) => DropdownMenuItem(
                          value: s.id,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(iconForKey(s.iconKey), color: s.color, size: 20),
                              const SizedBox(width: 8),
                              Text(s.name),
                            ],
                          ),
                        ))
                    .toList(),
                onChanged: (value) => setState(() => _segmentId = value),
              ),
            ),
          const SizedBox(height: 24),
          ListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('시작 시각'),
            subtitle: Text(TimeGeometry.formatMinute(_startMinute)),
            trailing: const Icon(Icons.access_time),
            onTap: _pickStartTime,
          ),
          const SizedBox(height: 8),
          const Text('길이', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(
            children: [
              Semantics(
                label: '길이 5분 줄이기',
                container: true,
                child: IconButton.filledTonal(
                  onPressed: () => _changeDuration(-5),
                  icon: const Icon(Icons.remove),
                ),
              ),
              SizedBox(
                width: 88,
                child: Text(
                  key: const Key('routineDurationValue'),
                  '$_durationMin분',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Semantics(
                label: '길이 5분 늘리기',
                container: true,
                child: IconButton.filledTonal(
                  onPressed: () => _changeDuration(5),
                  icon: const Icon(Icons.add),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: _durationPresets
                .map((minutes) => ChoiceChip(
                      label: Text('$minutes분'),
                      selected: _durationMin == minutes,
                      onSelected: (_) => setState(() => _durationMin = minutes),
                    ))
                .toList(),
          ),
          const SizedBox(height: 24),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('알람'),
            subtitle: const Text('정해진 시각에 알려줘요'),
            value: _alarmEnabled,
            onChanged: (value) => setState(() => _alarmEnabled = value),
          ),
          if (_alarmEnabled) ...[
            const SizedBox(height: 8),
            _MinuteStepperRow(
              label: '전환 예고',
              value: _leadWarningMin,
              suffix: '분 전',
              onChanged: (v) => setState(() => _leadWarningMin = v),
            ),
            const SizedBox(height: 8),
            _MinuteStepperRow(
              label: '스누즈',
              value: _snoozeMin,
              suffix: '분 후',
              onChanged: (v) => setState(() => _snoozeMin = v),
            ),
          ],
          const SizedBox(height: 24),
          const Text('반복 요일 (선택 안 하면 매일)',
              style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(7, (i) {
              final day = i + 1; // 1=Mon..7=Sun
              final selected = _repeatDays.contains(day);
              return Semantics(
                label: '${kWeekdayShortLabels[i]}요일 반복',
                selected: selected,
                child: FilterChip(
                  label: Text(kWeekdayShortLabels[i]),
                  selected: selected,
                  onSelected: (value) => setState(() {
                    if (value) {
                      _repeatDays.add(day);
                    } else {
                      _repeatDays.remove(day);
                    }
                  }),
                ),
              );
            }),
          ),
          const SizedBox(height: 24),
          const Text('마이크로스텝', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text(
            '작업을 작게 쪼개면 시작하기 쉬워져요.',
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < _microSteps.length; i++)
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.check_circle_outline),
              title: Text(_microSteps[i]),
              trailing: IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: '단계 삭제',
                onPressed: () => setState(() => _microSteps.removeAt(i)),
              ),
            ),
          Row(
            children: [
              Expanded(
                child: Semantics(
                  label: '마이크로스텝 입력',
                  child: TextField(
                    controller: _microStepController,
                    decoration: const InputDecoration(hintText: '예: 책상에 앉기'),
                    onSubmitted: (_) => _addMicroStep(),
                  ),
                ),
              ),
              IconButton.filledTonal(
                onPressed: _addMicroStep,
                icon: const Icon(Icons.add),
                tooltip: '단계 추가',
              ),
            ],
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

class _MinuteStepperRow extends StatelessWidget {
  const _MinuteStepperRow({
    required this.label,
    required this.value,
    required this.suffix,
    required this.onChanged,
  });

  final String label;
  final int value;
  final String suffix;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(width: 88, child: Text(label)),
        Semantics(
          label: '$label 1분 줄이기',
          container: true,
          child: IconButton.filledTonal(
            onPressed: value > 1 ? () => onChanged(value - 1) : null,
            icon: const Icon(Icons.remove),
          ),
        ),
        SizedBox(
          width: 72,
          child: Text('$value$suffix', textAlign: TextAlign.center),
        ),
        Semantics(
          label: '$label 1분 늘리기',
          container: true,
          child: IconButton.filledTonal(
            onPressed: () => onChanged(value + 1),
            icon: const Icon(Icons.add),
          ),
        ),
      ],
    );
  }
}
