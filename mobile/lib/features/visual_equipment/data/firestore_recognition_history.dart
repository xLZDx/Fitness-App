import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'recognition_history.dart';

/// Firestore-backed recognised-machine store. Documents live at
/// `users/{uid}/recognised_equipment/{equipmentId}` so the existing
/// `match /users/{uid}/{document=**}` rule already covers them.
///
/// The document id **is** the equipment id. That is what keeps a live camera
/// from filling the collection: fifty frames of one machine address one
/// document. The de-duplication itself is not re-implemented here — every
/// write folds through [RecognitionDedup], the same rule the in-memory
/// repository uses, so the two backends cannot disagree.
///
/// Signed out, every method degrades to a no-op / empty result rather than
/// throwing: recognition runs off the camera, which can be live before auth
/// has settled, and a crash there would take the Scan page down.
class FirestoreRecognitionHistoryRepository
    implements RecognitionHistoryRepository {
  FirestoreRecognitionHistoryRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _injectedDb = firestore,
        _injectedAuth = auth;

  final FirebaseFirestore? _injectedDb;
  final FirebaseAuth? _injectedAuth;

  // Resolved lazily rather than in the constructor: touching
  // `FirebaseFirestore.instance` / `FirebaseAuth.instance` before
  // `Firebase.initializeApp` throws, and this repository is constructed as a
  // Riverpod override. Same reason as `FirebaseAuthRepository`
  // (features/auth/data/firebase_auth_repository.dart).
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('recognised_equipment');

  Query<Map<String, dynamic>> _query(String uid) =>
      _col(uid).orderBy('recognisedAt', descending: true);

  List<RecognitionEntry> _fromSnapshot(
    QuerySnapshot<Map<String, dynamic>> snap,
  ) =>
      RecognitionDedup.sortNewestFirst(
        snap.docs.map((d) => recognitionEntryFromFirestore(d.id, d.data())),
      );

  @override
  Stream<List<RecognitionEntry>> watch() {
    late StreamController<List<RecognitionEntry>> out;
    StreamSubscription<User?>? authSub;
    StreamSubscription<List<RecognitionEntry>>? docsSub;
    // Bumped on every auth event. `bind` awaits a cancel, so two events in
    // quick succession (sign-out immediately followed by sign-in) can both be
    // in flight; without this the slower one would overwrite `docsSub` and
    // leak the other subscription, leaving the stream fed by a stale uid.
    var generation = 0;

    // Re-binds the document stream whenever the signed-in user changes, so
    // signing in mid-session starts populating the list without anyone
    // having to rebuild the provider. `asyncExpand` cannot do this: a
    // Firestore snapshot stream never completes, so it would swallow every
    // auth event after the first.
    Future<void> bind(User? user) async {
      final mine = ++generation;
      await docsSub?.cancel();
      docsSub = null;
      if (mine != generation || out.isClosed) return;
      if (user == null) {
        out.add(const []);
        return;
      }
      docsSub = _query(user.uid).snapshots().map(_fromSnapshot).listen(
        (entries) {
          if (mine == generation && !out.isClosed) out.add(entries);
        },
        onError: (Object e, StackTrace st) {
          if (mine == generation && !out.isClosed) out.addError(e, st);
        },
      );
    }

    out = StreamController<List<RecognitionEntry>>(
      onListen: () {
        authSub = _auth.authStateChanges().listen(bind);
      },
      onCancel: () async {
        await authSub?.cancel();
        await docsSub?.cancel();
      },
    );
    return out.stream;
  }

  @override
  Future<void> record(RecognitionEntry entry) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = _col(uid).doc(entry.equipmentId);
    final snap = await doc.get();
    final data = snap.data();

    // Fold against whatever is already stored so a burst of live frames
    // keeps the best confidence instead of the last one to land.
    final merged = (snap.exists && data != null)
        ? RecognitionDedup.merge(
            recognitionEntryFromFirestore(snap.id, data),
            entry,
          )
        : entry;

    await doc.set(recognitionEntryToFirestore(merged), SetOptions(merge: true));
  }

  @override
  Future<List<RecognitionEntry>> list() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    return _fromSnapshot(await _query(uid).get());
  }

  @override
  Future<void> clear() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    final snap = await _col(uid).get();
    if (snap.docs.isEmpty) return;
    final batch = _db.batch();
    for (final d in snap.docs) {
      batch.delete(d.reference);
    }
    await batch.commit();
  }
}

/// Decodes a stored document into an entry.
///
/// [equipmentId] comes from the document id, which is authoritative — the
/// field inside the document is only a convenience for anyone reading the
/// collection raw.
///
/// Tolerates `recognisedAt` arriving as a Firestore [Timestamp] (what a
/// server-side write or a console edit produces) as well as the ISO-8601
/// string this repository writes. Top-level and pure so the decode path is
/// testable without a Firebase binding.
RecognitionEntry recognitionEntryFromFirestore(
  String equipmentId,
  Map<String, dynamic> data,
) {
  final normalised = Map<String, dynamic>.from(data);
  final raw = normalised['recognisedAt'];
  if (raw is Timestamp) {
    normalised['recognisedAt'] = raw.toDate().toIso8601String();
  }
  normalised['equipmentId'] = equipmentId;
  return RecognitionEntry.fromJson(normalised);
}

/// Encodes an entry for storage. `recognisedAt` goes in as an ISO-8601 UTC
/// string — [RecognitionEntry] normalises to UTC, and those strings sort
/// lexicographically in the same order as the instants they encode, which is
/// what makes the `orderBy('recognisedAt')` query correct.
Map<String, dynamic> recognitionEntryToFirestore(RecognitionEntry entry) =>
    entry.toJson();
