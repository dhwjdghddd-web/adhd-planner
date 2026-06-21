import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../../data/today.dart';
import '../focus/focus_page.dart';
import '../memos/memo_inbox_page.dart';
import '../rewards/daily_checklist_badge.dart';
import '../rewards/streak_badge.dart';
import '../routines/routine_editor_page.dart';
import '../routines/routine_form_page.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_form_page.dart';
import '../memos/quick_add_button.dart' show showAppSnackBar, MultiFabRow, GlobalQuickAddButton;
import '../settings/settings_page.dart';
import 'dial_painter.dart';

/// Home screen: the 24h circular dial with segment arcs, routine markers,
/// and a current-time hand that advances roughly every minute.
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

  // Mirrors RoutineEditorPage's own + button: routines need a segment to
  // belong to, so nudge towards creating one first rather than opening a
  // form whose auto-derived segment dropdown would just show 구간 없음.
  void _openRoutineForm(BuildContext context) {
    final segments = ref.read(segmentsProvider).value ?? const <Segment>[];
    if (segments.isEmpty) {
      showAppSnackBar(context, const Text('먼저 구간을 만들어주세요.'));
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const RoutineFormPage()));
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final routinesAsync = ref.watch(routinesProvider);
    final postponements = ref.watch(routinePostponementsProvider).value ?? const [];
    final skips = ref.watch(routineSkipsProvider).value ?? const [];
    final completions = ref.watch(completionsProvider).value ?? const [];
    final completedRoutineIds = completedRoutineIdsOn(completions);

    return Scaffold(
      appBar: AppBar(
        title: const Text('오늘'),
        actions: [
          IconButton(
            icon: const Icon(Icons.checklist),
            tooltip: '루틴 관리',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const RoutineEditorPage()),
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
              data: (segments) => routinesAsync.when(
                data: (routines) {
                  final displayRoutines = applyTodaysPostponements(routines, postponements);
                  return _Dial(
                    segments: segments,
                    routines: routines,
                    displayRoutines: displayRoutines,
                    statusRoutines: excludeTodaysSkips(displayRoutines, skips),
                    currentMinute: _currentMinute,
                    completedRoutineIds: completedRoutineIds,
                  );
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('오류: $e')),
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
          label: '루틴 추가',
          child: FloatingActionButton(
            heroTag: 'planner-add-routine',
            onPressed: () => _openRoutineForm(context),
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
    required this.routines,
    required this.displayRoutines,
    required this.statusRoutines,
    required this.currentMinute,
    required this.completedRoutineIds,
  });

  // The permanent, never-postponed schedule -- only used to resolve a
  // tapped marker back to the real routine to edit (see _nearestRoutine).
  final List<Segment> segments;
  final List<Routine> routines;
  // Today's postponements overlaid on top of [routines] -- what's actually
  // drawn on the dial, so the marker position matches what alarms are
  // actually doing today. A 넘기기'd routine still keeps its marker here
  // (it's still on the permanent schedule, just skipped for today) --
  // [statusRoutines] is the one that excludes it from 지금/다음.
  final List<Routine> displayRoutines;
  // [displayRoutines] with today's 넘기기'd routines removed -- fed to
  // findRoutineStatus so the center summary's 지금/다음 agrees with
  // FocusPage about what's actually still in play today.
  final List<Routine> statusRoutines;
  final int currentMinute;
  // Routines with a Completion recorded for today -- drawn with a small
  // checkmark badge on their dial marker so "did I do this today" is
  // visible at a glance without opening Focus or the routine list.
  final Set<String> completedRoutineIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final weekday = DateTime.now().weekday;
    final status = findRoutineStatus(
      statusRoutines,
      currentMinute,
      weekday,
      completedRoutineIds: completedRoutineIds,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        // Extra breathing room so the east/west hour labels ("18시" etc.),
        // which now sit further out to clear the tick marks (see
        // DialPainter._paintTicks), still don't bleed past the screen edge
        // under larger accessibility text scales.
        final side = math.min(constraints.maxWidth, constraints.maxHeight) - 56;
        return Center(
          child: Semantics(
            // The markers themselves are painted, not focusable, so a screen
            // reader has no other way to learn what's on the dial. Read out
            // today's routines (time + title, in order) as part of the dial's
            // own label so the schedule is available without sight -- the
            // 오늘의 체크리스트 screen is the actionable counterpart.
            label: _dialSemanticsLabel(weekday),
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
                        routines: displayRoutines,
                        currentMinute: currentMinute,
                        tickColor: theme.colorScheme.onSurface,
                        labelStyle: theme.textTheme.labelSmall ??
                            const TextStyle(fontSize: 12, fontFamily: 'Pretendard'),
                        handColor: theme.colorScheme.primary,
                        brightness: Theme.of(context).brightness,
                        completedRoutineIds: completedRoutineIds,
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

  /// Spoken description of the dial: the current time, then today's routines
  /// in start-time order ("07:00 약 먹기, 12:30 점심" …), each tagged 완료 or
  /// 건너뜀 where that applies. Built from [displayRoutines] so the times match
  /// what's drawn (today's 미루기 included); 넘기기'd routines are still listed
  /// (marked 건너뜀) since they remain on the dial.
  String _dialSemanticsLabel(int weekday) {
    final todays = [
      for (final r in displayRoutines)
        if (r.occursOn(weekday)) r,
    ]..sort((a, b) => a.startMinute.compareTo(b.startMinute));

    final now = '현재 시각 ${TimeGeometry.formatMinute(currentMinute)}';
    if (todays.isEmpty) {
      return '오늘 원형 계획표, $now, 오늘 일정이 없어요';
    }

    final skippedIds = {
      for (final r in displayRoutines)
        if (!statusRoutines.any((s) => s.id == r.id)) r.id,
    };
    final items = todays.map((r) {
      final time = TimeGeometry.formatMinute(r.startMinute);
      final tag = completedRoutineIds.contains(r.id)
          ? ' 완료'
          : skippedIds.contains(r.id)
              ? ' 건너뜀'
              : '';
      return '$time ${r.title}$tag';
    }).join(', ');
    return '오늘 원형 계획표, $now. 오늘 일정: $items';
  }

  void _handleTap(BuildContext context, Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    final outerR = DialGeometry.outerRadius(side);
    final lanes = DialGeometry.assignLanes(segments);

    // 루틴 마커 hit-test: 마커 중심 ±(markerRadius+10) 이내.
    final tappedRoutine = _nearestRoutine(center, local, outerR, lanes);
    if (tappedRoutine != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => FocusPage.forRoutine(tappedRoutine)),
      );
      return;
    }

    // 구간 호(arc) hit-test: 탭 좌표가 해당 구간의 lane 반지름 위에 있고
    // 각도도 구간 범위 안에 있어야만 수정 화면을 연다.
    final tappedSegment = _segmentAtPoint(center, local, outerR, lanes);
    if (tappedSegment != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => SegmentFormPage(existing: tappedSegment)),
      );
    }
  }

  /// Finds the routine whose marker the tap landed closest to, within a
  /// small hit-test radius around the marker itself. Hit-tests against
  /// [displayRoutines] -- mirroring exactly how [DialPainter] positions
  /// markers, postponements included, so taps and drawing never disagree --
  /// then resolves the result back to its entry in [routines] before
  /// returning, since tapping a marker opens the edit form, which must
  /// show/save the routine's real permanent startMinute, not today's
  /// postponed display position.
  Routine? _nearestRoutine(
      Offset center, Offset tapPoint, double outerR, Map<String, int> lanes) {
    Routine? nearestDisplay;
    var bestDistance = double.infinity;
    const hitRadius = DialGeometry.routineMarkerRadius + 10;

    for (final routine in displayRoutines) {
      final lane = lanes[routine.segmentId] ?? 0;
      final radius = DialGeometry.laneRadius(outerR, lane);
      final point = TimeGeometry.pointOnCircle(center, radius, routine.startMinute);
      final distance = (tapPoint - point).distance;
      if (distance <= hitRadius && distance < bestDistance) {
        bestDistance = distance;
        nearestDisplay = routine;
      }
    }
    if (nearestDisplay == null) return null;
    for (final routine in routines) {
      if (routine.id == nearestDisplay.id) return routine;
    }
    return null;
  }

  /// 탭 좌표가 구간 호(arc) 위에 정확히 있는지 검사한다.
  ///
  /// 조건 두 가지를 모두 만족해야 구간을 반환한다:
  /// 1. 탭 지점의 중심 거리가 해당 구간 lane의 반지름 ±(ringThickness/2 + 여유 4px) 이내
  /// 2. 탭 지점의 각도(분 환산)가 구간 startMinute~endMinute 범위 안에 있음
  ///
  /// 두 조건 중 하나라도 벗어나면 null을 반환하므로, 구간 밖 빈 영역을 탭해도
  /// 수정 화면이 열리지 않는다.
  Segment? _segmentAtPoint(
      Offset center, Offset tapPoint, double outerR, Map<String, int> lanes) {
    final tapDist = (tapPoint - center).distance;
    const tolerance = DialGeometry.ringThickness / 2 + 4;

    for (final segment in segments) {
      final lane = lanes[segment.id] ?? 0;
      final laneR = DialGeometry.laneRadius(outerR, lane);

      // 반지름 거리 검사.
      if ((tapDist - laneR).abs() > tolerance) continue;

      // 각도(분) 검사: containsMinute로 wrap-around 처리.
      final minute = TimeGeometry.offsetToMinute(center, tapPoint);
      if (segment.containsMinute(minute)) return segment;
    }
    return null;
  }

}

class _CenterSummary extends StatelessWidget {
  const _CenterSummary({required this.status, required this.currentMinute});

  final RoutineStatus status;
  final int currentMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final routine = status.routine;

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
      // geometry), so it can't grow with the user's font-size setting the
      // way a scrolling list can. Clamp text growth so most of it still
      // scales a little, then FittedBox is a hard safety net — together
      // they guarantee this never overflows at 200%, even with a long
      // routine title.
      child: MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.3,
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(TimeGeometry.formatMinute(currentMinute), style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              if (routine == null)
                Text(
                  '오늘 일정이 없어요',
                  style: theme.textTheme.bodySmall,
                  textAlign: TextAlign.center,
                )
              else ...[
                Text(
                  status.isCurrent ? '지금: ${routine.title}' : '다음: ${routine.title}',
                  style: theme.textTheme.bodyMedium,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                // Only for "다음": absolute time, not a countdown -- a
                // routine that's already current has no length to count
                // down from (see Routine's doc comment for why), and an
                // upcoming one stays put either way until its own alarm
                // actually fires, so the exact remaining minutes were
                // never something to act on in the meantime.
                if (!status.isCurrent) ...[
                  const SizedBox(height: 4),
                  Text(
                    TimeGeometry.formatMinute(routine.startMinute),
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
