import 'package:cloud_firestore/cloud_firestore.dart';

import 'workout_log.dart';
import 'workout_log_repository.dart';
import 'workout_log_totals.dart';

/// Firestore-backed log store. Documents live at
/// `users/{uid}/workout_logs/{entryId}` so the existing
/// `match /users/{uid}/{document=**}` rule already covers them.
class FirestoreWorkoutLogRepository implements WorkoutLogRepository {
  FirestoreWorkoutLogRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, List<WorkoutLogEntry>> _cache = {};

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('workout_logs');

  WorkoutLogEntry _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    final raw = data['completedAt'];
    if (raw is Timestamp) {
      data['completedAt'] = raw.toDate().toIso8601String();
    }
    data['id'] = doc.id;
    return WorkoutLogEntry.fromJson(data);
  }

  /// The all-time numbers a windowed listener cannot serve.
  ///
  /// Its own document rather than a field on the profile: it is written on a
  /// different cadence than anything in the questionnaire, and the profile
  /// document is read on the router's redirect path where an extra field
  /// would be carried on every cold start for no reason.
  DocumentReference<Map<String, dynamic>> _totalsDoc(String uid) =>
      _db.collection('users').doc(uid).collection('stats').doc('workouts');

  @override
  Stream<List<WorkoutLogEntry>> watch(String uid) {
    return _col(uid)
        .orderBy('completedAt', descending: true)
        .limit(kWorkoutHistoryWindow)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(_fromDoc).toList(growable: false);
      _cache[uid] = list;
      return list;
    });
  }

  @override
  List<WorkoutLogEntry> cached(String uid) =>
      List.unmodifiable(_cache[uid] ?? const []);

  @override
  Future<void> save(String uid, WorkoutLogEntry entry) async {
    await _col(uid).doc(entry.id).set(entry.toJson());
  }

  @override
  Future<void> delete(String uid, String entryId) async {
    await _col(uid).doc(entryId).delete();
  }

  @override
  Future<WorkoutLogTotals> totals(String uid) async {
    // Counted server-side. `count()` bills one read per 1,000 documents and
    // never transfers them, so this stays one cheap call for a user with a
    // decade of history — and unlike a stored counter it cannot drift when a
    // write fails between incrementing and committing.
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
    // Read-then-write rather than a plain set, so a stale device replaying an
    // old streak cannot lower the record. A transaction because two devices
    // finishing a workout in the same minute is exactly when a record moves.
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
    // Chunked at 400: `batch.commit()` rejects above 500 operations, so the
    // single-batch version could not clear the history of exactly the user
    // most likely to want it cleared.
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
