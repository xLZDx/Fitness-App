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
    // Descending then reversed, rather than ascending with a limit.
    //
    // Ascending was the worst possible order for this collection: completed
    // sessions are never deleted, so the oldest rows are the most numerous and
    // the least wanted -- every consumer looks forward, `filterUpcoming` at 14
    // days and the offline prefetch at 7 -- and an unbounded ascending
    // listener re-read all of them on every cold start before reaching
    // anything anyone would render.
    //
    // A `where` on `scheduledFor` would have been the obvious fix and is the
    // riskier one: the field is stored as an ISO 8601 string
    // (`ScheduledSession.toJson`), so a range filter compares text. That is
    // correct only while every writer produces the same format -- a local
    // DateTime and a UTC one stringify to different lengths and sort
    // differently. Taking the highest N and reversing needs no such
    // assumption, and leaves the stream's ascending contract untouched.
    return _col(uid)
        .orderBy('scheduledFor', descending: true)
        .limit(kScheduledSessionWindow)
        .snapshots()
        .map((snap) {
      final list = snap.docs.map(_fromDoc).toList().reversed.toList(
            growable: false,
          );
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
  Future<List<ScheduledSession>> exportAll(String uid) async {
    final snap =
        await _col(uid).orderBy('scheduledFor', descending: false).get();
    return snap.docs.map(_fromDoc).toList(growable: false);
  }

  @override
  Future<void> clear(String uid) async {
    // Chunked at 400 for the same reason as the workout log: a single batch
    // rejects above 500 operations, so the unchunked version failed for
    // exactly the user with enough history to want it gone.
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
    _cache.remove(uid);
  }
}
