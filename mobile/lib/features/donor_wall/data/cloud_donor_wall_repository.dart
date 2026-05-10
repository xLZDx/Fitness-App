import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';

import 'donor_wall_entry.dart';
import 'donor_wall_repository.dart';

/// Real implementation backed by:
///   - Firestore collection `donor_wall` (public read, no client write)
///   - Cloud Function `optInDonorWall` for opt-in / opt-out
class CloudDonorWallRepository implements DonorWallRepository {
  CloudDonorWallRepository({
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
    FirebaseAuth? auth,
  })  : _db = firestore ?? FirebaseFirestore.instance,
        _functions =
            functions ?? FirebaseFunctions.instanceFor(region: 'us-central1'),
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseFunctions _functions;
  final FirebaseAuth _auth;

  @override
  Future<List<DonorWallEntry>> list() async {
    final snap = await _db
        .collection('donor_wall')
        .orderBy('since', descending: true)
        .limit(500)
        .get();
    return snap.docs
        .map((d) => DonorWallEntry.fromJson(d.id, d.data()))
        .toList();
  }

  @override
  Stream<List<DonorWallEntry>> watch() {
    return _db
        .collection('donor_wall')
        .orderBy('since', descending: true)
        .limit(500)
        .snapshots()
        .map((s) => s.docs
            .map((d) => DonorWallEntry.fromJson(d.id, d.data()))
            .toList());
  }

  @override
  Future<void> optIn({
    required String displayName,
    String? message,
  }) async {
    final user = _auth.currentUser;
    if (user == null) {
      throw StateError('Sign in to opt in to the donor wall.');
    }
    await _functions.httpsCallable('optInDonorWall').call(<String, dynamic>{
      'displayName': displayName,
      if (message != null && message.trim().isNotEmpty) 'message': message,
    });
  }

  @override
  Future<void> optOut() async {
    final user = _auth.currentUser;
    if (user == null) return;
    await _functions
        .httpsCallable('optOutDonorWall')
        .call(<String, dynamic>{});
  }
}
