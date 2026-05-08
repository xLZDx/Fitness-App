import 'package:cloud_firestore/cloud_firestore.dart';

import 'scheduled_session.dart';
import 'scheduled_session_repository.dart';

class FirestoreScheduledSessionRepository
    implements ScheduledSessionRepository {
  FirestoreScheduledSessionRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, List<ScheduledSession>> _cache = {};

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('scheduled_sessions');

  ScheduledSession _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    final raw = data['scheduledFor'];
    if (raw is Timestamp) {
      data['scheduledFor'] = raw.toDate().toIso8601String();
    }
    data['id'] = doc.id;
    return ScheduledSession.fromJson(data);
  }

  @override
  Stream<List<ScheduledSession>> watch(String uid) {
    return _col(uid)
        .orderBy('scheduledFor')
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(_fromDoc).toList(growable: false);
      _cache[uid] = list;
      return list;
    });
  }

  @override
  List<ScheduledSession> cached(String uid) =>
      List.unmodifiable(_cache[uid] ?? const []);

  @override
  Future<void> save(String uid, ScheduledSession session) async {
    await _col(uid).doc(session.id).set(session.toJson());
  }

  @override
  Future<void> delete(String uid, String sessionId) async {
    await _col(uid).doc(sessionId).delete();
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
