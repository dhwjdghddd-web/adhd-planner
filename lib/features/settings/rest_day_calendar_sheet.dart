import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../data/models/rest_day.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import 'rest_day_controller.dart';

/// Full-screen or modal sheet to manage irregular rest days (Off-Days) on a monthly calendar.
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
    final restDateKeys = restDays.map((r) => r.dateKey).toSet();

    final monthKey = DateFormat('yyyy-MM').format(_focusedMonth);
    final monthRestCount = restDateKeys.where((k) => k.startsWith(monthKey)).length;

    return Scaffold(
      appBar: AppBar(
        title: const Text('쉬는 날(휴일) 캘린더'),
        actions: [
          IconButton(
            icon: const Icon(Icons.help_outline),
            tooltip: '휴일 알람 안내',
            onPressed: () => _showHelpDialog(context),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Month navigation & summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '이전 달',
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(_focusedMonth.year, _focusedMonth.month - 1, 1);
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
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Tip Banner
            Card(
              elevation: 0,
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.coffee, color: theme.colorScheme.primary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        '날짜를 탭하여 쉬는 날(☕)을 지정하세요.\n쉬는 날엔 ‘근무일 전용’ 알람이 자동으로 울리지 않아요.',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '총 $monthRestCount일 쉼',
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.onPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 12),

            // Month Calendar Grid
            _RestMonthGrid(
              month: _focusedMonth,
              restDateKeys: restDateKeys,
              onToggleDate: (dateKey) {
                ref.read(restDayControllerProvider).toggle(dateKey);
              },
            ),
            const SizedBox(height: 20),

            // Quick Batch Actions
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _toggleWeekends(true),
                    icon: const Icon(Icons.weekend_outlined, size: 18),
                    label: const Text('주말 일괄 지정'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _clearMonthRestDays(),
                    icon: const Icon(Icons.clear_all, size: 18),
                    label: const Text('이번 달 초기화'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _toggleWeekends(bool isRest) async {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final controller = ref.read(restDayControllerProvider);

    for (var d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      if (dt.weekday == DateTime.saturday || dt.weekday == DateTime.sunday) {
        final dKey = DateFormat('yyyy-MM-dd').format(dt);
        await controller.setRestDay(dKey, isRest);
      }
    }
  }

  void _clearMonthRestDays() async {
    final daysInMonth = DateTime(_focusedMonth.year, _focusedMonth.month + 1, 0).day;
    final controller = ref.read(restDayControllerProvider);

    for (var d = 1; d <= daysInMonth; d++) {
      final dt = DateTime(_focusedMonth.year, _focusedMonth.month, d);
      final dKey = DateFormat('yyyy-MM-dd').format(dt);
      await controller.setRestDay(dKey, false);
    }
  }

  void _showHelpDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('쉬는 날(휴일) 알람 작동 방식'),
        content: const Text(
          '• [근무일에만]으로 설정된 루틴:\n'
          '  쉬는 날(☕)로 지정된 날에는 알람이 자동으로 울리지 않습니다.\n\n'
          '• [쉬는 날에만]으로 설정된 루틴:\n'
          '  쉬는 날(☕)로 지정된 날에만 알람이 울립니다.\n\n'
          '• [매일]로 설정된 루틴:\n'
          '  쉬는 날 여부와 상관없이 매일 항상 알람이 울립니다.\n\n'
          '불규칙한 교대근무나 휴무일을 미리 등록해두시면 편안하게 휴식을 취하실 수 있습니다.',
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

class _RestMonthGrid extends StatelessWidget {
  const _RestMonthGrid({
    required this.month,
    required this.restDateKeys,
    required this.onToggleDate,
  });

  final DateTime month;
  final Set<String> restDateKeys;
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
                    return const Expanded(child: SizedBox(height: 56));
                  }

                  final date = DateTime(month.year, month.month, dayNum);
                  final dateKey = DateFormat('yyyy-MM-dd').format(date);
                  final isRest = restDateKeys.contains(dateKey);
                  final isToday = dateKey == todayKey;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onToggleDate(dateKey),
                      child: Container(
                        height: 56,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isRest
                              ? theme.colorScheme.tertiaryContainer.withValues(alpha: 0.6)
                              : isToday
                              ? theme.colorScheme.surfaceContainerHighest
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          border: isToday
                              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                              : isRest
                              ? Border.all(color: theme.colorScheme.tertiary, width: 1.0)
                              : Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNum',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: isToday || isRest ? FontWeight.bold : null,
                                color: isRest
                                    ? theme.colorScheme.onTertiaryContainer
                                    : col >= 5
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                            const SizedBox(height: 2),
                            if (isRest)
                              const Icon(Icons.coffee, size: 16, color: Colors.brown)
                            else
                              const SizedBox(height: 16),
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
