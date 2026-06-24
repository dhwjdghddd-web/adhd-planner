import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import '../segments/segment_icons.dart';
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
      // A faint concentric-ripple backdrop fills the vertical slack the dial
      // leaves above/below itself on tall screens, so the home screen reads as
      // intentional calm space rather than an empty void — the same PDF 10
      // motif as the Focus rest screen. The dial and badges sit on top of it.
      body: Stack(
        children: [
          const Positioned.fill(child: _AmbientBackdrop()),
          Column(
            children: [
              _HomeHeader(minuteOfDay: _currentMinute),
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
              segmentsAsync.maybeWhen(
                data: (segments) => _TodayTimelineStrip(
                  segments: segments,
                  currentMinute: _currentMinute,
                  completedSegmentIds: completedSegmentIds,
                ),
                orElse: () => const SizedBox.shrink(),
              ),
            ],
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
                onLongPressStart: (details) =>
                    _handleLongPress(context, details.localPosition, side),
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

  /// Long-pressing a block's arc opens its editor directly — a shortcut to the
  /// same form reachable from the 구간 관리 list, so a quick time/alarm/item
  /// tweak doesn't need a trip through that list. A short haptic confirms the
  /// press landed on a block (a plain tap, by contrast, opens Focus review).
  void _handleLongPress(BuildContext context, Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    final outerR = DialGeometry.outerRadius(side);
    final lanes = DialGeometry.assignLanes(segments);

    final pressedSegment = _segmentAtPoint(center, local, outerR, lanes);
    if (pressedSegment != null) {
      HapticFeedback.mediumImpact();
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SegmentFormPage(existing: pressedSegment)),
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

/// A very faint set of concentric circles with a soft central glow, painted
/// behind the whole home screen so the dial doesn't float in empty space. It is
/// purely decorative (no semantics, no interaction) and static — no animation —
/// so it stays calm and cheap. Tuned far fainter than the Focus rest screen's
/// rings since it sits under live content.
class _AmbientBackdrop extends StatelessWidget {
  const _AmbientBackdrop();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return IgnorePointer(
      child: CustomPaint(
        size: Size.infinite,
        painter: _AmbientBackdropPainter(
          primaryColor: theme.colorScheme.primary,
          outlineColor: theme.colorScheme.outline,
          isDark: theme.brightness == Brightness.dark,
        ),
      ),
    );
  }
}

class _AmbientBackdropPainter extends CustomPainter {
  const _AmbientBackdropPainter({
    required this.primaryColor,
    required this.outlineColor,
    required this.isDark,
  });

  final Color primaryColor;
  final Color outlineColor;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height * 0.46);
    final base = math.min(size.width, size.height);

    // Soft central glow so the middle of the screen reads as gently lit.
    final glowPaint = Paint()
      ..color = primaryColor.withValues(alpha: isDark ? 0.07 : 0.05)
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 60);
    canvas.drawCircle(center, base * 0.32, glowPaint);

    // A handful of faint rings rippling outward past the dial's edge.
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    for (final factor in const [0.34, 0.46, 0.58, 0.70]) {
      ringPaint.color = outlineColor.withValues(alpha: 0.05);
      canvas.drawCircle(center, base * factor, ringPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _AmbientBackdropPainter oldDelegate) {
    return oldDelegate.primaryColor != primaryColor ||
        oldDelegate.outlineColor != outlineColor ||
        oldDelegate.isDark != isDark;
  }
}

/// A calm date + time-of-day greeting above the dial, so the top of the home
/// screen reads as an intentional header rather than empty space. Rebuilds with
/// the page's minute ticker, so the greeting shifts 아침→오후→저녁→밤 over the day.
class _HomeHeader extends StatelessWidget {
  const _HomeHeader({required this.minuteOfDay});

  final int minuteOfDay;

  // 1=Mon..7=Sun (ISO-8601) → index 0..6.
  static const _weekdayLabels = ['월', '화', '수', '목', '금', '토', '일'];

  String _greeting(int hour) {
    if (hour >= 5 && hour < 11) return '좋은 아침이에요';
    if (hour >= 11 && hour < 17) return '좋은 오후예요';
    if (hour >= 17 && hour < 21) return '좋은 저녁이에요';
    return '편안한 밤이에요';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final now = DateTime.now();
    final dateLabel = '${now.month}월 ${now.day}일 (${_weekdayLabels[now.weekday - 1]})';
    final mutedColor = isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68);

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 16, 24, 0),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(dateLabel, style: theme.textTheme.labelMedium?.copyWith(color: mutedColor)),
          const SizedBox(height: 2),
          Text(
            _greeting(minuteOfDay ~/ 60),
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

/// A horizontal, time-ordered strip of today's blocks beneath the dial — a
/// glanceable overview plus shortcuts: tap a block to open it in Focus,
/// long-press to edit it (mirrors the dial's own tap/long-press). Fills the
/// band below the dial that would otherwise sit empty on tall screens.
class _TodayTimelineStrip extends StatelessWidget {
  const _TodayTimelineStrip({
    required this.segments,
    required this.currentMinute,
    required this.completedSegmentIds,
  });

  final List<Segment> segments;
  final int currentMinute;
  final Set<String> completedSegmentIds;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final ordered = [...segments]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    return SizedBox(
      height: 64,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        itemCount: ordered.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final s = ordered[i];
          final isCurrent = currentMinute >= s.startMinute && currentMinute < s.endMinute;
          return _TimelineChip(
            segment: s,
            isCurrent: isCurrent,
            isDone: completedSegmentIds.contains(s.id),
          );
        },
      ),
    );
  }
}

class _TimelineChip extends StatelessWidget {
  const _TimelineChip({
    required this.segment,
    required this.isCurrent,
    required this.isDone,
  });

  final Segment segment;
  final bool isCurrent;
  final bool isDone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final primary = theme.colorScheme.primary;
    final mutedColor = isDark ? const Color(0xFFA6B2BE) : const Color(0xFF525C68);

    return Semantics(
      button: true,
      label: '${TimeGeometry.formatMinute(segment.startMinute)} ${segment.name}'
          '${isCurrent ? ', 현재' : ''}${isDone ? ', 완료' : ''}, 눌러서 열기',
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => FocusPage.forBlock(segment)),
        ),
        onLongPress: () {
          HapticFeedback.mediumImpact();
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => SegmentFormPage(existing: segment)),
          );
        },
        child: Container(
          constraints: const BoxConstraints(maxWidth: 150),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(14),
            color: isCurrent ? primary.withValues(alpha: isDark ? 0.18 : 0.10) : AppTheme.surface3(context),
            border: Border.all(
              color: isCurrent ? primary.withValues(alpha: 0.6) : (isDark ? Colors.transparent : const Color(0xFFE4E9EF)),
              width: isCurrent ? 1.5 : 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                isDone ? Icons.check_circle : iconForKey(segment.iconKey),
                size: 16,
                color: isDone ? primary : (isCurrent ? primary : mutedColor),
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      TimeGeometry.formatMinute(segment.startMinute),
                      style: theme.textTheme.labelSmall?.copyWith(color: mutedColor),
                    ),
                    Text(
                      segment.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w500,
                        color: isDone ? mutedColor : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
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
