import 'package:hive/hive.dart';

import '../../models/app_settings.dart';
import '../../models/completion.dart';
import '../../models/memo.dart';
import '../../models/micro_step_progress.dart';
import '../../models/routine.dart';
import '../../models/routine_postponement.dart';
import '../../models/segment.dart';
import '../planner_repository.dart';

/// Local-only [PlannerRepository] backed by Hive boxes. Entities are stored
/// as plain `Map<String, dynamic>` (via each model's toMap/fromMap) rather
/// than generated TypeAdapters — Hive natively supports Map/List/primitive
/// values, so no build_runner codegen step is needed for this shape.
class HivePlannerRepository implements PlannerRepository {
  static const segmentsBoxName = 'segments';
  static const routinesBoxName = 'routines';
  static const memosBoxName = 'memos';
  static const completionsBoxName = 'completions';
  static const microStepProgressBoxName = 'microStepProgress';
  static const routinePostponementsBoxName = 'routinePostponements';
  static const settingsBoxName = 'settings';
  static const _settingsKey = 'settings';

  final Box _segmentsBox;
  final Box _routinesBox;
  final Box _memosBox;
  final Box _completionsBox;
  final Box _microStepProgressBox;
  final Box _routinePostponementsBox;
  final Box _settingsBox;

  HivePlannerRepository._(
    this._segmentsBox,
    this._routinesBox,
    this._memosBox,
    this._completionsBox,
    this._microStepProgressBox,
    this._routinePostponementsBox,
    this._settingsBox,
  );

  static Future<HivePlannerRepository> open() async {
    final segments = await Hive.openBox(segmentsBoxName);
    final routines = await Hive.openBox(routinesBoxName);
    final memos = await Hive.openBox(memosBoxName);
    final completions = await Hive.openBox(completionsBoxName);
    final microStepProgress = await Hive.openBox(microStepProgressBoxName);
    final routinePostponements = await Hive.openBox(routinePostponementsBoxName);
    final settings = await Hive.openBox(settingsBoxName);
    return HivePlannerRepository._(
      segments,
      routines,
      memos,
      completions,
      microStepProgress,
      routinePostponements,
      settings,
    );
  }

  /// Closes all boxes. Used by tests to simulate an app restart, and can be
  /// called on app teardown if ever needed.
  Future<void> close() async {
    await _segmentsBox.close();
    await _routinesBox.close();
    await _memosBox.close();
    await _completionsBox.close();
    await _microStepProgressBox.close();
    await _routinePostponementsBox.close();
    await _settingsBox.close();
  }

  // Segments
  @override
  Stream<List<Segment>> watchSegments() => _watchAll(_segmentsBox, Segment.fromMap);

  @override
  Future<void> upsertSegment(Segment s) => _segmentsBox.put(s.id, s.toMap());

  @override
  Future<void> deleteSegment(String id) => _segmentsBox.delete(id);

  // Routines
  @override
  Stream<List<Routine>> watchRoutines() => _watchAll(_routinesBox, Routine.fromMap);

  @override
  Future<void> upsertRoutine(Routine r) => _routinesBox.put(r.id, r.toMap());

  @override
  Future<void> deleteRoutine(String id) => _routinesBox.delete(id);

  // Memos
  @override
  Stream<List<Memo>> watchMemos() => _watchAll(_memosBox, Memo.fromMap);

  @override
  Future<void> addMemo(Memo m) => _memosBox.put(m.id, m.toMap());

  @override
  Future<void> updateMemo(Memo m) => _memosBox.put(m.id, m.toMap());

  @override
  Future<void> deleteMemo(String id) => _memosBox.delete(id);

  // Completions
  @override
  Stream<List<Completion>> watchCompletions() =>
      _watchAll(_completionsBox, Completion.fromMap);

  @override
  Future<void> setCompletion(Completion c) => _completionsBox.put(c.id, c.toMap());

  @override
  Future<void> removeCompletion(String dateKey, String routineId) =>
      _completionsBox.delete(Completion.keyFor(dateKey, routineId));

  // Micro-step progress
  @override
  Stream<List<MicroStepProgress>> watchMicroStepProgress() =>
      _watchAll(_microStepProgressBox, MicroStepProgress.fromMap);

  @override
  Future<void> saveMicroStepProgress(MicroStepProgress p) =>
      _microStepProgressBox.put(p.id, p.toMap());

  // Routine postponements
  @override
  Stream<List<RoutinePostponement>> watchRoutinePostponements() =>
      _watchAll(_routinePostponementsBox, RoutinePostponement.fromMap);

  @override
  Future<void> saveRoutinePostponement(RoutinePostponement p) =>
      _routinePostponementsBox.put(p.id, p.toMap());

  // Settings
  @override
  Stream<AppSettings> watchSettings() async* {
    yield _readSettings();
    yield* _settingsBox.watch(key: _settingsKey).map((_) => _readSettings());
  }

  @override
  Future<void> saveSettings(AppSettings s) => _settingsBox.put(_settingsKey, s.toMap());

  AppSettings _readSettings() {
    final raw = _settingsBox.get(_settingsKey);
    if (raw == null) return const AppSettings.defaults();
    return AppSettings.fromMap(Map<String, dynamic>.from(raw as Map));
  }

  static Stream<List<T>> _watchAll<T>(
    Box box,
    T Function(Map<String, dynamic>) fromMap,
  ) async* {
    yield _allValues(box, fromMap);
    yield* box.watch().map((_) => _allValues(box, fromMap));
  }

  static List<T> _allValues<T>(
    Box box,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    return box.values
        .map((v) => fromMap(Map<String, dynamic>.from(v as Map)))
        .toList();
  }
}
