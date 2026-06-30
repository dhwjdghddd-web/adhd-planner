import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:intl/intl.dart';

import '../../models/achieved_day.dart';
import '../../models/alarm_skip.dart';
import '../../models/app_settings.dart';
import '../../models/checkin.dart';
import '../../models/completion.dart';
import '../../models/memo.dart';
import '../../models/micro_step_progress.dart';
import '../../models/mit.dart';
import '../../models/segment.dart';
import '../planner_repository.dart';

/// Firestore-backed [PlannerRepository] for the signed-in user — the only
/// concrete backend the app runs on. Every model has a plain `toMap`/
/// `fromMap`, so this is a straight read/write mapping — no new serialization
/// logic needed. Data lives at `users/{uid}/{segments|routines|memos|
/// completions}`; the `users/{uid}` document itself holds [AppSettings]
/// since there's only ever one per user.
class FirestorePlannerRepository implements PlannerRepository {
  FirestorePlannerRepository(this.uid, {FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  final String uid;
  final FirebaseFirestore _firestore;

  DocumentReference<Map<String, dynamic>> get _userDoc =>
      _firestore.collection('users').doc(uid);

  CollectionReference<Map<String, dynamic>> _collection(String name) =>
      _userDoc.collection(name);

  // Segments
  @override
  Stream<List<Segment>> watchSegments() =>
      _watchAll('segments', Segment.fromMap);

  @override
  Future<void> upsertSegment(Segment s) =>
      _collection('segments').doc(s.id).set(s.toMap());

  @override
  Future<void> deleteSegment(String id) =>
      _collection('segments').doc(id).delete();

  // Memos
  @override
  Stream<List<Memo>> watchMemos() => _watchAll('memos', Memo.fromMap);

  @override
  Future<void> addMemo(Memo m) => _collection('memos').doc(m.id).set(m.toMap());

  @override
  Future<void> updateMemo(Memo m) =>
      _collection('memos').doc(m.id).set(m.toMap());

  @override
  Future<void> deleteMemo(String id) => _collection('memos').doc(id).delete();

  // Completions
  //
  // Bounded to a recent window rather than _watchAll: these grow by one doc
  // per routine per day forever, but every reader only ever needs today (the
  // dial/Focus/checklist) or recent history (the achievement backfill that
  // seeds AchievedDay). Once a past day is banked as an AchievedDay it's read
  // from there, never recomputed from completions -- so an old completion
  // outside this window is dead weight that would otherwise be re-streamed on
  // every app start (and billed as a Firestore read). dateKey is a sortable
  // "yyyy-MM-dd" string, so a single-field range query needs no index.
  @override
  Stream<List<Completion>> watchCompletions() =>
      _watchSince('completions', Completion.fromMap, _historyWindowDays);

  @override
  Future<void> setCompletion(Completion c) =>
      _collection('completions').doc(c.id).set(c.toMap());

  @override
  Future<void> removeCompletion(String dateKey, String segmentId) =>
      _collection(
        'completions',
      ).doc(Completion.keyFor(dateKey, segmentId)).delete();

  // Micro-step progress -- same unbounded-growth/recent-window reasoning as
  // completions above.
  @override
  Stream<List<MicroStepProgress>> watchMicroStepProgress() => _watchSince(
    'microStepProgress',
    MicroStepProgress.fromMap,
    _historyWindowDays,
  );

  @override
  Future<void> saveMicroStepProgress(MicroStepProgress p) =>
      _collection('microStepProgress').doc(p.id).set(p.toMap());

  // Achieved days
  @override
  Stream<List<AchievedDay>> watchAchievedDays() =>
      _watchAll('achievedDays', AchievedDay.fromMap);

  @override
  Future<void> saveAchievedDay(AchievedDay d) =>
      _collection('achievedDays').doc(d.id).set(d.toMap());

  // Alarm skips -- same unbounded-growth/recent-window reasoning as
  // completions/microStepProgress above (one skip doc can be created per
  // block per day).
  @override
  Stream<List<AlarmSkip>> watchAlarmSkips() =>
      _watchSince('alarmSkips', AlarmSkip.fromMap, _historyWindowDays);

  @override
  Future<void> saveAlarmSkip(AlarmSkip s) =>
      _collection('alarmSkips').doc(s.id).set(s.toMap());

  // MITs -- same unbounded-growth/recent-window reasoning as
  // completions/microStepProgress/alarmSkips above.
  @override
  Stream<List<Mit>> watchMits() =>
      _watchSince('mits', Mit.fromMap, _historyWindowDays);

  @override
  Future<void> saveMit(Mit m) => _collection('mits').doc(m.id).set(m.toMap());

  @override
  Future<void> removeMit(String dateKey, String segmentId) =>
      _collection('mits').doc(Mit.keyFor(dateKey, segmentId)).delete();

  // Check-ins -- not block-keyed (one per day, not per segment), but still
  // unbounded over time, so the same recent-window reasoning applies.
  @override
  Stream<List<Checkin>> watchCheckins() =>
      _watchSince('checkins', Checkin.fromMap, _historyWindowDays);

  @override
  Future<void> saveCheckin(Checkin c) =>
      _collection('checkins').doc(c.id).set(c.toMap());

  @override
  Future<void> removeCheckin(String dateKey) =>
      _collection('checkins').doc(dateKey).delete();

  // Settings
  @override
  Stream<AppSettings> watchSettings() => _userDoc.snapshots().map((snap) {
    final data = snap.data();
    if (data == null) return const AppSettings.defaults();
    return AppSettings.fromMap(data);
  });

  @override
  Future<void> saveSettings(AppSettings s) =>
      _userDoc.set(s.toMap(), SetOptions(merge: true));

  @override
  Future<void> deleteAllData() async {
    // Firestore has no client-side recursive delete, so each known
    // subcollection is drained explicitly, then the user doc (which holds
    // AppSettings) itself. Batched in chunks to stay under the 500-write
    // limit. _historyWindowDays-windowed readers don't matter here -- we
    // delete every doc regardless of date.
    for (final name in _ownedCollections) {
      final snap = await _collection(name).get();
      for (var i = 0; i < snap.docs.length; i += 450) {
        final batch = _firestore.batch();
        for (final doc in snap.docs.skip(i).take(450)) {
          batch.delete(doc.reference);
        }
        await batch.commit();
      }
    }
    await _userDoc.delete();
  }

  Stream<List<T>> _watchAll<T>(
    String collection,
    T Function(Map<String, dynamic>) fromMap,
  ) {
    return _collection(collection).snapshots().map(
      (snap) => snap.docs.map((d) => fromMap(d.data())).toList(),
    );
  }

  /// [_watchAll], but only documents whose "yyyy-MM-dd" `dateKey` is within
  /// the last [windowDays] days (inclusive of today). The cutoff is computed
  /// once when the stream is created — fine for an app that re-subscribes on
  /// each launch; a session left open across midnight just keeps a window
  /// anchored to that launch day, which still includes today either way.
  Stream<List<T>> _watchSince<T>(
    String collection,
    T Function(Map<String, dynamic>) fromMap,
    int windowDays,
  ) {
    final cutoff = DateFormat(
      'yyyy-MM-dd',
    ).format(DateTime.now().subtract(Duration(days: windowDays)));
    return _collection(collection)
        .where('dateKey', isGreaterThanOrEqualTo: cutoff)
        .snapshots()
        .map((snap) => snap.docs.map((d) => fromMap(d.data())).toList());
  }
}

// How far back the date-keyed collections are read. Anything older is left in
// Firestore (never deleted) but not streamed into the app — see the per-method
// comments above for why each reader is safe with only this much history.
const _historyWindowDays = 90; // completions, micro-step progress

// Every subcollection under users/{uid}. Kept in one place so account deletion
// (deleteAllData) can't silently miss one as new collections are added.
const _ownedCollections = [
  'segments',
  'memos',
  'completions',
  'microStepProgress',
  'achievedDays',
  'alarmSkips',
  'mits',
  'checkins',
];
