import 'package:adhd_planner/data/models/achieved_day.dart';
import 'package:adhd_planner/data/models/alarm_skip.dart';
import 'package:adhd_planner/data/models/app_settings.dart';
import 'package:adhd_planner/data/models/checkin.dart';
import 'package:adhd_planner/data/models/completion.dart';
import 'package:adhd_planner/data/models/memo.dart';
import 'package:adhd_planner/data/models/micro_step_move.dart';
import 'package:adhd_planner/data/models/micro_step_progress.dart';
import 'package:adhd_planner/data/models/mit.dart';
import 'package:adhd_planner/data/models/rest_day.dart';
import 'package:adhd_planner/data/models/segment.dart';
import 'package:adhd_planner/data/repositories/planner_repository.dart';

/// A [PlannerRepository] that forwards every call to [inner]. Test doubles that
/// only need to tweak a method or two (e.g. delay one stream to exercise a
/// loading state) extend this and override just those -- so the forwarding
/// boilerplate lives in ONE place instead of being copy-pasted (and silently
/// going out of sync) in every decorator when the interface gains a method.
///
/// Dart has no language-level "delegate all to inner", and `noSuchMethod` can't
/// re-dispatch an [Invocation] onto another object without mirrors (unavailable
/// in Flutter), so the forwarding is explicit -- but it's written once here.
abstract class ForwardingPlannerRepository implements PlannerRepository {
  PlannerRepository get inner;

  @override
  Stream<List<Segment>> watchSegments() => inner.watchSegments();
  @override
  Future<void> upsertSegment(Segment s) => inner.upsertSegment(s);
  @override
  Future<void> deleteSegment(String id) => inner.deleteSegment(id);

  @override
  Stream<List<Memo>> watchMemos() => inner.watchMemos();
  @override
  Future<void> addMemo(Memo m) => inner.addMemo(m);
  @override
  Future<void> updateMemo(Memo m) => inner.updateMemo(m);
  @override
  Future<void> deleteMemo(String id) => inner.deleteMemo(id);

  @override
  Stream<List<Completion>> watchCompletions() => inner.watchCompletions();
  @override
  Future<void> setCompletion(Completion c) => inner.setCompletion(c);
  @override
  Future<void> removeCompletion(String dateKey, String segmentId) =>
      inner.removeCompletion(dateKey, segmentId);

  @override
  Stream<List<MicroStepProgress>> watchMicroStepProgress() =>
      inner.watchMicroStepProgress();
  @override
  Future<void> saveMicroStepProgress(MicroStepProgress p) =>
      inner.saveMicroStepProgress(p);

  @override
  Stream<List<AchievedDay>> watchAchievedDays() => inner.watchAchievedDays();
  @override
  Future<void> saveAchievedDay(AchievedDay d) => inner.saveAchievedDay(d);

  @override
  Stream<List<AlarmSkip>> watchAlarmSkips() => inner.watchAlarmSkips();
  @override
  Future<void> saveAlarmSkip(AlarmSkip s) => inner.saveAlarmSkip(s);

  @override
  Stream<List<Mit>> watchMits() => inner.watchMits();
  @override
  Future<void> saveMit(Mit m) => inner.saveMit(m);
  @override
  Future<void> removeMit(String dateKey, String segmentId) =>
      inner.removeMit(dateKey, segmentId);

  @override
  Stream<List<Checkin>> watchCheckins() => inner.watchCheckins();
  @override
  Future<void> saveCheckin(Checkin c) => inner.saveCheckin(c);
  @override
  Future<void> removeCheckin(String dateKey) => inner.removeCheckin(dateKey);

  @override
  Stream<List<MicroStepMove>> watchMicroStepMoves() =>
      inner.watchMicroStepMoves();
  @override
  Future<void> saveMicroStepMove(MicroStepMove m) => inner.saveMicroStepMove(m);
  @override
  Future<void> removeMicroStepMove(String homeSegmentId, int stepIndex) =>
      inner.removeMicroStepMove(homeSegmentId, stepIndex);

  @override
  Stream<List<RestDay>> watchRestDays() => inner.watchRestDays();
  @override
  Future<void> saveRestDay(RestDay r) => inner.saveRestDay(r);
  @override
  Future<void> removeRestDay(String dateKey) => inner.removeRestDay(dateKey);

  @override
  Stream<AppSettings> watchSettings() => inner.watchSettings();
  @override
  Future<void> saveSettings(AppSettings s) => inner.saveSettings(s);

  @override
  Future<void> deleteAllData() => inner.deleteAllData();
}
