import 'package:cloud_firestore/cloud_firestore.dart';

import 'workout_log_totals.dart';
import 'workout_session.dart';
import 'workout_session_repository.dart';

/// Firestore-backed session store. Documents live at
/// `users/{uid}/workout_sessions/{sessionId}` -- a sibling of
/// `users/{uid}/workout_logs`, not a replacement (see
/// `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`). The wildcard rule
/// `match /users/{uid}/{coll}/{document=**}` already covers this collection;
/// no rules change needed.
class FirestoreWorkoutSessionRepository implements WorkoutSessionRepository {
  FirestoreWorkoutSessionRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, List<WorkoutSession>> _cache = {};

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('workout_sessions');

  /// A doc of its own, not a field on the profile or on the log totals doc --
  /// same rationale as `_totalsDoc` in `firestore_workout_log_repository.dart`:
  /// written on a different cadence than anything read on the router's
  /// redirect path.
  DocumentReference<Map<String, dynamic>> _totalsDoc(String uid) => _db
      .collection('users')
      .doc(uid)
      .collection('stats')
      .doc('workout_sessions');

  WorkoutSession _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    for (final field in ['startedAt', 'completedAt']) {
      final raw = data[field];
      if (raw is Timestamp) data[field] = raw.toDate().toIso8601String();
    }
    data['id'] = doc.id;
    return WorkoutSession.fromJson(data);
  }

  @override
  Stream<List<WorkoutSession>> watch(String uid) {
    return _col(uid)
        .orderBy('startedAt', descending: true)
        .limit(kWorkoutSessionHistoryWindow)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(_fromDoc).toList(growable: false);
      _cache[uid] = list;
      return list;
    });
  }

  @override
  List<WorkoutSession> cached(String uid) =>
      List.unmodifiable(_cache[uid] ?? const []);

  @override
  Future<void> save(String uid, WorkoutSession session) async {
    await _col(uid).doc(session.id).set(session.toJson());
  }

  @override
  Future<void> delete(String uid, String sessionId) async {
    await _col(uid).doc(sessionId).delete();
  }

  @override
  Future<List<WorkoutSession>> exportAll(String uid) async {
    final snap = await _col(uid).orderBy('startedAt', descending: true).get();
    return snap.docs.map(_fromDoc).toList(growable: false);
  }

  @override
  Future<WorkoutLogTotals> totals(String uid) async {
    final counted = await _col(uid).count().get();
    final record = await _totalsDoc(uid).get();
    return WorkoutLogTotals(
      total: counted.count ?? 0,
      longestStreakDays:
          (record.data()?['longestStreakDays'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  Future<void> recordStreak(String uid, int days) async {
    if (days <= 0) return;
    await _db.runTransaction((tx) async {
      final ref = _totalsDoc(uid);
      final snap = await tx.get(ref);
      final current = (snap.data()?['longestStreakDays'] as num?)?.toInt() ?? 0;
      if (days <= current) return;
      tx.set(ref, {'longestStreakDays': days}, SetOptions(merge: true));
    });
  }

  @override
  Future<void> clear(String uid) async {
    while (true) {
      final snap = await _col(uid).limit(400).get();
      if (snap.docs.isEmpty) break;
      final batch = _db.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
      if (snap.docs.length < 400) break;
    }
    await _totalsDoc(uid).delete();
    _cache.remove(uid);
  }
}
