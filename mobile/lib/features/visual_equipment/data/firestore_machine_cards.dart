import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'machine_card.dart';
import 'machine_card_repository.dart';

/// Firestore-backed machine cards, at `users/{uid}/machine_cards/{cardId}`.
///
/// ## Why under the user, when we are also the audience
///
/// The card is the user's — it is what they see on their own list. It is also
/// how we learn what people photograph that we have nothing for. A separate
/// world-writable collection would have served us more directly, and would
/// have meant a rule letting any signed-in client write arbitrary documents
/// into a shared space. The same numbers come out of a collection-group read
/// over `machine_cards` with the Admin SDK, so the shared write surface buys
/// nothing.
///
/// It also needs no rules change: `match /users/{uid}/{coll}/{document=**}`
/// already covers this subcollection (firestore.rules), and `machine_cards` is
/// not the server-only `subscription`.
///
/// Signed out, every method degrades to a no-op / empty result rather than
/// throwing — same reason as the recognition history: this runs off the
/// scanner, which can be live before auth has settled.
class FirestoreMachineCardRepository implements MachineCardRepository {
  FirestoreMachineCardRepository({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _injectedDb = firestore,
        _injectedAuth = auth;

  final FirebaseFirestore? _injectedDb;
  final FirebaseAuth? _injectedAuth;

  // Lazily resolved: touching the singletons before `Firebase.initializeApp`
  // throws, and this is constructed as a Riverpod override.
  FirebaseFirestore get _db => _injectedDb ?? FirebaseFirestore.instance;
  FirebaseAuth get _auth => _injectedAuth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> _col(String uid) =>
      _db.collection('users').doc(uid).collection('machine_cards');

  Query<Map<String, dynamic>> _query(String uid) =>
      _col(uid).orderBy('lastSeenAt', descending: true);

  List<MachineCard> _fromSnapshot(QuerySnapshot<Map<String, dynamic>> snap) =>
      MachineCardMerge.sortNewestFirst(
        snap.docs.map((d) => machineCardFromFirestore(d.id, d.data())),
      );

  @override
  Stream<List<MachineCard>> watch() {
    late StreamController<List<MachineCard>> out;
    StreamSubscription<User?>? authSub;
    StreamSubscription<List<MachineCard>>? docsSub;
    // Bumped on every auth event: `bind` awaits a cancel, so a sign-out
    // immediately followed by a sign-in can have both in flight, and without
    // this the slower one would overwrite `docsSub` and leave the stream fed
    // by a stale uid.
    var generation = 0;

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
        (cards) {
          if (mine == generation && !out.isClosed) out.add(cards);
        },
        onError: (Object e, StackTrace st) {
          if (mine == generation && !out.isClosed) out.addError(e, st);
        },
      );
    }

    out = StreamController<List<MachineCard>>(
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
  Future<void> save(MachineCard card) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final doc = _col(uid).doc(card.id);
    final snap = await doc.get();
    final data = snap.data();

    // Fold against what is stored so the count, the first sighting and any
    // decision already taken about this machine survive.
    final merged = (snap.exists && data != null)
        ? MachineCardMerge.fold(machineCardFromFirestore(snap.id, data), card)
        : card;

    await doc.set(machineCardToFirestore(merged), SetOptions(merge: true));
  }

  @override
  Future<List<MachineCard>> list() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return const [];
    return _fromSnapshot(await _query(uid).get());
  }

  @override
  Future<void> remove(String id) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _col(uid).doc(id).delete();
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

/// Decodes a stored document. [id] comes from the document id, which is
/// authoritative — the field inside is a convenience for reading the
/// collection raw.
///
/// Tolerates the dates arriving as Firestore [Timestamp]s (what a console edit
/// or a server-side write produces) as well as the ISO-8601 strings this
/// repository writes.
MachineCard machineCardFromFirestore(String id, Map<String, dynamic> data) {
  final normalised = Map<String, dynamic>.from(data);
  for (final key in const ['firstSeenAt', 'lastSeenAt']) {
    final raw = normalised[key];
    if (raw is Timestamp) {
      normalised[key] = raw.toDate().toUtc().toIso8601String();
    }
  }
  normalised['id'] = id;
  return MachineCard.fromJson(normalised);
}

/// Encodes a card for storage. Dates go in as ISO-8601 UTC strings: they sort
/// lexicographically in the same order as the instants they encode, which is
/// what makes `orderBy('lastSeenAt')` correct.
Map<String, dynamic> machineCardToFirestore(MachineCard card) {
  final json = card.toJson();
  // Always present, even for a card that has only been seen once: the query
  // orders on it, and Firestore drops a document from an `orderBy` when the
  // field is missing — the machine would simply vanish from the user's list.
  json['lastSeenAt'] ??= card.firstSeenAt.toUtc().toIso8601String();
  // The photo stays on the phone that took it. `photoPath` is a path in that
  // device's cache directory: it means nothing on another device, it is
  // already dangling after the cache is cleared, and the only version of it
  // worth storing would be the image itself — which is a decision about the
  // user's pictures leaving their phone, not a detail of this write.
  json.remove('photoPath');
  return json;
}
