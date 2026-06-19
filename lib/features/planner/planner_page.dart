import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../focus/focus_page.dart';
import '../memos/memo_inbox_page.dart';
import '../rewards/daily_checklist_badge.dart';
import '../rewards/streak_badge.dart';
import '../routines/routine_editor_page.dart';
import '../routines/routine_form_page.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_form_page.dart';
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('먼저 구간을 만들어주세요.')));
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
    final completions = ref.watch(completionsProvider).value ?? const [];
    final todayKey = DateFormat('yyyy-MM-dd').format(DateTime.now());
    final completedRoutineIds = {
      for (final c in completions)
        if (c.dateKey == todayKey) c.routineId,
    };

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
                data: (routines) => _Dial(
                  segments: segments,
                  routines: routines,
                  displayRoutines: applyTodaysPostponements(routines, postponements),
                  currentMinute: _currentMinute,
                  completedRoutineIds: completedRoutineIds,
                ),
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, st) => Center(child: Text('오류: $e')),
              ),
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (e, st) => Center(child: Text('오류: $e')),
            ),
          ),
        ],
      ),
      // Same shape/corner as the global quick-add FAB (bottom-left, see
      // app.dart) but mirrored to the opposite corner -- a direct shortcut
      // to adding a routine, instead of having to go through 루틴 관리 first.
      floatingActionButton: Semantics(
        label: '루틴 추가',
        child: FloatingActionButton(
          heroTag: 'planner-add-routine',
          onPressed: () => _openRoutineForm(context),
          child: const Icon(Icons.add),
        ),
      ),
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.segments,
    required this.routines,
    required this.displayRoutines,
    required this.currentMinute,
    required this.completedRoutineIds,
  });

  // The permanent, never-postponed schedule -- only used to resolve a
  // tapped marker back to the real routine to edit (see _nearestRoutine).
  final List<Segment> segments;
  final List<Routine> routines;
  // Today's postponements overlaid on top of [routines] -- what's actually
  // drawn on the dial and fed to findRoutineStatus, so the marker position
  // and the "지금/다음" summary always agree with what alarms are actually
  // doing today.
  final List<Routine> displayRoutines;
  final int currentMinute;
  // Routines with a Completion recorded for today -- drawn with a small
  // checkmark badge on their dial marker so "did I do this today" is
  // visible at a glance without opening Focus or the routine list.
  final Set<String> completedRoutineIds;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = findRoutineStatus(
      displayRoutines,
      currentMinute,
      DateTime.now().weekday,
      completedRoutineIds: completedRoutineIds,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final side = math.min(constraints.maxWidth, constraints.maxHeight) - 32;
        return Center(
          child: Semantics(
            label: '오늘 원형 계획표, 현재 시각 ${TimeGeometry.formatMinute(currentMinute)}',
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
                            const TextStyle(fontSize: 11),
                        handColor: theme.colorScheme.error,
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

  void _handleTap(BuildContext context, Offset local, double side) {
    final center = Offset(side / 2, side / 2);
    final outerR = DialGeometry.outerRadius(side);
    final lanes = DialGeometry.assignLanes(segments);

    final tappedRoutine = _nearestRoutine(center, local, outerR, lanes);
    if (tappedRoutine != null) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => RoutineFormPage(existing: tappedRoutine)),
      );
      return;
    }

    final minute = TimeGeometry.offsetToMinute(center, local);
    final tappedSegment = _nearestSegment(segments, minute);
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

  Segment? _nearestSegment(List<Segment> segments, int minute) {
    for (final segment in segments) {
      if (segment.containsMinute(minute)) return segment;
    }
    if (segments.isEmpty) return null;

    Segment? nearest;
    var bestDistance = TimeGeometry.minutesPerDay;
    for (final segment in segments) {
      final distance = math.min(
        _wrapDistance(minute, segment.startMinute),
        _wrapDistance(minute, segment.endMinute),
      );
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = segment;
      }
    }
    return nearest;
  }

  int _wrapDistance(int a, int b) {
    final forward = TimeGeometry.lengthMinutes(a, b);
    final backward = TimeGeometry.lengthMinutes(b, a);
    return math.min(forward, backward);
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

    return Container(
      width: 160,
      height: 160,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
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
              FilledButton.tonal(
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
