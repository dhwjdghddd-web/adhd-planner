import '../models/app_settings.dart';
import '../models/completion.dart';
import '../models/memo.dart';
import '../models/micro_step_progress.dart';
import '../models/routine.dart';
import '../models/routine_postponement.dart';
import '../models/routine_skip.dart';
import '../models/segment.dart';

/// Storage abstraction for the whole app. Screens and controllers depend
/// only on this interface, never on the concrete storage backend — STEP 3
/// ships [HivePlannerRepository] (local-only, no account needed) and STEP 9
/// swaps in a Firestore-backed implementation behind the same contract.
abstract class PlannerRepository {
  // Segments
  Stream<List<Segment>> watchSegments();
  Future<void> upsertSegment(Segment s);
  Future<void> deleteSegment(String id);

  // Routines
  Stream<List<Routine>> watchRoutines();
  Future<void> upsertRoutine(Routine r);
  Future<void> deleteRoutine(String id);

  // Memos
  Stream<List<Memo>> watchMemos();
  Future<void> addMemo(Memo m);
  Future<void> updateMemo(Memo m);
  Future<void> deleteMemo(String id);

  // Completions
  Stream<List<Completion>> watchCompletions();
  Future<void> setCompletion(Completion c);
  Future<void> removeCompletion(String dateKey, String routineId);

  // Micro-step progress (per routine, per day)
  Stream<List<MicroStepProgress>> watchMicroStepProgress();
  Future<void> saveMicroStepProgress(MicroStepProgress p);

  // Routine postponements ("미루기" -- per routine, per day)
  Stream<List<RoutinePostponement>> watchRoutinePostponements();
  Future<void> saveRoutinePostponement(RoutinePostponement p);

  // Routine skips ("넘기기" -- per routine, per day)
  Stream<List<RoutineSkip>> watchRoutineSkips();
  Future<void> saveRoutineSkip(RoutineSkip s);

  // Settings
  Stream<AppSettings> watchSettings();
  Future<void> saveSettings(AppSettings s);
}
