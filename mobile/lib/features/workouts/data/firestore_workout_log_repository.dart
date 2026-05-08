import 'package:cloud_firestore/cloud_firestore.dart';

import 'workout_log.dart';
import 'workout_log_repository.dart';

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

  @override
  Stream<List<WorkoutLogEntry>> watch(String uid) {
    return _col(uid)
        .orderBy('completedAt', descending: true)
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
  Future<void> clear(String uid) async {
    final batch = _db.batch();
    final snap = await _col(uid).get();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
    _cache.remove(uid);
  }
}
