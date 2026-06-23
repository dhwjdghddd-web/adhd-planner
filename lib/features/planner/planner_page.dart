import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/time_geometry.dart';
import '../../data/block_status.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../focus/focus_page.dart';
import '../memos/memo_inbox_page.dart';
import '../rewards/daily_checklist_badge.dart';
import '../rewards/streak_badge.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_form_page.dart';
import '../memos/quick_add_button.dart' show MultiFabRow, GlobalQuickAddButton;
import '../settings/settings_page.dart';
import 'dial_painter.dart';

/// Home screen: the 24h circular dial with block arcs and a current-time hand
/// that advances roughly every minute. Tapping a block's arc opens it in Focus
/// (review mode) so its checklist can be caught up on; the centre summary shows
/// whichever block is current (or next). Editing a block is done from the
/// 구간 관리 list, not here.
class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key});

  @override
  ConsumerState<PlannerPage> createState() => _PlannerPageState();
}

class _PlannerPageState extends ConsumerState<PlannerPage> {
  late int _currentMinute;
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _currentMinute = _minuteOfNow();
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      final minute = _minuteOfNow();
      if (minute != _currentMinute) {
        setState(() => _currentMinute = minute);
      }
    });
  }

  int _minuteOfNow() {
    final now = TimeOfDay.now();
    return now.hour * 60 + now.minute;
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final completions = ref.watch(completionsProvider).value ?? const [];
    final completedSegmentIds = completedBlockIdsOn(completions);

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.tune),
            tooltip: '구간 관리',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SegmentEditorPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.sticky_note_2_outlined),
            tooltip: '메모',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const MemoInboxPage()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsPage()),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(
              child: Wrap(
                spacing: 12,
                alignment: WrapAlignment.center,
                children: [StreakBadge(), DailyChecklistBadge()],
              ),
            ),
          ),
          Expanded(
            child: segmentsAsync.when(
              data: (segments) => _Dial(
                segments: segments,
                currentMinute: _currentMinute,
                completedSegmentIds: completedSegmentIds,
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('오류: $e')),
            ),
          ),
        ],
      ),
      floatingActionButton: MultiFabRow(
        left: const GlobalQuickAddButton(),
        right: Semantics(
          label: '구간 추가',
          child: FloatingActionButton(
            heroTag: 'planner-add-segment',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SegmentFormPage()),
            ),
            child: const Icon(Icons.add),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.segments,
    required this.currentMinute,
    required this.completedSegmentIds,
  });

  final List<Segment> segments;
  final int currentMinute;
  final Set<String> completedSegmentIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = findBlockStatus(segments, currentMinute);

    return LayoutBuilder(
      builder: (context, constraints) {
        // Extra breathing room so the east/west hour labels ("18시" etc.),
        // which sit further out to clear the tick marks, still don't bleed past
        // the screen edge under larger accessibility text scales.
        final side = math.min(constraints.maxWidth, constraints.maxHeight) - 56;
        return Center(
          child: Semantics(
            // The arcs are painted, not focusable, so a screen reader has no
            // other way to learn what's on the dial. Read out today's blocks
            // (time + name, in order) as part of the dial's own label.
            label: _dialSemanticsLabel(),
            child: SizedBox(
              width: side,
              height: side,
              child: GestureDetector(
                onTapUp: (details) => _handleTap(context, details.localPosition, side),
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    CustomPaint(
                      size: Size(side, side),
                      painter: DialPainter(
                        segments: segments,
                        currentMinute: currentMinute,
                        tickColor: theme.colorScheme.onSurface,
                        labelStyle: theme.textTheme.labelSmall ??
                            const TextStyle(fontSize: 12, fontFamily: 'Pretendard'),
                        handColor: theme.colorScheme.primary,
                        brightness: Theme.of(context).brightness,
                        completedSegmentIds: completedSegmentIds,
                      ),
                    ),
                    _CenterSummary(status: status, currentMinute: currentMinute),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Spoken description of the dial: the current time, then today's blocks in
  /// start-time order ("07:00 아침, 12:30 점심" …), each tagged 완료 where it
  /// applies.
  String _dialSemanticsLabel() {
    final todays = [...segments]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    final now = '현재 시각 ${TimeGeometry.formatMinute(currentMinute)}';
    if (todays.isEmpty) {
      return '오늘 원형 계획표, $now, 오늘 일정이 없어요';
    }

    final items = todays.map((s) {
      final time = TimeGeometry.formatMinute(s.startMinute);
      final tag = completedSegmentIds.contains(s.id) ? ' 완료' : '';
      return '$time ${s.name}$tag';
    }).join(', ');
    return '오늘 원형 계획표, $now. 오늘 일정: $items';
  }

  void _handleTap(BuildContext context, Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    final outerR = DialGeometry.outerRadius(side);
    final lanes = DialGeometry.assignLanes(segments);

    // Tapping a block's arc opens it in Focus (review mode) -- not its editor --
    // so a block whose time has already passed can still have its "루틴" items
    // ticked off late. Editing a block (time/alarm/items) is done from the
    // 구간 관리 list instead. Mirrors the old dial-marker → Focus review flow.
    final tappedSegment = _segmentAtPoint(center, local, outerR, lanes);
    if (tappedSegment != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FocusPage.forBlock(tappedSegment)),
      );
    }
  }

  /// The block whose arc the tap landed on: the tap's distance from centre must
  /// be within the block's lane radius (±half the ring thickness, plus a little
  /// slack) and its angle (converted to a minute) must fall inside the block's
  /// range. Both conditions must hold, so tapping empty space opens nothing.
  Segment? _segmentAtPoint(
      Offset center, Offset tapPoint, double outerR, Map<String, int> lanes) {
    final tapDist = (tapPoint - center).distance;
    const tolerance = DialGeometry.ringThickness / 2 + 4;

    for (final segment in segments) {
      final lane = lanes[segment.id] ?? 0;
      final laneR = DialGeometry.laneRadius(outerR, lane);
      if ((tapDist - laneR).abs() > tolerance) continue;
      final minute = TimeGeometry.offsetToMinute(center, tapPoint);
      if (segment.containsMinute(minute)) return segment;
    }
    return null;
  }
}

class _CenterSummary extends StatelessWidget {
  const _CenterSummary({required this.status, required this.currentMinute});

  final BlockStatus status;
  final int currentMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final segment = status.segment;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: 160,
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppTheme.surface3(context),
        border: isDark ? null : Border.all(color: const Color(0xFFE4E9EF), width: 1),
        boxShadow: isDark
            ? null
            : [
                BoxShadow(
                  color: const Color(0xFF141E32).withValues(alpha: 0.07),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
      ),
      // This circle has a fixed physical size (it sits inside the dial's own
      // geometry), so it can't grow with the user's font-size setting the way
      // a scrolling list can. Clamp text growth so most of it still scales a
      // little, then FittedBox is a hard safety net.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(TimeGeometry.formatMinute(currentMinute), style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              if (segment == null)
                Text(
                  '오늘 일정이 없어요',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              else ...[
                Text(
                  status.isCurrent ? '지금: ${segment.name}' : '다음: ${segment.name}',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                if (!status.isCurrent) ...[
                  const SizedBox(height: 4),
                  Text(
                    TimeGeometry.formatMinute(segment.startMinute),
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ],
              const SizedBox(height: 8),
              FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(builder: (_) => const FocusPage()),
                ),
                child: const Text('지금'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
