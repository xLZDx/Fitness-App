import 'package:cloud_firestore/cloud_firestore.dart';

import 'programme.dart';
import 'programme_repository.dart';

class FirestoreProgrammeRepository implements ProgrammeRepository {
  FirestoreProgrammeRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, List<Programme>> _cache = {};

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('programmes');

  Programme _fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = Map<String, dynamic>.from(doc.data());
    final started = data['startedAt'];
    if (started is Timestamp) {
      data['startedAt'] = started.toDate().toIso8601String();
    }
    final ended = data['endedAt'];
    if (ended is Timestamp) {
      data['endedAt'] = ended.toDate().toIso8601String();
    }
    data['id'] = doc.id;
    return Programme.fromJson(data);
  }

  @override
  Stream<List<Programme>> watch(String uid) {
    // Descending by startedAt at the query level, same direction the model
    // reads in -- no reversal needed, unlike the scheduled-session listener,
    // because this collection is never large enough to window (see the
    // interface doc).
    return _col(uid).orderBy('startedAt', descending: true).snapshots().map(
      (snap) {
        final list = snap.docs.map(_fromDoc).toList(growable: false);
        _cache[uid] = list;
        return list;
      },
    );
  }

  @override
  List<Programme> cached(String uid) => List.unmodifiable(_cache[uid] ?? const []);

  @override
  Future<void> save(String uid, Programme programme) async {
    await _col(uid).doc(programme.id).set(programme.toJson());
  }

  @override
  Future<void> delete(String uid, String programmeId) async {
    await _col(uid).doc(programmeId).delete();
  }

  @override
  Future<List<Programme>> exportAll(String uid) async {
    final snap = await _col(uid).orderBy('startedAt', descending: false).get();
    return snap.docs.map(_fromDoc).toList(growable: false);
  }
}
