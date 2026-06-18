import 'package:cloud_firestore/cloud_firestore.dart';

import '../../models/app_settings.dart';
import '../../models/completion.dart';
import '../../models/memo.dart';
import '../../models/routine.dart';
import '../../models/segment.dart';
import '../planner_repository.dart';

/// Firestore-backed [PlannerRepository] for the signed-in user. Every model
/// already has a plain `toMap`/`fromMap` (added in STEP 3 for exactly this
/// swap), so this is a straight read/write mapping — no new serialization
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

  CollectionReference<Map<String, dynamic>> _collection(String name) => _userDoc.collection(name);

  // Segments
  @override
  Stream<List<Segment>> watchSegments() => _watchAll('segments', Segment.fromMap);

  @override
  Future<void> upsertSegment(Segment s) => _collection('segments').doc(s.id).set(s.toMap());

  @override
  Future<void> deleteSegment(String id) => _collection('segments').doc(id).delete();

  // Routines
  @override
  Stream<List<Routine>> watchRoutines() => _watchAll('routines', Routine.fromMap);

  @override
  Future<void> upsertRoutine(Routine r) => _collection('routines').doc(r.id).set(r.toMap());

  @override
  Future<void> deleteRoutine(String id) => _collection('routines').doc(id).delete();

  // Memos
  @override
  Stream<List<Memo>> watchMemos() => _watchAll('memos', Memo.fromMap);

  @override
  Future<void> addMemo(Memo m) => _collection('memos').doc(m.id).set(m.toMap());

  @override
  Future<void> updateMemo(Memo m) => _collection('memos').doc(m.id).set(m.toMap());

  @override
  Future<void> deleteMemo(String id) => _collection('memos').doc(id).delete();

  // Completions
  @override
  Stream<List<Completion>> watchCompletions() => _watchAll('completions', Completion.fromMap);

  @override
  Future<void> setCompletion(Completion c) => _collection('completions').doc(c.id).set(c.toMap());

  @override
  Future<void> removeCompletion(String dateKey, String routineId) =>
      _collection('completions').doc(Completion.keyFor(dateKey, routineId)).delete();

  // Settings
  @override
  Stream<AppSettings> watchSettings() => _userDoc.snapshots().map((snap) {
        final data = snap.data();
        if (data == null) return const AppSettings.defaults();
        return AppSettings.fromMap(data);
      });

  @override
  Future<void> saveSettings(AppSettings s) => _userDoc.set(s.toMap(), SetOptions(merge: true));

  Stream<List<T>> _watchAll<T>(String collection, T Function(Map<String, dynamic>) fromMap) {
    return _collection(collection)
        .snapshots()
        .map((snap) => snap.docs.map((d) => fromMap(d.data())).toList());
  }
}
