import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../core/constants.dart';
import '../../core/error_view.dart';
import '../../core/minute_ticker.dart';
import '../../core/screen_mode.dart';
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
    show
        MultiFabRow,
        GlobalQuickAddButton,
        fabAvoidingBottomInset,
        showAppSnackBar;
import '../rewards/rest_day_controller.dart';
import '../settings/settings_controller.dart';
import '../settings/settings_page.dart';
import 'dial_painter.dart';

part 'planner_dial.dart';

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
  late final MinuteTicker _ticker;

  @override
  void initState() {
    super.initState();
    _currentMinute = _minuteOfNow();
    _ticker = MinuteTicker(() {
      final minute = _minuteOfNow();
      if (minute != _currentMinute) {
        setState(() => _currentMinute = minute);
      }
    })..start();
  }

  int _minuteOfNow() {
    final override = widget.debugNowMinuteOfDay;
    if (override != null) return override;
    final now = TimeOfDay.now();
    return now.hour * 60 + now.minute;
  }

  @override
  void dispose() {
    _ticker.cancel();
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
    final isResting = isRestDayOn(
      ref.watch(restDaysProvider).value ?? const [],
    );

    return Scaffold(
      // 빠른메모 시트(모달, 별도 라우트)가 키보드와 함께 올라올 때 그 viewInsets가
      // 이 홈 Scaffold 본문까지 줄여 LayoutBuilder의 maxHeight가 작아지고 다이얼이
      // 축소되던 문제 방지 -- 홈엔 인라인 입력창이 없어 키보드 회피가 불필요하다.
      resizeToAvoidBottomInset: false,
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
          // "오늘은 쉬기": the whole live dashboard is dimmed and a calm rest
          // banner sits over it, so a rest day reads as visibly, deliberately
          // different (taps still pass through -- resting is a soft state, not
          // a lockout).
          Opacity(
            opacity: isResting ? 0.28 : 1.0,
            child:
                // Header, badges, dial, and the next-block countdown are ONE
                // vertically-centred group, balanced within the space above the
                // bottom quick-add FAB. Centring the whole group (rather than pinning
                // header to the top and countdown to the bottom) keeps both reading as
                // a calm cluster around the dial, and the LayoutBuilder sizing keeps
                // that balance on any screen height. Reserving the FAB inset at the
                // bottom guarantees nothing ever sits in the FAB's space.
                Padding(
                  // Compact (cover): the FABs are a short corner row, so reserve
                  // only enough to clear them -- the dashboard then uses the whole
                  // short screen down to just above the camera, instead of a big
                  // full-width FAB band.
                  padding: EdgeInsets.only(
                    bottom: isCompactLayout(context)
                        ? 56
                        : fabAvoidingBottomInset(context),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      // Compact screen (foldable cover / small phone): the 24h dial
                      // is too cramped to read, so show a dedicated compact
                      // dashboard (current/next block card + streak + checklist),
                      // no dial -- regardless of the dial/next-action toggle.
                      if (isCompactLayout(context)) {
                        return segmentsAsync.maybeWhen(
                          data: (segments) => _CompactHome(
                            segments: segments,
                            currentMinute: _currentMinute,
                            mitSegmentIds: mitSegmentIds,
                          ),
                          orElse: () =>
                              const Center(child: CircularProgressIndicator()),
                        );
                      }

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
                                padding: const EdgeInsets.symmetric(
                                  vertical: 24,
                                ),
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
                      // doesn't run edge-to-edge and crowd the texts). The gaps
                      // above/below it scale with the screen height — generous on a
                      // tall phone, tight on a short cover screen.
                      final vGap = (constraints.maxHeight * 0.09).clamp(
                        16.0,
                        56.0,
                      );
                      final dialSize = math
                          .min(
                            constraints.maxWidth * 0.9,
                            constraints.maxHeight - 200,
                          )
                          .clamp(140.0, constraints.maxWidth);
                      final content = Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          _HomeHeader(minuteOfDay: _currentMinute),
                          const SizedBox(height: 12),
                          const Wrap(
                            spacing: 12,
                            alignment: WrapAlignment.center,
                            children: [StreakBadge(), DailyChecklistBadge()],
                          ),
                          SizedBox(height: vGap),
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
                              loading: () => const Center(
                                child: CircularProgressIndicator(),
                              ),
                              error: errorView,
                            ),
                          ),
                          SizedBox(height: vGap),
                          segmentsAsync.maybeWhen(
                            data: (segments) => _NextBlockCountdown(
                              segments: segments,
                              currentMinute: _currentMinute,
                            ),
                            orElse: () => const SizedBox.shrink(),
                          ),
                        ],
                      );

                      // On a normal phone the cluster fits, so it's a plain static
                      // Center -- no scroll view, so it reads as a fixed backdrop
                      // (no scroll bounce/jank). Only on a short screen (foldable
                      // cover) does it fall back to scrolling to avoid overflow.
                      const fitsThreshold = 560.0;
                      if (constraints.maxHeight >= fitsThreshold) {
                        return Center(child: content);
                      }
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(child: content),
                        ),
                      );
                    },
                  ),
                ),
          ),
          if (isResting)
            const Positioned.fill(
              child: IgnorePointer(child: _RestDayBanner()),
            ),
          Positioned(
            right: 12,
            bottom:
                (isCompactLayout(context)
                    ? 56
                    : fabAvoidingBottomInset(context)) +
                4,
            child: _RestDayToggle(resting: isResting),
          ),
        ],
      ),
      floatingActionButton: isCompactLayout(context)
          // Compact: small buttons in a single horizontal row in the
          // bottom-left corner (a row, not a stack, so they take only one
          // FAB's height -- sitting just above the camera and freeing the most
          // vertical room).
          ? Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const GlobalQuickAddButton(small: true),
                const SizedBox(width: 12),
                Semantics(
                  label: '구간 추가',
                  child: FloatingActionButton.small(
                    heroTag: 'planner-add-segment',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => const SegmentFormPage(),
                      ),
                    ),
                    child: const Icon(Icons.add),
                  ),
                ),
              ],
            )
          : MultiFabRow(
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
      floatingActionButtonLocation: isCompactLayout(context)
          ? const CompactCornerFabLocation()
          : FloatingActionButtonLocation.centerFloat,
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

  // Centres when it fits, scrolls when it doesn't (e.g. a foldable cover
  // screen, or a two-line block name) instead of overflowing.
  Widget _scrollSafe(Widget child) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(child: child),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = findBlockStatus(segments, currentMinute);
    final segment = status.segment;

    if (segment == null) {
      return _scrollSafe(
        Padding(
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
    return _scrollSafe(
      Padding(
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

/// Dedicated compact home for a cover screen / small phone (see
/// [isCompactLayout]): no 24h dial and no block icon graphic (too cramped to
/// read at that size) -- a tight, text-first dashboard that fits the whole
/// thing on one short screen without scrolling: small date+greeting, the
/// current (or next) block's name + when, a small 시작 button, and the
/// streak/checklist counts. Tapping 시작 on the *current* block opens the live
/// Focus (same as the main screen's 지금 button); a future block opens it
/// pinned for review.
class _CompactHome extends StatelessWidget {
  const _CompactHome({
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

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _HomeHeader(minuteOfDay: currentMinute),
            const SizedBox(height: 16),
            if (segment == null)
              Text(
                segments.isEmpty
                    ? '아직 구간이 없어요\n+ 로 하루를 나눠보세요'
                    : '지금이나 다음 일정이 없어요\n편히 쉬어도 좋아요',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium,
              )
            else ...[
              if (mitSegmentIds.contains(segment.id)) ...[
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.star_rounded,
                      size: 15,
                      color: Colors.amber[600],
                    ),
                    const SizedBox(width: 4),
                    Text('오늘의 MIT', style: theme.textTheme.labelSmall),
                  ],
                ),
                const SizedBox(height: 4),
              ],
              Text(
                segment.name,
                style: theme.textTheme.titleLarge,
                textAlign: TextAlign.center,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                status.isCurrent
                    ? '지금'
                    : '다음 · ${TimeGeometry.formatMinute(segment.startMinute)}',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => status.isCurrent
                          ? const FocusPage()
                          : FocusPage.forBlock(segment),
                    ),
                  ),
                  child: const Text('시작'),
                ),
              ),
            ],
            const SizedBox(height: 16),
            const Wrap(
              spacing: 12,
              runSpacing: 4,
              alignment: WrapAlignment.center,
              children: [StreakBadge(), DailyChecklistBadge()],
            ),
          ],
        ),
      ),
    );
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

/// The calm overlay shown over the dimmed home on a rest day ("오늘은 쉬기").
class _RestDayBanner extends StatelessWidget {
  const _RestDayBanner();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.bedtime_rounded,
            size: 48,
            color: theme.colorScheme.primary,
          ),
          const SizedBox(height: 12),
          Text('오늘은 쉬는 날', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 6),
          Text(
            '푹 쉬어요. 알람은 내일 다시 울려요.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Bottom-right toggle for "오늘은 쉬기". Filled while resting (tap to resume),
/// tonal otherwise (tap to rest). Toggling reschedules alarms via app.dart's
/// _RestDayAlarmSync watching the same record.
class _RestDayToggle extends ConsumerWidget {
  const _RestDayToggle({required this.resting});

  final bool resting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    void toggle() {
      final next = !resting;
      unawaited(ref.read(restDayControllerProvider).setToday(next));
      showAppSnackBar(
        context,
        Text(next ? '오늘은 쉬어요 🌙 오늘 알람을 껐어요.' : '다시 시작해요. 오늘 알람을 다시 켰어요.'),
        duration: const Duration(seconds: 2),
      );
    }

    return Semantics(
      button: true,
      label: resting ? '쉬는 날 해제' : '오늘은 쉬기',
      child: resting
          ? FilledButton.icon(
              onPressed: toggle,
              icon: const Icon(Icons.bedtime_rounded, size: 18),
              label: const Text('쉬는 날'),
            )
          : FilledButton.tonalIcon(
              onPressed: toggle,
              icon: const Icon(Icons.bedtime_outlined, size: 18),
              label: const Text('오늘은 쉬기'),
            ),
    );
  }
}
