import 'dart:async';

import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/routine.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/repositories/planner_repository.dart';

/// In-memory [PlannerRepository] for widget tests — avoids real Hive disk
/// I/O so feature tests (STEP 4+) start fast and don't need setUp/tearDown
/// around a temp directory.
class FakePlannerRepository implements PlannerRepository {
  final Map<String, Segment> _segments = {};
  final Map<String, Routine> _routines = {};
  final Map<String, Memo> _memos = {};
  final Map<String, Completion> _completions = {};
  AppSettings _settings = const AppSettings.defaults();

  final _segmentsStream = _ReplayStream<List<Segment>>();
  final _routinesStream = _ReplayStream<List<Routine>>();
  final _memosStream = _ReplayStream<List<Memo>>();
  final _completionsStream = _ReplayStream<List<Completion>>();
  final _settingsStream = _ReplayStream<AppSettings>();

  FakePlannerRepository() {
    _segmentsStream.add(const []);
    _routinesStream.add(const []);
    _memosStream.add(const []);
    _completionsStream.add(const []);
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
  Stream<AppSettings> watchSettings() => _settingsStream.stream;

  @override
  Future<void> saveSettings(AppSettings s) async {
    _settings = s;
    _settingsStream.add(_settings);
  }
}

/// Broadcast stream that replays the latest value to new listeners,
/// mirroring the "yield current state immediately" behaviour of
/// [HivePlannerRepository]'s watch* streams.
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
