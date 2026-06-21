import 'dart:async';

import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/routine_postponement.dart';
import 'package:adhd_planner/data/models/routine_skip.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/repositories/planner_repository.dart';

/// In-memory [PlannerRepository] for widget tests — avoids any real disk or
/// network I/O so feature tests start fast and don't need setUp/tearDown
/// around a temp directory or a Firestore emulator.
class FakePlannerRepository implements PlannerRepository {
  final Map<String, Segment> _segments = {};
  final Map<String, Routine> _routines = {};
  final Map<String, Memo> _memos = {};
  final Map<String, Completion> _completions = {};
  final Map<String, MicroStepProgress> _microStepProgress = {};
  final Map<String, RoutinePostponement> _routinePostponements = {};
  final Map<String, RoutineSkip> _routineSkips = {};
  final Map<String, AchievedDay> _achievedDays = {};
  AppSettings _settings = const AppSettings.defaults();

  final _segmentsStream = _ReplayStream<List<Segment>>();
  final _routinesStream = _ReplayStream<List<Routine>>();
  final _memosStream = _ReplayStream<List<Memo>>();
  final _completionsStream = _ReplayStream<List<Completion>>();
  final _microStepProgressStream = _ReplayStream<List<MicroStepProgress>>();
  final _routinePostponementsStream = _ReplayStream<List<RoutinePostponement>>();
  final _routineSkipsStream = _ReplayStream<List<RoutineSkip>>();
  final _achievedDaysStream = _ReplayStream<List<AchievedDay>>();
  final _settingsStream = _ReplayStream<AppSettings>();

  FakePlannerRepository() {
    _segmentsStream.add(const []);
    _routinesStream.add(const []);
    _memosStream.add(const []);
    _completionsStream.add(const []);
    _microStepProgressStream.add(const []);
    _routinePostponementsStream.add(const []);
    _routineSkipsStream.add(const []);
    _achievedDaysStream.add(const []);
    _settingsStream.add(_settings);
  }

  @override
  Stream<List<Segment>> watchSegments() => _segmentsStream.stream;

  @override
  Future<void> upsertSegment(Segment s) async {
    _segments[s.id] = s;
    _segmentsStream.add(_segments.values.toList());
  }

  @override
  Future<void> deleteSegment(String id) async {
    _segments.remove(id);
    _segmentsStream.add(_segments.values.toList());
  }

  @override
  Stream<List<Routine>> watchRoutines() => _routinesStream.stream;

  @override
  Future<void> upsertRoutine(Routine r) async {
    _routines[r.id] = r;
    _routinesStream.add(_routines.values.toList());
  }

  @override
  Future<void> deleteRoutine(String id) async {
    _routines.remove(id);
    _routinesStream.add(_routines.values.toList());
  }

  @override
  Stream<List<Memo>> watchMemos() => _memosStream.stream;

  @override
  Future<void> addMemo(Memo m) async {
    _memos[m.id] = m;
    _memosStream.add(_memos.values.toList());
  }

  @override
  Future<void> updateMemo(Memo m) async {
    _memos[m.id] = m;
    _memosStream.add(_memos.values.toList());
  }

  @override
  Future<void> deleteMemo(String id) async {
    _memos.remove(id);
    _memosStream.add(_memos.values.toList());
  }

  @override
  Stream<List<Completion>> watchCompletions() => _completionsStream.stream;

  @override
  Future<void> setCompletion(Completion c) async {
    _completions[c.id] = c;
    _completionsStream.add(_completions.values.toList());
  }

  @override
  Future<void> removeCompletion(String dateKey, String routineId) async {
    _completions.remove(Completion.keyFor(dateKey, routineId));
    _completionsStream.add(_completions.values.toList());
  }

  @override
  Stream<List<MicroStepProgress>> watchMicroStepProgress() => _microStepProgressStream.stream;

  @override
  Future<void> saveMicroStepProgress(MicroStepProgress p) async {
    _microStepProgress[p.id] = p;
    _microStepProgressStream.add(_microStepProgress.values.toList());
  }

  @override
  Stream<List<RoutinePostponement>> watchRoutinePostponements() =>
      _routinePostponementsStream.stream;

  @override
  Future<void> saveRoutinePostponement(RoutinePostponement p) async {
    _routinePostponements[p.id] = p;
    _routinePostponementsStream.add(_routinePostponements.values.toList());
  }

  @override
  Stream<List<RoutineSkip>> watchRoutineSkips() => _routineSkipsStream.stream;

  @override
  Future<void> saveRoutineSkip(RoutineSkip s) async {
    _routineSkips[s.id] = s;
    _routineSkipsStream.add(_routineSkips.values.toList());
  }

  @override
  Stream<List<AchievedDay>> watchAchievedDays() => _achievedDaysStream.stream;

  @override
  Future<void> saveAchievedDay(AchievedDay d) async {
    _achievedDays[d.id] = d;
    _achievedDaysStream.add(_achievedDays.values.toList());
  }

  @override
  Stream<AppSettings> watchSettings() => _settingsStream.stream;

  @override
  Future<void> saveSettings(AppSettings s) async {
    _settings = s;
    _settingsStream.add(_settings);
  }
}

/// Broadcast stream that replays the latest value to new listeners,
/// mirroring the "yield current state immediately" behaviour of a real
/// repository's watch* streams (Firestore snapshots emit the current
/// state right away on subscribe).
class _ReplayStream<T> {
  final _controller = StreamController<T>.broadcast();
  T? _latest;
  bool _hasValue = false;

  Stream<T> get stream async* {
    if (_hasValue) yield _latest as T;
    yield* _controller.stream;
  }

  void add(T value) {
    _latest = value;
    _hasValue = true;
    _controller.add(value);
  }
}
