import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/screen_mode.dart';
import '../../core/time_geometry.dart';
import '../../core/wheel_time_picker.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../memos/quick_add_button.dart';
import '../../data/models/routine_preset.dart';
import 'multi_date_picker_dialog.dart';
import 'segment_icons.dart';
import 'segments_controller.dart';

const _uuid = Uuid();

/// Add/edit form for a single block (segment): its name, colour, icon, time
/// range, optional start-of-block alarm, and its checklist of "루틴" items.
/// Reachable from [SegmentEditorPage]'s list, the home dial's "구간 추가" FAB,
/// or by tapping a block's arc on the home dial.
class SegmentFormPage extends ConsumerStatefulWidget {
  const SegmentFormPage({
    super.key,
    this.existing,
    this.initialName,
    this.initialPresetId,
  });

  final Segment? existing;

  /// Pre-fills the name field for a brand-new block (e.g. promoting a memo's
  /// text straight into a block) — ignored when [existing] is set, since an
  /// edit always starts from that block's own name.
  final String? initialName;
  final String? initialPresetId;

  @override
  ConsumerState<SegmentFormPage> createState() => _SegmentFormPageState();
}

class _SegmentFormPageState extends ConsumerState<SegmentFormPage> {
  late TextEditingController _nameController;
  late TextEditingController _noteController;
  late TextEditingController _microStepController;
  final _microStepFocusNode = FocusNode();
  final _microStepInputKey = GlobalKey();
  late int _colorValue;
  late String _iconKey;
  late int _startMinute;
  late int _endMinute;
  late SegmentAlarmType _alarmType;
  late SegmentScheduleTarget _scheduleTarget;
  late int _leadWarningMinutes;
  late bool _isFirstBlock;
  late Map<String, int> _dateOverrides;
  late String _presetId;
  late List<String> _microSteps;
  // Parallel to _microSteps, one stable id per item so ReorderableListView can
  // track each item's identity across reorders -- the items are plain strings
  // (and can repeat), so text/index alone can't serve as a stable key.
  late List<int> _microStepKeyIds;
  int _nextMicroStepKeyId = 0;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    _nameController = TextEditingController(
      text: existing?.name ?? widget.initialName ?? '',
    );
    _noteController = TextEditingController(text: existing?.note ?? '');
    _microStepController = TextEditingController();
    _colorValue = existing?.colorValue ?? kSegmentPalette.first.toARGB32();
    _iconKey = existing?.iconKey ?? kSegmentIcons.keys.first;
    _startMinute = existing?.startMinute ?? 6 * 60;
    _endMinute = existing?.endMinute ?? 12 * 60;
    _alarmType = existing?.alarmType ?? SegmentAlarmType.fullScreen;
    _scheduleTarget = existing?.scheduleTarget ?? SegmentScheduleTarget.everyday;
    _leadWarningMinutes = existing?.leadWarningMinutes ?? 10;
    _isFirstBlock = existing?.isFirstBlock ?? false;
    _dateOverrides = Map<String, int>.from(existing?.dateOverrides ?? {});
    _presetId = existing?.presetId ?? widget.initialPresetId ?? 'work';
    _microSteps = [...(existing?.microSteps ?? const <String>[])];
    _microStepKeyIds = List.generate(
      _microSteps.length,
      (_) => _nextMicroStepKeyId++,
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _noteController.dispose();
    _microStepController.dispose();
    _microStepFocusNode.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  int get _lengthMinutes =>
      TimeGeometry.lengthMinutes(_startMinute, _endMinute);

  bool get _canSave =>
      _nameController.text.trim().isNotEmpty && _lengthMinutes > 0;

  // A scrollable 24h wheel (no AM/PM, no separate keyboard-entry mode) instead
  // of the standard dial/keyboard showTimePicker.
  Future<int?> _pickWheelMinute(int initialMinute) =>
      pickWheelMinute(context, initialMinute);

  // Confirming the start time chains straight into the end-time picker --
  // entering a block's range is one continuous action.
  Future<void> _pickStartTime() async {
    final picked = await _pickWheelMinute(_startMinute);
    if (picked == null) return;
    setState(() => _startMinute = picked);
    await _pickEndTime();
  }

  Future<void> _pickEndTime() async {
    final picked = await _pickWheelMinute(_endMinute);
    if (picked == null) return;
    setState(() => _endMinute = picked);
  }

  void _addMicroStep() {
    final text = _microStepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _microSteps.add(text);
      _microStepKeyIds.add(_nextMicroStepKeyId++);
      _microStepController.clear();
    });
    // Keep the keyboard open so several items can be added back-to-back.
    _microStepFocusNode.requestFocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inputContext = _microStepInputKey.currentContext;
      if (inputContext == null) return;
      Scrollable.ensureVisible(
        inputContext,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  Future<void> _addDateOverride() async {
    final pickedDates = await MultiDatePickerDialog.show(
      context,
      title: '기상 시간 다르게 설정할 날짜 선택',
    );
    if (pickedDates == null || pickedDates.isEmpty || !mounted) return;

    final dateSummary = pickedDates.length == 1
        ? pickedDates.first
        : '${pickedDates.length}개 날짜 선택됨';

    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
              child: Text(
                '$dateSummary 기상 알람 설정',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.access_time),
              title: const Text('기상 시간 직접 설정'),
              subtitle: const Text('선택한 날짜들에 일어날 시각을 일괄 지정합니다'),
              onTap: () => Navigator.pop(ctx, 'time'),
            ),
            ListTile(
              leading: const Icon(Icons.notifications_off_outlined, color: Colors.orange),
              title: const Text('알람 없음 (울리지 않음)'),
              subtitle: const Text('선택한 날짜들에는 아침 기상 알람이 울리지 않습니다'),
              onTap: () => Navigator.pop(ctx, 'none'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;

    if (action == 'none') {
      setState(() {
        for (final d in pickedDates) {
          _dateOverrides[d] = Segment.noAlarmMinute;
        }
      });
      return;
    }

    final pickedMinute = await pickWheelMinute(context, _startMinute);
    if (pickedMinute == null || !mounted) return;

    setState(() {
      for (final d in pickedDates) {
        _dateOverrides[d] = pickedMinute;
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
      note: _noteController.text.trim(),
      microSteps: _microSteps,
      alarmType: _alarmType,
      scheduleTarget: _scheduleTarget,
      leadWarningMinutes: _leadWarningMinutes,
      isFirstBlock: _isFirstBlock,
      dateOverrides: _dateOverrides,
      presetId: _presetId,
      notificationIds: widget.existing?.notificationIds ?? const [],
    );

    if (controller.overlapsAny(segment, segments)) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('시간이 겹쳐요'),
          content: const Text(
            '다른 구간과 시간이 겹칩니다. 그래도 저장할까요? (원형에서 안쪽 링으로 표시됩니다)',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('취소'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('저장'),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Not awaited: Firestore's write Future only resolves once the backend
    // acknowledges it, which never happens while offline. The local cache
    // updates synchronously either way.
    unawaited(controller.upsert(segment));
    if (mounted) Navigator.pop(context, true);
  }

  Future<void> _confirmDelete() async {
    final existing = widget.existing;
    if (existing == null) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('구간 삭제'),
        content: Text('"${existing.name}" 구간과 그 안의 루틴이 삭제됩니다. 삭제할까요?'),
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
      unawaited(ref.read(segmentsControllerProvider).delete(existing.id));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final lengthOk = _lengthMinutes > 0;

    return Scaffold(
      appBar: AppBar(title: Text(_isEditing ? '구간 수정' : '구간 추가')),
      // Delete FAB: bottom-right, mirroring the global memo FAB on the left.
      // Only shown in edit mode — new blocks have nothing to delete yet.
      floatingActionButton: _isEditing
          ? (isCompactLayout(context)
                ? FloatingActionButton.small(
                    heroTag: 'segment-delete',
                    onPressed: _confirmDelete,
                    tooltip: '구간 삭제',
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    child: const Icon(Icons.delete_outline),
                  )
                : FloatingActionButton(
                    heroTag: 'segment-delete',
                    onPressed: _confirmDelete,
                    tooltip: '구간 삭제',
                    backgroundColor: theme.colorScheme.errorContainer,
                    foregroundColor: theme.colorScheme.onErrorContainer,
                    child: const Icon(Icons.delete_outline),
                  ))
          : null,
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text('소속 프리셋', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Builder(
              builder: (context) {
                final presets = ref.watch(settingsProvider).value?.presets ??
                    RoutinePreset.defaultPresets;
                return Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final p in presets)
                      ChoiceChip(
                        avatar: Icon(
                          p.id == 'rest' ? Icons.beach_access : Icons.work,
                          size: 16,
                          color: _presetId == p.id
                              ? theme.colorScheme.onPrimary
                              : null,
                        ),
                        label: Text(p.name),
                        selected: _presetId == p.id,
                        onSelected: (_) => setState(() => _presetId = p.id),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(height: 20),
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
            const Text('색', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: kSegmentPalette.map((color) {
                final brightness = Theme.of(context).brightness;
                final displayColor = getEffectiveSegmentColor(
                  color,
                  brightness,
                );
                final value = color.toARGB32();
                final selected =
                    getEffectiveSegmentColor(
                      Color(_colorValue),
                      brightness,
                    ).toARGB32() ==
                    displayColor.toARGB32();
                return Semantics(
                  label: '색상 선택',
                  selected: selected,
                  child: GestureDetector(
                    onTap: () => setState(() => _colorValue = value),
                    child: Container(
                      width: kMinTapTarget,
                      height: kMinTapTarget,
                      decoration: BoxDecoration(
                        color: displayColor,
                        shape: BoxShape.circle,
                        border: selected
                            ? Border.all(
                                color: theme.colorScheme.onSurface,
                                width: 3,
                              )
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
                            ? theme.colorScheme.primaryContainer
                            : theme.colorScheme.surfaceContainerHighest,
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
              onTap: _pickStartTime,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('끝나는 시각'),
              subtitle: Text(TimeGeometry.formatMinute(_endMinute)),
              trailing: const Icon(Icons.access_time),
              onTap: _pickEndTime,
            ),
            const SizedBox(height: 8),
            Text(
              lengthOk ? '길이: $_lengthMinutes분' : '시작과 끝 시각이 같아요. 길이가 0분이 됩니다.',
              style: TextStyle(
                color: lengthOk
                    ? theme.colorScheme.onSurfaceVariant
                    : theme.colorScheme.error,
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 0,
              color: _isFirstBlock
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.3)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
                side: BorderSide(
                  color: _isFirstBlock
                      ? theme.colorScheme.primary.withValues(alpha: 0.5)
                      : theme.colorScheme.outlineVariant,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SwitchListTile.adaptive(
                      contentPadding: EdgeInsets.zero,
                      secondary: Icon(
                        Icons.wb_twilight,
                        color: _isFirstBlock ? theme.colorScheme.primary : null,
                      ),
                      title: const Text(
                        '하루의 첫 번째 블록 (기상 블록)',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: const Text(
                        '아침 기상 블록으로 지정하고, 특정일 기상 시간을 다르게 설정할 수 있어요',
                        style: TextStyle(fontSize: 12),
                      ),
                      value: _isFirstBlock,
                      onChanged: (val) => setState(() => _isFirstBlock = val),
                    ),
                    if (_isFirstBlock) ...[
                      const Divider(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            '📅 특정일 기상 시간 변경',
                            style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                          ),
                          TextButton.icon(
                            onPressed: _addDateOverride,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('날짜 추가'),
                          ),
                        ],
                      ),
                      if (_dateOverrides.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 6),
                          child: Text(
                            '설정된 특정일이 없어요. 평소와 다른 시간에 일어나는 날이 있다면 추가해 보세요.',
                            style: TextStyle(fontSize: 12, color: Colors.grey),
                          ),
                        )
                      else ...[
                        const SizedBox(height: 4),
                        for (final entry in (_dateOverrides.entries.toList()..sort((a, b) => a.key.compareTo(b.key))))
                          Builder(
                            builder: (context) {
                              final isNone = entry.value == Segment.noAlarmMinute;
                              return Container(
                                margin: const EdgeInsets.only(bottom: 6),
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.surface,
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                    color: isNone
                                        ? Colors.orange.withValues(alpha: 0.5)
                                        : theme.colorScheme.outlineVariant,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      isNone ? Icons.notifications_off_outlined : Icons.alarm,
                                      size: 16,
                                      color: isNone ? Colors.orange : theme.colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        isNone
                                            ? '${entry.key} ➔ 🔕 알람 없음 (울리지 않음)'
                                            : '${entry.key} ➔ ${TimeGeometry.formatMinute(entry.value)} 기상',
                                        style: TextStyle(
                                          fontWeight: FontWeight.w500,
                                          fontSize: 13,
                                          color: isNone ? Colors.orange.shade800 : null,
                                        ),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 18),
                                      tooltip: '삭제',
                                      padding: EdgeInsets.zero,
                                      constraints: const BoxConstraints(),
                                      onPressed: () {
                                        setState(() {
                                          _dateOverrides.remove(entry.key);
                                        });
                                      },
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),
                      ],
                    ],
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('알람 강도 / 유형', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                ChoiceChip(
                  label: const Text('🚨 강력 알람'),
                  selected: _alarmType == SegmentAlarmType.fullScreen,
                  onSelected: (selected) {
                    if (selected) setState(() => _alarmType = SegmentAlarmType.fullScreen);
                  },
                ),
                ChoiceChip(
                  label: const Text('🔔 부드러운 알림'),
                  selected: _alarmType == SegmentAlarmType.gentle,
                  onSelected: (selected) {
                    if (selected) setState(() => _alarmType = SegmentAlarmType.gentle);
                  },
                ),
                ChoiceChip(
                  label: const Text('📳 진동만'),
                  selected: _alarmType == SegmentAlarmType.hapticOnly,
                  onSelected: (selected) {
                    if (selected) setState(() => _alarmType = SegmentAlarmType.hapticOnly);
                  },
                ),
                ChoiceChip(
                  label: const Text('🚫 알람 끔'),
                  selected: _alarmType == SegmentAlarmType.none,
                  onSelected: (selected) {
                    if (selected) setState(() => _alarmType = SegmentAlarmType.none);
                  },
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              switch (_alarmType) {
                SegmentAlarmType.fullScreen => '잠금화면을 덮는 전체화면 알람 + 1분간 반복 벨소리/진동',
                SegmentAlarmType.gentle => '상단 배너 푸시 알림 + 1회 알림음',
                SegmentAlarmType.hapticOnly => '소리 없이 햅틱 진동만 1회',
                SegmentAlarmType.none => '알람 없이 다이얼에만 표시',
              },
              style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
            if (_alarmType != SegmentAlarmType.none) ...[
              const SizedBox(height: 16),
              const Text('울리는 날짜 조건', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('🔄 매일'),
                    selected: _scheduleTarget == SegmentScheduleTarget.everyday,
                    onSelected: (selected) {
                      if (selected) setState(() => _scheduleTarget = SegmentScheduleTarget.everyday);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('🏢 근무일에만'),
                    selected: _scheduleTarget == SegmentScheduleTarget.workDaysOnly,
                    onSelected: (selected) {
                      if (selected) setState(() => _scheduleTarget = SegmentScheduleTarget.workDaysOnly);
                    },
                  ),
                  ChoiceChip(
                    label: const Text('🏖️ 쉬는 날(휴일)에만'),
                    selected: _scheduleTarget == SegmentScheduleTarget.restDaysOnly,
                    onSelected: (selected) {
                      if (selected) setState(() => _scheduleTarget = SegmentScheduleTarget.restDaysOnly);
                    },
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                switch (_scheduleTarget) {
                  SegmentScheduleTarget.everyday => '쉬는 날 여부와 관계없이 매일 울려요.',
                  SegmentScheduleTarget.workDaysOnly => '쉬는 날(휴일 캘린더 등록일)에는 자동으로 울리지 않아요.',
                  SegmentScheduleTarget.restDaysOnly => '쉬는 날(휴일 캘린더 등록일)에만 특별히 울려요.',
                },
                style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 16),
              const Text('전환 예고', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final mins in const [0, 5, 10, 15, 30])
                    ChoiceChip(
                      label: Text(mins == 0 ? '예고 없음' : '$mins분 전'),
                      selected: _leadWarningMinutes == mins,
                      onSelected: (selected) {
                        if (selected) setState(() => _leadWarningMinutes = mins);
                      },
                    ),
                ],
              ),
            ],
            const SizedBox(height: 16),
            const Text('루틴', style: TextStyle(fontWeight: FontWeight.bold)),
            const SizedBox(height: 4),
            Text('이 구간에 할 일을 작게 쪼개 적어두세요.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            // 꾹 눌러서 드래그하면 순서를 바꿀 수 있음 (별도 핸들 없이 항목 전체가
            // long-press로 드래그됨).
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _microSteps.length,
              onReorderItem: (oldIndex, newIndex) => setState(() {
                _microSteps.insert(newIndex, _microSteps.removeAt(oldIndex));
                _microStepKeyIds.insert(
                  newIndex,
                  _microStepKeyIds.removeAt(oldIndex),
                );
              }),
              itemBuilder: (context, i) => ListTile(
                key: ValueKey(_microStepKeyIds[i]),
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.check_circle_outline),
                title: Text(_microSteps[i]),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline),
                  tooltip: '루틴 삭제',
                  onPressed: () => setState(() {
                    _microSteps.removeAt(i);
                    _microStepKeyIds.removeAt(i);
                  }),
                ),
              ),
            ),
            Row(
              // Without this stable key, adding an item shifts this Row one slot
              // later in the ListView's unkeyed children -- Flutter then
              // disposes+recreates this whole Row, tearing down the TextField's
              // IME connection on every 추가 tap.
              key: _microStepInputKey,
              children: [
                Expanded(
                  child: Semantics(
                    label: '루틴 입력',
                    child: TextField(
                      controller: _microStepController,
                      focusNode: _microStepFocusNode,
                      decoration: const InputDecoration(hintText: '예: 책상에 앉기'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addMicroStep(),
                    ),
                  ),
                ),
                ExcludeFocus(
                  child: IconButton.filledTonal(
                    onPressed: _addMicroStep,
                    icon: const Icon(Icons.add),
                    tooltip: '루틴 추가',
                  ),
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
      ),
    );
  }
}
