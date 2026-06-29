import '../models/achieved_day.dart';
import '../models/alarm_skip.dart';
import '../models/app_settings.dart';
import '../models/completion.dart';
import '../models/memo.dart';
import '../models/micro_step_progress.dart';
import '../models/mit.dart';
import '../models/segment.dart';

/// Storage abstraction for the whole app. Screens and controllers depend
/// only on this interface, never on the concrete storage backend — the app
/// runs on [FirestorePlannerRepository] (per-account cloud sync, with
/// Firestore's own on-device cache for offline use). Tests swap in an
/// in-memory fake behind the same contract.
abstract class PlannerRepository {
  // Segments (the app's single "block" entity: time range + checklist + alarm)
  Stream<List<Segment>> watchSegments();
  Future<void> upsertSegment(Segment s);
  Future<void> deleteSegment(String id);

  // Memos
  Stream<List<Memo>> watchMemos();
  Future<void> addMemo(Memo m);
  Future<void> updateMemo(Memo m);
  Future<void> deleteMemo(String id);

  // Completions (per block, per day)
  Stream<List<Completion>> watchCompletions();
  Future<void> setCompletion(Completion c);
  Future<void> removeCompletion(String dateKey, String segmentId);

  // Micro-step progress (per block, per day)
  Stream<List<MicroStepProgress>> watchMicroStepProgress();
  Future<void> saveMicroStepProgress(MicroStepProgress p);

  // Achieved days (streak source -- per day, write-once; see [AchievedDay])
  Stream<List<AchievedDay>> watchAchievedDays();
  Future<void> saveAchievedDay(AchievedDay d);

  // Alarm skips (per block, per day -- "오늘은 건너뛰기" on the alarm screen)
  Stream<List<AlarmSkip>> watchAlarmSkips();
  Future<void> saveAlarmSkip(AlarmSkip s);

  // MITs (per block, per day -- "오늘의 MIT" star toggle in 구간 관리)
  Stream<List<Mit>> watchMits();
  Future<void> saveMit(Mit m);
  Future<void> removeMit(String dateKey, String segmentId);

  // Settings
  Stream<AppSettings> watchSettings();
  Future<void> saveSettings(AppSettings s);
}
