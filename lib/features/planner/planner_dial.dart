part of 'planner_page.dart';

// The home screen's 24-hour circular dial and its faint decorative backdrop.
// Split out of planner_page.dart (which was ~1000 lines); still 'part of' the
// same library, so it shares the parent's imports and private scope.

class _Dial extends StatelessWidget {
  const _Dial({
    required this.segments,
    required this.currentMinute,
    required this.completedSegmentIds,
    required this.mitSegmentIds,
  });

  final List<Segment> segments;
  final int currentMinute;
  final Set<String> completedSegmentIds;
  final Set<String> mitSegmentIds;

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
                onTapUp: (details) =>
                    _handleTap(context, details.localPosition, side),
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
                        labelStyle:
                            theme.textTheme.labelSmall ??
                            const TextStyle(
                              fontSize: 12,
                              fontFamily: 'Pretendard',
                            ),
                        handColor: theme.colorScheme.primary,
                        brightness: Theme.of(context).brightness,
                        completedSegmentIds: completedSegmentIds,
                        mitSegmentIds: mitSegmentIds,
                      ),
                    ),
                    _CenterSummary(
                      status: status,
                      currentMinute: currentMinute,
                    ),
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
    final todays = [...segments]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    final now = '현재 시각 ${TimeGeometry.formatMinute(currentMinute)}';
    if (todays.isEmpty) {
      return '오늘 원형 계획표, $now, 오늘 일정이 없어요';
    }

    final items = todays
        .map((s) {
          final time = TimeGeometry.formatMinute(s.startMinute);
          final tag = completedSegmentIds.contains(s.id) ? ' 완료' : '';
          return '$time ${s.name}$tag';
        })
        .join(', ');
    return '오늘 원형 계획표, $now. 오늘 일정: $items';
  }

  void _handleTap(BuildContext context, Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    final outerR = DialGeometry.outerRadius(side);
    final lanes = DialGeometry.assignLanes(segments);

    // Tapping a block's arc opens it in Focus -- not its editor -- so a block
    // whose time has already passed can still have its "루틴" items ticked off
    // late. Editing a block (time/alarm/items) is done from the 구간 관리 list
    // instead. The CURRENT block opens the live Focus (const FocusPage(), with
    // remaining-time ring + timer) -- identical to the centre "지금" button --
    // rather than the pinned review mode, so both entry points to the block
    // that's happening right now land on the same screen. Past/future blocks
    // still open in review mode (forBlock), where "20분 남음" against the wall
    // clock would be meaningless.
    final tappedSegment = _segmentAtPoint(center, local, outerR, lanes);
    if (tappedSegment != null) {
      final currentId = findBlockStatus(segments, currentMinute).segment?.id;
      final isCurrent = tappedSegment.id == currentId;
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              isCurrent ? const FocusPage() : FocusPage.forBlock(tappedSegment),
        ),
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
        MaterialPageRoute(
          builder: (_) => SegmentFormPage(existing: pressedSegment),
        ),
      );
    }
  }

  /// The block whose arc the tap landed on: the tap's distance from centre must
  /// be within the block's lane radius (±half the ring thickness, plus a little
  /// slack) and its angle (converted to a minute) must fall inside the block's
  /// range. Both conditions must hold, so tapping empty space opens nothing.
  Segment? _segmentAtPoint(
    Offset center,
    Offset tapPoint,
    double outerR,
    Map<String, int> lanes,
  ) {
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
