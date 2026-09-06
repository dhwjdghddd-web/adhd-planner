import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/rest_day.dart';
import '../../data/models/routine_preset.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../segments/preset_management_sheet.dart';
import '../segments/segment_icons.dart';
import 'rest_day_controller.dart';

/// Full-screen or modal sheet to manage presets and off-days on a monthly calendar with multi-selection.
class RestDayCalendarSheet extends ConsumerStatefulWidget {
  const RestDayCalendarSheet({super.key});

  static Future<void> show(BuildContext context) {
    return Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const RestDayCalendarSheet()),
    );
  }

  @override
  ConsumerState<RestDayCalendarSheet> createState() => _RestDayCalendarSheetState();
}

class _RestDayCalendarSheetState extends ConsumerState<RestDayCalendarSheet> {
  late DateTime _focusedMonth;
  final Set<String> _selectedDateKeys = <String>{};

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final restDays = ref.watch(restDaysProvider).value ?? const <RestDay>[];
    final settings = ref.watch(settingsProvider).value;
    final presets = settings?.presets ?? RoutinePreset.defaultPresets;

    final presetMap = {for (final p in presets) p.id: p};
    final datePresetMap = {for (final r in restDays) r.dateKey: r.presetId};

    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;

    return Scaffold(
      appBar: AppBar(
        title: const Text('스케줄 & 프리셋 캘린더'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '프리셋 관리',
            onPressed: () => PresetManagementSheet.show(context),
          ),
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '캘린더 및 프리셋 안내',
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month navigation & header
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '이전 달',
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
                      _selectedDateKeys.clear();
                    });
                  },
                ),
                Text(
                  '${_focusedMonth.year}년 ${_focusedMonth.month}월',
                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '다음 달',
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 1);
                      _selectedDateKeys.clear();
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tip & Multi-Selection Banner
            Card(
              elevation: 0,
              color: _selectedDateKeys.isNotEmpty
                  ? theme.colorScheme.primaryContainer.withValues(alpha: 0.6)
                  : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(
                      _selectedDateKeys.isNotEmpty ? Icons.checklist_rtl : Icons.touch_app_outlined,
                      color: _selectedDateKeys.isNotEmpty
                          ? theme.colorScheme.primary
                          : theme.colorScheme.onSurfaceVariant,
                      size: 20,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        _selectedDateKeys.isNotEmpty
                            ? '${_selectedDateKeys.length}개 날짜가 선택되었습니다.\n하단에서 적용할 프리셋을 선택하세요.'
                            : '날짜를 탭하여 여러 날을 선택한 후,\n원하는 프리셋(근무일, 쉬는 날 등)을 한 번에 배정하세요.',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: _selectedDateKeys.isNotEmpty ? FontWeight.w600 : null,
                        ),
                      ),
                    ),
                    if (_selectedDateKeys.isNotEmpty)
                      TextButton(
                        onPressed: () => setState(() => _selectedDateKeys.clear()),
                        style: TextButton.styleFrom(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('선택 해제'),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Month Calendar Grid
            _PresetMonthGrid(
              month: _focusedMonth,
              selectedDateKeys: _selectedDateKeys,
              datePresetMap: datePresetMap,
              presetMap: presetMap,
              onToggleDate: (dateKey) {
                setState(() {
                  if (_selectedDateKeys.contains(dateKey)) {
                    _selectedDateKeys.remove(dateKey);
                  } else {
                    _selectedDateKeys.add(dateKey);
                  }
                });
              },
            ),
            const SizedBox(height: 16),

            // Quick Selection Actions
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                OutlinedButton.icon(
                  onPressed: () => _selectWeekends(daysInMonth),
                  icon: const Icon(Icons.weekend_outlined, size: 16),
                  label: const Text('주말 선택'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                OutlinedButton.icon(
                  onPressed: () => _selectWeekdays(daysInMonth),
                  icon: const Icon(Icons.work_outline, size: 16),
                  label: const Text('평일 선택'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
                OutlinedButton.icon(
                  onPressed: () => _clearMonthPresets(daysInMonth),
                  icon: const Icon(Icons.refresh, size: 16),
                  label: const Text('이번 달 전체 초기화'),
                  style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
                ),
              ],
            ),
          ],
        ),
      ),
      bottomSheet: _selectedDateKeys.isNotEmpty
          ? Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                    offset: const Offset(0, -2),
                  ),
                ],
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        '선택한 ${_selectedDateKeys.length}개 날짜에 프리셋 배정',
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold),
                      ),
                      InkWell(
                        onTap: () => setState(() => _selectedDateKeys.clear()),
                        child: Icon(Icons.close, size: 18, color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final preset in presets) ...[
                          _PresetActionButton(
                            preset: preset,
                            onTap: () => _applyPresetToSelected(preset),
                          ),
                          const SizedBox(width: 8),
                        ],
                        OutlinedButton.icon(
                          onPressed: _clearSelectedPresets,
                          icon: const Icon(Icons.clear, size: 16),
                          label: const Text('기본값(해제)'),
                          style: OutlinedButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }

  void _selectWeekends(int daysInMonth) {
    setState(() {
      for (var d = 1; d <= daysInMonth; d++) {
        final dt = DateTime(_focusedMonth.year, _focusedMonth.month, d);
        if (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday) {
          _selectedDateKeys.add(DateFormat('yyyy-MM-dd').format(dt));
        }
      }
    });
  }

  void _selectWeekdays(int daysInMonth) {
    setState(() {
      for (var d = 1; d <= daysInMonth; d++) {
        final dt = DateTime(_focusedMonth.year, _focusedMonth.month, d);
        if (dt.weekday >= DateTime.monday && dt.weekday <= DateTime.friday) {
          _selectedDateKeys.add(DateFormat('yyyy-MM-dd').format(dt));
        }
      }
    });
  }

  Future<void> _applyPresetToSelected(RoutinePreset preset) async {
    final count = _selectedDateKeys.length;
    final keys = Set<String>.from(_selectedDateKeys);
    await ref.read(restDayControllerProvider).setPresetForDates(keys, preset.id);

    if (!mounted) return;
    setState(() => _selectedDateKeys.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count개 날짜에 [${preset.name}] 프리셋이 배정되었습니다.')),
    );
  }

  Future<void> _clearSelectedPresets() async {
    final count = _selectedDateKeys.length;
    final keys = Set<String>.from(_selectedDateKeys);
    await ref.read(restDayControllerProvider).clearDates(keys);

    if (!mounted) return;
    setState(() => _selectedDateKeys.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$count개 날짜의 프리셋이 기본값으로 초기화되었습니다.')),
    );
  }

  Future<void> _clearMonthPresets(int daysInMonth) async {
    final monthKeys = <String>[];
    for (var d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      monthKeys.add(DateFormat('yyyy-MM-dd').format(dt));
    }
    await ref.read(restDayControllerProvider).clearDates(monthKeys);

    if (!mounted) return;
    setState(() => _selectedDateKeys.clear());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${_focusedMonth.month}월 일정이 모두 기본값으로 초기화되었습니다.')),
    );
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('캘린더 및 프리셋 작동 안내'),
        content: const SingleChildScrollView(
          child: Text(
            '• [프리셋별 알람 및 시간표]:\n'
            '  각 날짜에 원하는 프리셋(근무일, 쉬는 날, 커스텀 프리셋)을 배정할 수 있습니다.\n'
            '  배정된 날에는 해당 프리셋에 등록된 시간표와 알람 규칙이 자동으로 적용됩니다.\n\n'
            '• [다중 날짜 일괄 배정]:\n'
            '  원하는 날짜들을 탭하여 여러 개 선택한 뒤, 하단에 나타나는 프리셋 버튼을 누르면 한 번에 배정됩니다.\n\n'
            '• [미지정 날짜]:\n'
            '  별도로 프리셋을 배정하지 않은 날은 기본값인 [근무일]로 동작합니다.\n\n'
            '• [프리셋 관리]:\n'
            '  상단의 조절기 아이콘을 눌러 새 프리셋(예: 교대근무, 당직, 주말 등)을 생성하고 관리할 수 있습니다.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }
}

class _PresetActionButton extends StatelessWidget {
  const _PresetActionButton({
    required this.preset,
    required this.onTap,
  });

  final RoutinePreset preset;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = Color(preset.colorValue);
    return FilledButton.icon(
      onPressed: onTap,
      style: FilledButton.styleFrom(
        backgroundColor: color.withValues(alpha: 0.18),
        foregroundColor: color,
        side: BorderSide(color: color.withValues(alpha: 0.6)),
        visualDensity: VisualDensity.compact,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      ),
      icon: Icon(iconForKey(preset.iconKey), size: 16),
      label: Text(preset.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
    );
  }
}

class _PresetMonthGrid extends StatelessWidget {
  const _PresetMonthGrid({
    required this.month,
    required this.selectedDateKeys,
    required this.datePresetMap,
    required this.presetMap,
    required this.onToggleDate,
  });

  final DateTime month;
  final Set<String> selectedDateKeys;
  final Map<String, String> datePresetMap;
  final Map<String, RoutinePreset> presetMap;
  final ValueChanged<String> onToggleDate;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    final startingOffset = firstDayOfMonth.weekday - 1;
    final totalCells = ((startingOffset + daysInMonth + 6) ~/ 7) * 7;
    final todayKey = dayKeyFor();

    return Column(
      children: [
        // Weekday header
        Row(
          children: [
            for (var i = 0; i < 7; i++)
              Expanded(
                child: Center(
                  child: Text(
                    _weekdays[i],
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: i >= 5 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 8),

        // Grid cells
        for (var row = 0; row < totalCells / 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++) ...[
                () {
                  final cellIndex = row * 7 + col;
                  final dayNum = cellIndex - startingOffset + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 62));
                  }

                  final date = DateTime(month.year, month.month, dayNum);
                  final dateKey = DateFormat('yyyy-MM-dd').format(date);
                  final isSelected = selectedDateKeys.contains(dateKey);
                  final isToday = dateKey == todayKey;

                  final presetId = datePresetMap[dateKey];
                  final preset = presetId != null ? presetMap[presetId] : null;

                  final Color? cellBg;
                  final Border? cellBorder;

                  if (isSelected) {
                    cellBg = theme.colorScheme.primaryContainer.withValues(alpha: 0.6);
                    cellBorder = Border.all(color: theme.colorScheme.primary, width: 2.0);
                  } else if (preset != null) {
                    final pColor = Color(preset.colorValue);
                    cellBg = pColor.withValues(alpha: 0.14);
                    cellBorder = Border.all(color: pColor.withValues(alpha: 0.5), width: 1.2);
                  } else if (isToday) {
                    cellBg = theme.colorScheme.surfaceContainerHighest;
                    cellBorder = Border.all(color: theme.colorScheme.primary, width: 1.5);
                  } else {
                    cellBg = null;
                    cellBorder = Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.25));
                  }

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onToggleDate(dateKey),
                      child: Container(
                        height: 62,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: cellBg,
                          borderRadius: BorderRadius.circular(10),
                          border: cellBorder,
                        ),
                        child: Stack(
                          children: [
                            if (isSelected)
                              Positioned(
                                top: 2,
                                right: 2,
                                child: Icon(
                                  Icons.check_circle,
                                  size: 14,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                            Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(
                                    '$dayNum',
                                    style: theme.textTheme.labelMedium?.copyWith(
                                      fontWeight: isToday || isSelected || preset != null ? FontWeight.bold : null,
                                      color: col >= 5 && preset == null
                                          ? theme.colorScheme.error
                                          : null,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  if (preset != null) ...[
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: Color(preset.colorValue).withValues(alpha: 0.2),
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: Text(
                                        preset.name,
                                        style: TextStyle(
                                          fontSize: 9,
                                          fontWeight: FontWeight.bold,
                                          color: Color(preset.colorValue),
                                        ),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ] else
                                    const SizedBox(height: 14),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                }(),
              ],
            ],
          ),
      ],
    );
  }
}
