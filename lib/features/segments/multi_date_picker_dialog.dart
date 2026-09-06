import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

/// Interactive monthly calendar dialog that allows multiple dates to be
/// selected at once. Returns the set of selected "yyyy-MM-dd" dateKeys.
class MultiDatePickerDialog extends StatefulWidget {
  const MultiDatePickerDialog({
    super.key,
    this.initialDates = const {},
    this.title = '날짜 선택 (다중 선택 가능)',
  });

  final Set<String> initialDates;
  final String title;

  static Future<Set<String>?> show(
    BuildContext context, {
    Set<String> initialDates = const {},
    String title = '날짜 선택 (다중 선택 가능)',
  }) {
    return showDialog<Set<String>>(
      context: context,
      builder: (_) => MultiDatePickerDialog(
        initialDates: initialDates,
        title: title,
      ),
    );
  }

  @override
  State<MultiDatePickerDialog> createState() => _MultiDatePickerDialogState();
}

class _MultiDatePickerDialogState extends State<MultiDatePickerDialog> {
  late DateTime _focusedMonth;
  late Set<String> _selectedDates;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDates = Set<String>.from(widget.initialDates);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final daysInMonth = DateUtils.getDaysInMonth(
      _focusedMonth.year,
      _focusedMonth.month,
    );
    final firstWeekday =
        DateTime(_focusedMonth.year, _focusedMonth.month, 1).weekday % 7;

    return AlertDialog(
      titlePadding: const EdgeInsets.fromLTRB(20, 16, 16, 8),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      title: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              widget.title,
              style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
      content: SizedBox(
        width: 340,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Month navigation
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.chevron_left),
                  tooltip: '이전 달',
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month - 1,
                        1,
                      );
                    });
                  },
                ),
                Text(
                  '년 월',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.chevron_right),
                  tooltip: '다음 달',
                  onPressed: () {
                    setState(() {
                      _focusedMonth = DateTime(
                        _focusedMonth.year,
                        _focusedMonth.month + 1,
                        1,
                      );
                    });
                  },
                ),
              ],
            ),
            const SizedBox(height: 8),

            // Weekday headers
            Row(
              children: [
                for (final day in ['일', '월', '화', '수', '목', '금', '토'])
                  Expanded(
                    child: Center(
                      child: Text(
                        day,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: day == '일'
                              ? Colors.redAccent
                              : (day == '토'
                                  ? Colors.blueAccent
                                  : theme.colorScheme.onSurfaceVariant),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),

            // Calendar grid
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: firstWeekday + daysInMonth,
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisSpacing: 4,
                crossAxisSpacing: 4,
              ),
              itemBuilder: (context, index) {
                if (index < firstWeekday) return const SizedBox.shrink();
                final dayNumber = index - firstWeekday + 1;
                final date = DateTime(
                  _focusedMonth.year,
                  _focusedMonth.month,
                  dayNumber,
                );
                final dateKey = DateFormat('yyyy-MM-dd').format(date);
                final isSelected = _selectedDates.contains(dateKey);
                final isToday = DateFormat('yyyy-MM-dd').format(DateTime.now()) == dateKey;

                return InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () {
                    setState(() {
                      if (isSelected) {
                        _selectedDates.remove(dateKey);
                      } else {
                        _selectedDates.add(dateKey);
                      }
                    });
                  },
                  child: Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected
                          ? theme.colorScheme.primary
                          : (isToday
                              ? theme.colorScheme.primaryContainer.withValues(alpha: 0.5)
                              : null),
                      border: isToday && !isSelected
                          ? Border.all(color: theme.colorScheme.primary)
                          : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected || isToday
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? theme.colorScheme.onPrimary
                            : (date.weekday == DateTime.sunday
                                ? Colors.redAccent
                                : (date.weekday == DateTime.saturday
                                    ? Colors.blueAccent
                                    : theme.colorScheme.onSurface)),
                      ),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 12),

            // Selection summary
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '선택된 날짜: 개',
                  style: TextStyle(
                    fontSize: 13,
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (_selectedDates.isNotEmpty)
                  TextButton(
                    onPressed: () => setState(() => _selectedDates.clear()),
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: const Text('초기화', style: TextStyle(fontSize: 12)),
                  ),
              ],
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('취소'),
        ),
        FilledButton(
          onPressed: _selectedDates.isEmpty
              ? null
              : () => Navigator.pop(context, _selectedDates),
          child: Text('완료 ()'),
        ),
      ],
    );
  }
}
