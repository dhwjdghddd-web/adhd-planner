import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/theme.dart';
import '../../core/time_geometry.dart';
import '../../data/block_status.dart';
import '../../data/models/app_settings.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/today.dart';
import '../checkin/checkin_page.dart';
import '../focus/focus_page.dart';
import '../memos/memo_inbox_page.dart';
import '../rewards/daily_checklist_badge.dart';
import '../rewards/streak_badge.dart';
import '../segments/brain_dump_page.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_form_page.dart';
import '../segments/segment_icons.dart';
import '../segments/segment_templates.dart';
import '../segments/segments_controller.dart';
import '../memos/quick_add_button.dart'
    show MultiFabRow, GlobalQuickAddButton, fabAvoidingBottomInset;
import '../settings/settings_controller.dart';
import '../settings/settings_page.dart';
import 'dial_painter.dart';

const _uuid = Uuid();

/// Home screen: the 24h circular dial with block arcs and a current-time hand
/// that advances roughly every minute. Tapping a block's arc opens it in Focus
/// (review mode) so its checklist can be caught up on; the centre summary shows
/// whichever block is current (or next). Editing a block is done from the
/// 구간 관리 list, not here.
class PlannerPage extends ConsumerStatefulWidget {
  const PlannerPage({super.key, @visibleForTesting this.debugNowMinuteOfDay});

  /// Test-only override for "now" (minute-of-day). When set, the live status
  /// reads this fixed value instead of the wall clock, so widget tests
  /// (e.g. T6's "다음 한 행동" view with a future block) don't break near day
  /// boundaries.
  final int? debugNowMinuteOfDay;

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
    final override = widget.debugNowMinuteOfDay;
    if (override != null) return override;
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
    final mits = ref.watch(mitsProvider).value ?? const [];
    final mitSegmentIds = mitBlockIdsOn(mits);
    final settings = ref.watch(settingsProvider).value;
    final homeViewMode = settings?.homeViewMode ?? HomeViewMode.dial;

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘'),
        actions: [
          // T6: toggles the whole home view in place (no route push) between
          // the dial and the minimal "다음 한 행동" screen -- shows the icon
          // for whichever view tapping it switches *to*, the same convention
          // a theme toggle uses. Remembered across launches via
          // AppSettings.homeViewMode rather than resetting to the dial every
          // cold start.
          IconButton(
            icon: Icon(
              homeViewMode == HomeViewMode.dial
                  ? Icons.bolt
                  : Icons.donut_large,
            ),
            tooltip: homeViewMode == HomeViewMode.dial
                ? '다음 한 행동 보기'
                : '다이얼 보기',
            onPressed: settings == null
                ? null
                : () => unawaited(
                    ref
                        .read(settingsControllerProvider)
                        .save(
                          settings.copyWith(
                            homeViewMode: homeViewMode == HomeViewMode.dial
                                ? HomeViewMode.nextAction
                                : HomeViewMode.dial,
                          ),
                        ),
                  ),
          ),
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
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const MemoInboxPage())),
          ),
          IconButton(
            icon: const Icon(Icons.mood_outlined),
            tooltip: '체크인',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const CheckinPage())),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: '설정',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsPage())),
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
          // Header, badges, dial, and the next-block countdown are ONE
          // vertically-centred group, balanced within the space above the
          // bottom quick-add FAB. Centring the whole group (rather than pinning
          // header to the top and countdown to the bottom) keeps both reading as
          // a calm cluster around the dial, and the LayoutBuilder sizing keeps
          // that balance on any screen height. Reserving the FAB inset at the
          // bottom guarantees nothing ever sits in the FAB's space.
          Padding(
            padding: EdgeInsets.only(bottom: fabAvoidingBottomInset(context)),
            child: LayoutBuilder(
              builder: (context, constraints) {
                // T6: dial, badges, and the countdown are all hidden in this
                // mode -- just the current/next block and a big start button
                // (or a calm empty message when there's neither).
                if (homeViewMode == HomeViewMode.nextAction) {
                  return segmentsAsync.maybeWhen(
                    data: (segments) => _NextActionView(
                      segments: segments,
                      currentMinute: _currentMinute,
                      mitSegmentIds: mitSegmentIds,
                    ),
                    orElse: () =>
                        const Center(child: CircularProgressIndicator()),
                  );
                }

                final isEmpty = segmentsAsync.value?.isEmpty ?? false;

                // Empty case: there's no dialSize-style computed height to
                // budget around (the starter chips' natural height isn't
                // capped the way the dial's square size is), so this is laid
                // out as a normal top-to-bottom Column with the content area
                // left free to scroll -- on a short screen it scrolls instead
                // of overflowing, rather than trying to force everything to
                // fit via mainAxisSize.min like the non-empty layout below.
                if (isEmpty) {
                  return Column(
                    children: [
                      const SizedBox(height: 8),
                      _HomeHeader(minuteOfDay: _currentMinute),
                      const SizedBox(height: 12),
                      const Wrap(
                        spacing: 12,
                        alignment: WrapAlignment.center,
                        children: [StreakBadge(), DailyChecklistBadge()],
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(
                                maxWidth: math.min(
                                  constraints.maxWidth * 0.9,
                                  420,
                                ),
                              ),
                              child: const _EmptyHomeStarter(),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                }

                // Dial is kept a little narrower than the full width (so it
                // doesn't run edge-to-edge and crowd the texts), with generous
                // gaps above/below so the header and countdown read as clearly
                // separated from it. Reserve covers header+badges+countdown+gaps.
                final dialSize = math
                    .min(
                      constraints.maxWidth * 0.9,
                      constraints.maxHeight - 260,
                    )
                    .clamp(180.0, constraints.maxWidth);
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _HomeHeader(minuteOfDay: _currentMinute),
                      const SizedBox(height: 12),
                      const Wrap(
                        spacing: 12,
                        alignment: WrapAlignment.center,
                        children: [StreakBadge(), DailyChecklistBadge()],
                      ),
                      const SizedBox(height: 56),
                      SizedBox(
                        width: dialSize,
                        height: dialSize,
                        child: segmentsAsync.when(
                          data: (segments) => _Dial(
                            segments: segments,
                            currentMinute: _currentMinute,
                            completedSegmentIds: completedSegmentIds,
                            mitSegmentIds: mitSegmentIds,
                          ),
                          loading: () =>
                              const Center(child: CircularProgressIndicator()),
                          error: (e, st) => Center(child: Text('오류: $e')),
                        ),
                      ),
                      const SizedBox(height: 56),
                      segmentsAsync.maybeWhen(
                        data: (segments) => _NextBlockCountdown(
                          segments: segments,
                          currentMinute: _currentMinute,
                        ),
                        orElse: () => const SizedBox.shrink(),
                      ),
                    ],
                  ),
                );
              },
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
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SegmentFormPage())),
            child: const Icon(Icons.add),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

/// Shown instead of the dial when there are no blocks yet at all -- a cold,
/// empty ring gives a brand-new user no hint of what to do, so this offers
/// two zero-effort ways in: tap one starter chip (adds exactly that one
/// block; the dial fills in immediately, replacing this) or list out
/// whatever's on your mind and let 브레인덤프 page suggest times for all of
/// it at once.
class _EmptyHomeStarter extends ConsumerWidget {
  const _EmptyHomeStarter();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mutedColor = theme.brightness == Brightness.dark
        ? const Color(0xFFA6B2BE)
        : const Color(0xFF525C68);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '아직 만든 구간이 없어요\n아래에서 하나 골라 시작해보세요',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(color: mutedColor),
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.center,
          children: [
            for (final template in kSegmentTemplates)
              ActionChip(
                avatar: Icon(
                  iconForKey(template.iconKey),
                  size: 18,
                  color: Color(template.colorValue),
                ),
                label: Text(template.name),
                onPressed: () => _addTemplate(ref, template),
              ),
          ],
        ),
        const SizedBox(height: 20),
        TextButton.icon(
          onPressed: () => Navigator.of(
            context,
          ).push(MaterialPageRoute(builder: (_) => const BrainDumpPage())),
          icon: const Icon(Icons.psychology_outlined),
          label: const Text('또는, 떠오르는 일들을 적어보기'),
        ),
      ],
    );
  }

  // Not awaited: the same offline-safe fire-and-forget pattern every other
  // save action in this app uses (see SegmentsController.upsert) -- the dial
  // reappearing (segments becomes non-empty) is itself the feedback.
  void _addTemplate(WidgetRef ref, SegmentTemplate template) {
    final segment = Segment(
      id: _uuid.v4(),
      name: template.name,
      colorValue: template.colorValue,
      iconKey: template.iconKey,
      startMinute: template.startMinute,
      endMinute: template.endMinute,
      order: 0,
    );
    unawaited(ref.read(segmentsControllerProvider).upsert(segment));
  }
}

/// T6's minimal "다음 한 행동" home view: hides the dial/badges/countdown
/// entirely and surfaces only whichever block [findBlockStatus] says is
/// current (or, failing that, next) -- one thing to look at, one button to
/// press. For someone too overwhelmed by the whole day to look at the dial
/// at all.
class _NextActionView extends StatelessWidget {
  const _NextActionView({
    required this.segments,
    required this.currentMinute,
    required this.mitSegmentIds,
  });

  final List<Segment> segments;
  final int currentMinute;
  final Set<String> mitSegmentIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = findBlockStatus(segments, currentMinute);
    final segment = status.segment;

    if (segment == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(
            '지금이나 다음 일정이 없어요\n편히 쉬어도 좋아요',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ),
      );
    }

    final avatarColor = segment.themeColor(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 48,
              backgroundColor: avatarColor,
              child: Icon(
                iconForKey(segment.iconKey),
                size: 40,
                color: onSegmentColor(avatarColor),
              ),
            ),
            const SizedBox(height: 20),
            if (mitSegmentIds.contains(segment.id)) ...[
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star, size: 16, color: Colors.amber[700]),
                  const SizedBox(width: 4),
                  Text('오늘의 MIT', style: theme.textTheme.labelMedium),
                ],
              ),
              const SizedBox(height: 4),
            ],
            Text(
              segment.name,
              style: theme.textTheme.headlineSmall,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 6),
            Text(
              status.isCurrent
                  ? '지금'
                  : '다음 · ${TimeGeometry.formatMinute(segment.startMinute)}',
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 36),
            SizedBox(
              width: 220,
              height: 64,
              child: FilledButton(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => FocusPage.forBlock(segment),
                  ),
                ),
                child: Text('시작', style: theme.textTheme.titleLarge),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

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
    final dateLabel =
        '${now.month}월 ${now.day}일 (${_weekdayLabels[now.weekday - 1]})';
    final mutedColor = isDark
        ? const Color(0xFFA6B2BE)
        : const Color(0xFF525C68);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            dateLabel,
            style: theme.textTheme.labelMedium?.copyWith(color: mutedColor),
          ),
          const SizedBox(height: 2),
          Text(
            _greeting(minuteOfDay ~/ 60),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// A calm one-line countdown to the next block's start, filling the band
/// between the dial and the bottom quick-add FAB. Hidden when no block is still
/// ahead today.
class _NextBlockCountdown extends StatelessWidget {
  const _NextBlockCountdown({
    required this.segments,
    required this.currentMinute,
  });

  final List<Segment> segments;
  final int currentMinute;

  @override
  Widget build(BuildContext context) {
    if (segments.isEmpty) return const SizedBox.shrink();
    final ordered = [...segments]
      ..sort((a, b) => a.startMinute.compareTo(b.startMinute));
    Segment? next;
    for (final s in ordered) {
      if (s.startMinute > currentMinute) {
        next = s;
        break;
      }
    }
    if (next == null) return const SizedBox.shrink();

    final remaining = next.startMinute - currentMinute;
    final h = remaining ~/ 60;
    final m = remaining % 60;
    final remLabel = h > 0 ? '$h시간 $m분' : '$m분';

    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final mutedColor = isDark
        ? const Color(0xFFA6B2BE)
        : const Color(0xFF525C68);

    return Semantics(
      label: '다음 구간 ${next.name}까지 $remLabel 남음',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.schedule, size: 16, color: mutedColor),
            const SizedBox(width: 6),
            Flexible(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: '다음 '),
                    TextSpan(
                      text: next.name,
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                    const TextSpan(text: '까지 '),
                    TextSpan(
                      text: remLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
                style: theme.textTheme.bodyMedium?.copyWith(color: mutedColor),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
          ],
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
        border: isDark
            ? null
            : Border.all(color: const Color(0xFFE4E9EF), width: 1),
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
              Text(
                TimeGeometry.formatMinute(currentMinute),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 6),
              if (segment == null)
                Text(
                  '오늘 일정이 없어요',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              else ...[
                Text(
                  status.isCurrent
                      ? '지금: ${segment.name}'
                      : '다음: ${segment.name}',
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
                onPressed: () => Navigator.of(
                  context,
                ).push(MaterialPageRoute(builder: (_) => const FocusPage())),
                child: const Text('지금'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
