import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/screen_mode.dart';
import '../../data/models/checkin.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../memos/quick_add_button.dart';
import 'checkin_controller.dart';

enum CheckinViewMode { calendar, list, insights }

/// T8: daily & time-of-day mood and energy observation.
/// Supports 3 comprehensive views:
/// 1. [Calendar]: Monthly emoji mood map with daily detail cards.
/// 2. [List]: Chronological timeline grouped by date with time tags.
/// 3. [Insights]: Time-of-day distribution & day-of-week energy patterns.
class CheckinPage extends ConsumerStatefulWidget {
  const CheckinPage({super.key, this.autoOpenMoodDialog = false});

  final bool autoOpenMoodDialog;

  @override
  ConsumerState<CheckinPage> createState() => _CheckinPageState();
}

class _CheckinPageState extends ConsumerState<CheckinPage> {
  bool _autoOpened = false;
  CheckinViewMode _viewMode = CheckinViewMode.calendar;
  late DateTime _focusedMonth;
  late String _selectedDateKey;

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _focusedMonth = DateTime(now.year, now.month, 1);
    _selectedDateKey = dayKeyFor(now);
  }

  Future<void> _saveCheckin({
    String? id,
    required int mood,
    required int energy,
    String? note,
    DateTime? at,
    String? dateKey,
    String? createdAtIso,
  }) {
    return ref.read(checkinControllerProvider).save(
      id: id,
      mood: mood,
      energy: energy,
      note: note,
      at: at,
      dateKey: dateKey,
      createdAtIso: createdAtIso,
    );
  }

  Future<void> _openMoodDialog({Checkin? existing, DateTime? forDate}) {
    final targetDate = forDate ?? (existing != null ? existing.createdAt : DateTime.now());
    return showDialog(
      context: context,
      builder: (dialogContext) => Dialog(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: SingleChildScrollView(
            child: _CheckinForm(
              initialMood: existing?.mood,
              initialEnergy: existing?.energy,
              initialNote: existing?.note,
              buttonLabel: existing == null ? '저장' : '수정하기',
              title: existing == null ? '기분과 에너지를 기록해요' : '체크인 수정',
              onSubmit: (mood, energy, note) async {
                await _saveCheckin(
                  id: existing?.id,
                  mood: mood,
                  energy: energy,
                  note: note,
                  at: targetDate,
                  dateKey: existing?.dateKey ?? DateFormat('yyyy-MM-dd').format(targetDate),
                  createdAtIso: existing?.createdAtIso,
                );
                if (dialogContext.mounted) Navigator.of(dialogContext).pop();
              },
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final checkins = ref.watch(checkinsProvider).value ?? const [];
    final todayKey = dayKeyFor();

    // Find today's latest check-in for auto-open
    Checkin? todaysLatest;
    for (final c in checkins) {
      if (c.dateKey == todayKey) {
        if (todaysLatest == null || c.createdAt.isAfter(todaysLatest.createdAt)) {
          todaysLatest = c;
        }
      }
    }

    if (widget.autoOpenMoodDialog && !_autoOpened) {
      _autoOpened = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMoodDialog(existing: todaysLatest);
      });
    }

    final sortedCheckins = [...checkins]
      ..sort((a, b) => b.createdAtIso.compareTo(a.createdAtIso));

    return Scaffold(
      appBar: AppBar(
        title: const Text('체크인'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: SegmentedButton<CheckinViewMode>(
              segments: const [
                ButtonSegment(
                  value: CheckinViewMode.calendar,
                  icon: Icon(Icons.calendar_month_outlined, size: 18),
                  label: Text('달력'),
                ),
                ButtonSegment(
                  value: CheckinViewMode.list,
                  icon: Icon(Icons.list_alt, size: 18),
                  label: Text('목록'),
                ),
                ButtonSegment(
                  value: CheckinViewMode.insights,
                  icon: Icon(Icons.insights, size: 18),
                  label: Text('통계'),
                ),
              ],
              selected: {_viewMode},
              onSelectionChanged: (selected) {
                setState(() => _viewMode = selected.first);
              },
            ),
          ),
        ),
      ),
      body: Padding(
        padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 250),
          child: switch (_viewMode) {
            CheckinViewMode.calendar => _CalendarMoodView(
                checkins: sortedCheckins,
                focusedMonth: _focusedMonth,
                selectedDateKey: _selectedDateKey,
                onMonthChanged: (m) => setState(() => _focusedMonth = m),
                onDateSelected: (d) => setState(() => _selectedDateKey = d),
                onEdit: (c) => _openMoodDialog(existing: c),
                onAddForDate: (d) => _openMoodDialog(forDate: d),
                onDelete: (id) => ref.read(checkinControllerProvider).delete(id),
              ),
            CheckinViewMode.list => _TimelineListView(
                checkins: sortedCheckins,
                onEdit: (c) => _openMoodDialog(existing: c),
                onDelete: (id) => ref.read(checkinControllerProvider).delete(id),
              ),
            CheckinViewMode.insights => _InsightsPatternView(
                checkins: sortedCheckins,
              ),
          },
        ),
      ),
      floatingActionButton: isCompactLayout(context)
          ? compactCornerFabs(
              actions: [
                Semantics(
                  label: '기분 추가',
                  child: FloatingActionButton.small(
                    heroTag: 'checkin-add',
                    onPressed: () => _openMoodDialog(),
                    child: const Icon(Icons.add_reaction_outlined),
                  ),
                ),
              ],
            )
          : MultiFabRow(
              left: const GlobalQuickAddButton(),
              right: Semantics(
                label: '기분 추가',
                child: FloatingActionButton.extended(
                  onPressed: () => _openMoodDialog(),
                  icon: const Icon(Icons.add_reaction_outlined),
                  label: const Text('기록하기'),
                ),
              ),
            ),
      floatingActionButtonLocation: screenFabLocation(context),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 1. CALENDAR VIEW (월별 캘린더 뷰)
// ─────────────────────────────────────────────────────────────────────────────

class _CalendarMoodView extends StatelessWidget {
  const _CalendarMoodView({
    required this.checkins,
    required this.focusedMonth,
    required this.selectedDateKey,
    required this.onMonthChanged,
    required this.onDateSelected,
    required this.onEdit,
    required this.onAddForDate,
    required this.onDelete,
  });

  final List<Checkin> checkins;
  final DateTime focusedMonth;
  final String selectedDateKey;
  final ValueChanged<DateTime> onMonthChanged;
  final ValueChanged<String> onDateSelected;
  final ValueChanged<Checkin> onEdit;
  final ValueChanged<DateTime> onAddForDate;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final monthKey = DateFormat('yyyy-MM').format(focusedMonth);

    // Group checkins by dateKey
    final checkinsByDate = <String, List<Checkin>>{};
    for (final c in checkins) {
      checkinsByDate.putIfAbsent(c.dateKey, () => []).add(c);
    }

    // Month statistics
    final monthCheckins = checkins.where((c) => c.dateKey.startsWith(monthKey)).toList();
    final totalCount = monthCheckins.length;
    final avgMood = totalCount > 0
        ? (monthCheckins.map((c) => c.mood).reduce((a, b) => a + b) / totalCount)
        : 0.0;
    final avgEnergy = totalCount > 0
        ? (monthCheckins.map((c) => c.energy).reduce((a, b) => a + b) / totalCount)
        : 0.0;

    final selectedCheckins = checkinsByDate[selectedDateKey] ?? const [];
    final selectedDate = DateTime.tryParse(selectedDateKey) ?? DateTime.now();

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Month header & Navigation
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              IconButton(
                icon: const Icon(Icons.chevron_left),
                tooltip: '이전 달',
                onPressed: () {
                  onMonthChanged(DateTime(focusedMonth.year, focusedMonth.month - 1, 1));
                },
              ),
              Text(
                '${focusedMonth.year}년 ${focusedMonth.month}월',
                style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.chevron_right),
                tooltip: '다음 달',
                onPressed: () {
                  onMonthChanged(DateTime(focusedMonth.year, focusedMonth.month + 1, 1));
                },
              ),
            ],
          ),
          const SizedBox(height: 4),

          // Monthly summary badge card
          if (totalCount > 0)
            Card(
              elevation: 0,
              color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
              margin: const EdgeInsets.only(bottom: 12),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    _SummaryPill(
                      label: '기록 수',
                      value: '$totalCount회',
                      icon: Icons.edit_note,
                      color: theme.colorScheme.primary,
                    ),
                    _SummaryPill(
                      label: '평균 기분',
                      value: '${avgMood.toStringAsFixed(1)} / 5',
                      emoji: _MoodRow._emojis[(avgMood.round() - 1).clamp(0, 4)],
                    ),
                    _SummaryPill(
                      label: '평균 에너지',
                      value: '${avgEnergy.toStringAsFixed(1)} / 5',
                      icon: Icons.bolt,
                      color: Colors.amber[700]!,
                    ),
                  ],
                ),
              ),
            ),

          // Calendar Grid
          _CalendarGrid(
            month: focusedMonth,
            checkinsByDate: checkinsByDate,
            selectedDateKey: selectedDateKey,
            onSelectDate: onDateSelected,
          ),
          const SizedBox(height: 16),
          const Divider(),

          // Selected date detail section
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _formatDateWithWeekday(selectedDateKey),
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                ),
                TextButton.icon(
                  onPressed: () => onAddForDate(selectedDate),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('기록 추가'),
                ),
              ],
            ),
          ),

          if (selectedCheckins.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: Text(
                  '이 날의 체크인 기록이 없어요.\n우측 상단 버튼으로 기록을 추가해보세요.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            )
          else
            for (final c in selectedCheckins)
              _CheckinCard(
                checkin: c,
                onTap: () => onEdit(c),
                onDelete: () => onDelete(c.id),
              ),
        ],
      ),
    );
  }

  static String _formatDateWithWeekday(String dateKey) {
    try {
      final d = DateTime.parse(dateKey);
      final weekdays = ['월', '화', '수', '목', '금', '토', '일'];
      final today = dayKeyFor();
      final prefix = dateKey == today ? '오늘 · ' : '';
      return '$prefix${d.month}월 ${d.day}일 (${weekdays[d.weekday - 1]})';
    } catch (_) {
      return dateKey;
    }
  }
}

class _CalendarGrid extends StatelessWidget {
  const _CalendarGrid({
    required this.month,
    required this.checkinsByDate,
    required this.selectedDateKey,
    required this.onSelectDate,
  });

  final DateTime month;
  final Map<String, List<Checkin>> checkinsByDate;
  final String selectedDateKey;
  final ValueChanged<String> onSelectDate;

  static const _weekdays = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final firstDayOfMonth = DateTime(month.year, month.month, 1);
    final daysInMonth = DateTime(month.year, month.month + 1, 0).day;

    // ISO: 1=Mon .. 7=Sun
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

        // Grid rows
        for (var row = 0; row < totalCells / 7; row++)
          Row(
            children: [
              for (var col = 0; col < 7; col++) ...[
                () {
                  final cellIndex = row * 7 + col;
                  final dayNum = cellIndex - startingOffset + 1;
                  if (dayNum < 1 || dayNum > daysInMonth) {
                    return const Expanded(child: SizedBox(height: 52));
                  }

                  final date = DateTime(month.year, month.month, dayNum);
                  final dateKey = DateFormat('yyyy-MM-dd').format(date);
                  final isSelected = dateKey == selectedDateKey;
                  final isToday = dateKey == todayKey;
                  final dayCheckins = checkinsByDate[dateKey] ?? const [];

                  // Latest mood emoji for this date
                  final moodEmoji = dayCheckins.isNotEmpty
                      ? _MoodRow._emojis[dayCheckins.first.mood - 1]
                      : null;

                  return Expanded(
                    child: GestureDetector(
                      onTap: () => onSelectDate(dateKey),
                      child: Container(
                        height: 52,
                        margin: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? theme.colorScheme.primaryContainer
                              : isToday
                              ? theme.colorScheme.surfaceContainerHighest
                              : null,
                          borderRadius: BorderRadius.circular(10),
                          border: isToday && !isSelected
                              ? Border.all(color: theme.colorScheme.primary, width: 1.5)
                              : null,
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '$dayNum',
                              style: theme.textTheme.labelSmall?.copyWith(
                                fontWeight: isToday || isSelected ? FontWeight.bold : null,
                                color: isSelected
                                    ? theme.colorScheme.onPrimaryContainer
                                    : col >= 5
                                    ? theme.colorScheme.error
                                    : null,
                              ),
                            ),
                            if (moodEmoji != null) ...[
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Text(moodEmoji, style: const TextStyle(fontSize: 14)),
                                  if (dayCheckins.length > 1)
                                    Container(
                                      margin: const EdgeInsets.only(left: 2),
                                      width: 4,
                                      height: 4,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: theme.colorScheme.primary,
                                      ),
                                    ),
                                ],
                              ),
                            ] else ...[
                              const SizedBox(height: 16),
                            ],
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

// ─────────────────────────────────────────────────────────────────────────────
// 2. TIMELINE LIST VIEW (목록 뷰)
// ─────────────────────────────────────────────────────────────────────────────

class _TimelineListView extends StatelessWidget {
  const _TimelineListView({
    required this.checkins,
    required this.onEdit,
    required this.onDelete,
  });

  final List<Checkin> checkins;
  final ValueChanged<Checkin> onEdit;
  final ValueChanged<String> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final todayKey = dayKeyFor();

    if (checkins.isEmpty) {
      return Center(
        child: Text(
          '아직 체크인 기록이 없어요.\n우하단 버튼을 눌러 첫 기분을 기록해보세요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // Group by dateKey
    final grouped = <String, List<Checkin>>{};
    for (final c in checkins) {
      grouped.putIfAbsent(c.dateKey, () => []).add(c);
    }

    final dateKeys = grouped.keys.toList();

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: dateKeys.length,
      itemBuilder: (context, index) {
        final dKey = dateKeys[index];
        final items = grouped[dKey]!;
        final isToday = dKey == todayKey;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
              child: Text(
                _CalendarMoodView._formatDateWithWeekday(dKey),
                style: theme.textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: isToday ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            for (final c in items)
              _CheckinCard(
                checkin: c,
                showTime: true,
                onTap: () => onEdit(c),
                onDelete: () => onDelete(c.id),
              ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 3. INSIGHTS PATTERN VIEW (시간대별 & 요일별 통계 뷰)
// ─────────────────────────────────────────────────────────────────────────────

class _InsightsPatternView extends StatelessWidget {
  const _InsightsPatternView({required this.checkins});

  final List<Checkin> checkins;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (checkins.isEmpty) {
      return Center(
        child: Text(
          '체크인 데이터가 쌓이면\n시간대별 감정·에너지 패턴을 분석해드려요.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      );
    }

    // 1. Time-of-day bins:
    // Morning (05:00 - 11:00), Afternoon (11:00 - 17:00), Evening (17:00 - 21:00), Night (21:00 - 05:00)
    final morning = <Checkin>[];
    final afternoon = <Checkin>[];
    final evening = <Checkin>[];
    final night = <Checkin>[];

    for (final c in checkins) {
      final hour = c.createdAt.hour;
      if (hour >= 5 && hour < 11) {
        morning.add(c);
      } else if (hour >= 11 && hour < 17) {
        afternoon.add(c);
      } else if (hour >= 17 && hour < 21) {
        evening.add(c);
      } else {
        night.add(c);
      }
    }

    // 2. Day-of-week averages (1=Mon..7=Sun)
    final dayOfWeekBins = List.generate(7, (_) => <Checkin>[]);
    for (final c in checkins) {
      final weekday = c.createdAt.weekday - 1; // 0..6
      if (weekday >= 0 && weekday < 7) {
        dayOfWeekBins[weekday].add(c);
      }
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            '⏰ 시간대별 기분 & 에너지',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 4),
          Text(
            '하루 중 언제 기분과 활력이 높은지 확인해보세요.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
          const SizedBox(height: 12),

          _TimeBinCard(title: '🌅 아침 (05~11시)', items: morning),
          const SizedBox(height: 8),
          _TimeBinCard(title: '☀️ 낮 (11~17시)', items: afternoon),
          const SizedBox(height: 8),
          _TimeBinCard(title: '🌆 저녁 (17~21시)', items: evening),
          const SizedBox(height: 8),
          _TimeBinCard(title: '🌙 밤·심야 (21~05시)', items: night),
          const SizedBox(height: 24),

          Text(
            '📅 요일별 평균 패턴',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          _DayOfWeekChart(bins: dayOfWeekBins),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

class _TimeBinCard extends StatelessWidget {
  const _TimeBinCard({required this.title, required this.items});

  final String title;
  final List<Checkin> items;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = items.length;
    final avgMood = count > 0 ? items.map((c) => c.mood).reduce((a, b) => a + b) / count : 0.0;
    final avgEnergy = count > 0 ? items.map((c) => c.energy).reduce((a, b) => a + b) / count : 0.0;

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                Text(
                  count > 0 ? '$count회 기록' : '기록 없음',
                  style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            if (count > 0) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: _ScoreProgressBar(
                      label: '기분',
                      score: avgMood,
                      emoji: _MoodRow._emojis[(avgMood.round() - 1).clamp(0, 4)],
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: _ScoreProgressBar(
                      label: '에너지',
                      score: avgEnergy,
                      icon: Icons.bolt,
                      color: Colors.amber[700]!,
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScoreProgressBar extends StatelessWidget {
  const _ScoreProgressBar({
    required this.label,
    required this.score,
    this.emoji,
    this.icon,
    required this.color,
  });

  final String label;
  final double score;
  final String? emoji;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fraction = (score / 5.0).clamp(0.0, 1.0);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 14)),
            if (icon != null) Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(label, style: theme.textTheme.labelSmall),
            const Spacer(),
            Text(score.toStringAsFixed(1), style: theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 6,
            backgroundColor: theme.colorScheme.surfaceContainerHighest,
            valueColor: AlwaysStoppedAnimation<Color>(color),
          ),
        ),
      ],
    );
  }
}

class _DayOfWeekChart extends StatelessWidget {
  const _DayOfWeekChart({required this.bins});

  final List<List<Checkin>> bins;
  static const _labels = ['월', '화', '수', '목', '금', '토', '일'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (var i = 0; i < 7; i++) ...[
              () {
                final list = bins[i];
                final count = list.length;
                final avgMood = count > 0 ? list.map((c) => c.mood).reduce((a, b) => a + b) / count : 0.0;
                final heightFactor = (avgMood / 5.0).clamp(0.08, 1.0);

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (count > 0)
                      Text(
                        avgMood.toStringAsFixed(1),
                        style: theme.textTheme.labelSmall?.copyWith(fontSize: 10),
                      )
                    else
                      const Text('-', style: TextStyle(fontSize: 10, color: Colors.transparent)),
                    const SizedBox(height: 4),
                    Container(
                      width: 24,
                      height: 80 * heightFactor,
                      decoration: BoxDecoration(
                        color: count > 0 ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest,
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _labels[i],
                      style: theme.textTheme.labelSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: i >= 5 ? theme.colorScheme.error : null,
                      ),
                    ),
                  ],
                );
              }(),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// REUSABLE CARD & SUMMARY PILL
// ─────────────────────────────────────────────────────────────────────────────

class _SummaryPill extends StatelessWidget {
  const _SummaryPill({
    required this.label,
    required this.value,
    this.icon,
    this.emoji,
    this.color,
  });

  final String label;
  final String value;
  final IconData? icon;
  final String? emoji;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (emoji != null) Text(emoji!, style: const TextStyle(fontSize: 14)),
            if (icon != null) Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
          ],
        ),
        const SizedBox(height: 2),
        Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
      ],
    );
  }
}

class _CheckinCard extends StatelessWidget {
  const _CheckinCard({
    required this.checkin,
    this.showTime = true,
    required this.onTap,
    required this.onDelete,
  });

  final Checkin checkin;
  final bool showTime;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  static String _formatTime(DateTime dt) {
    final period = dt.hour < 12 ? '오전' : '오후';
    final hour12 = dt.hour == 0 ? 12 : (dt.hour > 12 ? dt.hour - 12 : dt.hour);
    final minStr = dt.minute.toString().padLeft(2, '0');
    return '$period $hour12:$minStr';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final note = checkin.note;
    final timeStr = _formatTime(checkin.createdAt);

    return Dismissible(
      key: ValueKey(checkin.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) => _confirmDelete(context),
      onDismissed: (_) => onDelete(),
      background: Container(
        color: theme.colorScheme.errorContainer,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: const Icon(Icons.delete_outline),
      ),
      child: Card(
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: ListTile(
          onTap: onTap,
          leading: Text(
            _MoodRow._emojis[(checkin.mood - 1).clamp(0, 4)],
            style: const TextStyle(fontSize: 28),
          ),
          title: Row(
            children: [
              Text('기분 ${checkin.mood}/5', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(width: 12),
              Icon(Icons.bolt, size: 16, color: Colors.amber[700]),
              Text('${checkin.energy}/5', style: theme.textTheme.bodyMedium),
              const Spacer(),
              if (showTime)
                Text(
                  timeStr,
                  style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                ),
            ],
          ),
          subtitle: note != null && note.isNotEmpty
              ? Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    note,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodySmall,
                  ),
                )
              : null,
          trailing: const Icon(Icons.edit_outlined, size: 16),
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('체크인 기록 삭제'),
        content: const Text('이 체크인 기록을 삭제할까요?'),
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
    return confirmed ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// 4. CHECKIN INPUT FORM DIALOG
// ─────────────────────────────────────────────────────────────────────────────

class _CheckinForm extends StatefulWidget {
  const _CheckinForm({
    this.initialMood,
    this.initialEnergy,
    this.initialNote,
    this.title = '오늘 기분은 어때요?',
    required this.buttonLabel,
    required this.onSubmit,
  });

  final int? initialMood;
  final int? initialEnergy;
  final String? initialNote;
  final String title;
  final String buttonLabel;
  final Future<void> Function(int mood, int energy, String? note) onSubmit;

  @override
  State<_CheckinForm> createState() => _CheckinFormState();
}

class _CheckinFormState extends State<_CheckinForm> {
  int? _mood;
  int? _energy;
  late final TextEditingController _noteController;

  @override
  void initState() {
    super.initState();
    _mood = widget.initialMood;
    _energy = widget.initialEnergy;
    _noteController = TextEditingController(text: widget.initialNote ?? '');
  }

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  bool get _canSubmit => _mood != null && _energy != null;

  Future<void> _submit() async {
    if (!_canSubmit) return;
    final note = _noteController.text.trim();
    await widget.onSubmit(_mood!, _energy!, note.isEmpty ? null : note);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(widget.title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 12),
        Text('기분은 어때요?', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        _MoodRow(selected: _mood, onSelect: (v) => setState(() => _mood = v)),
        const SizedBox(height: 20),
        Text('에너지는 어때요?', style: theme.textTheme.bodyMedium),
        const SizedBox(height: 8),
        _EnergyRow(
          selected: _energy,
          onSelect: (v) => setState(() => _energy = v),
        ),
        const SizedBox(height: 20),
        TextField(
          controller: _noteController,
          decoration: InputDecoration(
            labelText: '메모 (선택)',
            hintText: '어떤 생각이나 일들이 있었나요?',
            alignLabelWithHint: true,
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderSide: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          maxLines: 3,
          onChanged: (_) => setState(() {}),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          height: 48,
          child: FilledButton(
            onPressed: _canSubmit ? _submit : null,
            child: Text(widget.buttonLabel),
          ),
        ),
      ],
    );
  }
}

class _MoodRow extends StatelessWidget {
  const _MoodRow({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int> onSelect;

  static const _emojis = ['😞', '😕', '😐', '🙂', '😄'];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final level = i + 1;
        final isSelected = selected == level;
        return Semantics(
          label: '기분 $level단계',
          selected: isSelected,
          child: InkWell(
            onTap: () => onSelect(level),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isSelected ? theme.colorScheme.primaryContainer : null,
              ),
              child: Text(_emojis[i], style: const TextStyle(fontSize: 26)),
            ),
          ),
        );
      }),
    );
  }
}

class _EnergyRow extends StatelessWidget {
  const _EnergyRow({required this.selected, required this.onSelect});

  final int? selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: List.generate(5, (i) {
        final level = i + 1;
        final filled = selected != null && level <= selected!;
        return Semantics(
          label: '에너지 $level단계',
          selected: selected == level,
          child: InkWell(
            onTap: () => onSelect(level),
            customBorder: const CircleBorder(),
            child: Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: filled
                  ? null
                  : BoxDecoration(
                      shape: BoxShape.circle,
                      color: theme.colorScheme.surfaceContainerHighest,
                    ),
              child: Icon(
                Icons.bolt,
                size: 26,
                color: filled ? Colors.amber[700] : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        );
      }),
    );
  }
}
