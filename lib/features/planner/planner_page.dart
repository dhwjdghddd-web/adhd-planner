import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/time_geometry.dart';
import '../../data/models/routine.dart';
import '../../data/models/segment.dart';
import '../../data/providers.dart';
import '../../data/routine_status.dart';
import '../focus/focus_page.dart';
import '../memos/memo_inbox_page.dart';
import '../rewards/streak_badge.dart';
import '../routines/routine_editor_page.dart';
import '../routines/routine_form_page.dart';
import '../segments/segment_editor_page.dart';
import '../segments/segment_form_page.dart';
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

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final segmentsAsync = ref.watch(segmentsProvider);
    final routinesAsync = ref.watch(routinesProvider);

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
        ],
      ),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: Center(child: StreakBadge()),
          ),
          Expanded(
            child: segmentsAsync.when(
              data: (segments) => routinesAsync.when(
                data: (routines) => _Dial(
                  segments: segments,
                  routines: routines,
                  currentMinute: _currentMinute,
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
    );
  }
}

class _Dial extends StatelessWidget {
  const _Dial({
    required this.segments,
    required this.routines,
    required this.currentMinute,
  });

  final List<Segment> segments;
  final List<Routine> routines;
  final int currentMinute;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final status = findRoutineStatus(routines, currentMinute, DateTime.now().weekday);

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
                        routines: routines,
                        currentMinute: currentMinute,
                        tickColor: theme.colorScheme.onSurface,
                        labelStyle: theme.textTheme.labelSmall ??
                            const TextStyle(fontSize: 11),
                        handColor: theme.colorScheme.error,
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
  /// small hit-test radius around the marker itself. Mirrors exactly how
  /// [DialPainter] positions markers so taps and drawing never disagree.
  Routine? _nearestRoutine(
      Offset center, Offset tapPoint, double outerR, Map<String, int> lanes) {
    Routine? nearest;
    var bestDistance = double.infinity;
    const hitRadius = DialGeometry.routineMarkerRadius + 10;

    for (final routine in routines) {
      final lane = lanes[routine.segmentId] ?? 0;
      final radius = DialGeometry.laneRadius(outerR, lane);
      final point = TimeGeometry.pointOnCircle(center, radius, routine.startMinute);
      final distance = (tapPoint - point).distance;
      if (distance <= hitRadius && distance < bestDistance) {
        bestDistance = distance;
        nearest = routine;
      }
    }
    return nearest;
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
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
            const SizedBox(height: 4),
            Text(
              status.isCurrent
                  ? '${status.remainingMinutes}분 남음'
                  : '${status.remainingMinutes}분 후 시작',
              style: theme.textTheme.bodySmall,
            ),
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
    );
  }
}
