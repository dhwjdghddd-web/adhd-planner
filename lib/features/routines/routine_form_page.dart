import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../memos/quick_add_button.dart';
import '../segments/segment_icons.dart';
import 'routines_controller.dart';

const _uuid = Uuid();

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
  final _microStepFocusNode = FocusNode();
  final _microStepInputKey = GlobalKey();
  late int _startMinute;
  late bool _alarmEnabled;
  late int _leadWarningMin;
  late int _snoozeMin;
  late Set<int> _repeatDays;
  late List<String> _microSteps;

  @override
  void initState() {
    super.initState();
    final existing = widget.existing;
    final now = TimeOfDay.now();

    _titleController = TextEditingController(text: existing?.title ?? '');
    _noteController = TextEditingController(text: existing?.note ?? '');
    _microStepController = TextEditingController();
    _startMinute = existing?.startMinute ?? now.hour * 60 + now.minute;
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
    _microStepFocusNode.dispose();
    super.dispose();
  }

  bool get _isEditing => widget.existing != null;

  bool get _canSave => _titleController.text.trim().isNotEmpty;

  /// The segment whose time range covers [startMinute], if any — segments
  /// are purely a visual category (marker color/icon + dial lane) derived
  /// from when the routine actually starts, not something the user picks
  /// separately, so there's no real "no segment selected" failure mode here.
  static Segment? _autoSegment(List<Segment> segments, int startMinute) {
    for (final segment in segments) {
      if (segment.containsMinute(startMinute)) return segment;
    }
    return null;
  }

  // A scrollable 24h wheel (no AM/PM, no separate keyboard-entry mode)
  // instead of the standard dial/keyboard showTimePicker — swiping each
  // column directly matches how the rest of this app's time inputs work.
  Future<void> _pickStartTime() async {
    var pickedMinute = _startMinute;
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: 216,
              child: CupertinoDatePicker(
                mode: CupertinoDatePickerMode.time,
                use24hFormat: true,
                initialDateTime: DateTime(
                  2000,
                  1,
                  1,
                  _startMinute ~/ 60,
                  _startMinute % 60,
                ),
                onDateTimeChanged: (dt) =>
                    pickedMinute = dt.hour * 60 + dt.minute,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.pop(sheetContext, true),
                  child: const Text('확인'),
                ),
              ),
            ),
          ],
        ),
      ),
    );
    if (confirmed != true) return;
    setState(() => _startMinute = pickedMinute);
  }

  void _addMicroStep() {
    final text = _microStepController.text.trim();
    if (text.isEmpty) return;
    setState(() {
      _microSteps.add(text);
      _microStepController.clear();
    });
    // Without this, tapping the + button (which isn't the text field
    // itself) drops focus and dismisses the keyboard, forcing a re-tap
    // before typing the next step -- re-requesting keeps it open so
    // several steps can be added back-to-back.
    _microStepFocusNode.requestFocus();
    // Otherwise the input row only scrolls into view once the keyboard's
    // own "scroll to the focused field" kicks in on the next keystroke --
    // a new step pushes the row further down the list right as it's
    // added, so it should already be visible by then, not after typing.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final inputContext = _microStepInputKey.currentContext;
      if (inputContext == null) return;
      Scrollable.ensureVisible(
        inputContext,
        duration: const Duration(milliseconds: 200),
      );
    });
  }

  // Not awaited: Firestore's write Future only resolves once the backend
  // acknowledges it, which never happens while offline. The local cache
  // updates synchronously either way, so blocking the pop on it would just
  // leave the form stuck open with no feedback when there's no connection.
  void _save() {
    if (!_canSave) return;

    final controller = ref.read(routinesControllerProvider);
    final segments = ref.read(segmentsProvider).value ?? const <Segment>[];
    final routine = Routine(
      id: widget.existing?.id ?? _uuid.v4(),
      segmentId: _autoSegment(segments, _startMinute)?.id,
      title: _titleController.text.trim(),
      note: _noteController.text.trim(),
      microSteps: _microSteps,
      startMinute: _startMinute,
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
      unawaited(ref.read(routinesControllerProvider).delete(existing.id));
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final segments = ref.watch(segmentsProvider).value ?? const <Segment>[];
    final theme = Theme.of(context);
    final autoSegment = _autoSegment(segments, _startMinute);

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
      // Shrinks the visible body area itself (rather than padding inside
      // the ListView, which only shows up once scrolled all the way down)
      // so the 저장 button and the fields above it never end up under the
      // global bottom-left quick-add FAB even before scrolling.
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: ListView(
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
            // Segment is derived from the start time below, not chosen here —
            // this just shows what that comes out to so it's not a total
            // mystery, with no way for it to drift from the actual time.
            Semantics(
              label: '소속 구간: ${autoSegment?.name ?? '구간 없음'} (시작 시각에 따라 자동 결정)',
              child: Row(
                children: [
                  Icon(
                    iconForKey(autoSegment?.iconKey ?? ''),
                    color: autoSegment?.color ?? theme.disabledColor,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    autoSegment?.name ?? '구간 없음',
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
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
            const Text(
              '반복 요일 (선택 안 하면 매일)',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
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
            Text('작업을 작게 쪼개면 시작하기 쉬워져요.', style: theme.textTheme.bodySmall),
            const SizedBox(height: 8),
            for (var i = 0; i < _microSteps.length; i++)
              ListTile(
                key: ValueKey('microStep$i-${_microSteps[i]}'),
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
              // Without this, adding a step shifts this Row one slot later
              // in the surrounding ListView's unkeyed children (the new
              // ListTile takes its old slot) -- Flutter then sees a type
              // mismatch at that slot and disposes+recreates this whole
              // Row, tearing down the TextField's EditableText (and with
              // it the IME connection) on every single 추가 tap.
              key: _microStepInputKey,
              children: [
                Expanded(
                  child: Semantics(
                    label: '마이크로스텝 입력',
                    child: TextField(
                      controller: _microStepController,
                      focusNode: _microStepFocusNode,
                      decoration: const InputDecoration(hintText: '예: 책상에 앉기'),
                      textInputAction: TextInputAction.done,
                      onSubmitted: (_) => _addMicroStep(),
                    ),
                  ),
                ),
                // Kept on top of the key fix above: a focusable button
                // stealing focus on tap would otherwise still dismiss the
                // keyboard in its own right.
                ExcludeFocus(
                  child: IconButton.filledTonal(
                    onPressed: _addMicroStep,
                    icon: const Icon(Icons.add),
                    tooltip: '단계 추가',
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
