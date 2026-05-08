import 'package:cloud_firestore/cloud_firestore.dart';

import 'subscription_models.dart';
import 'subscription_repository.dart';

/// Firestore-backed subscription store. Documents live at
/// `users/{uid}/subscription/main` so the existing per-uid Firestore rule
/// already covers them.
class FirestoreSubscriptionRepository implements SubscriptionRepository {
  FirestoreSubscriptionRepository([FirebaseFirestore? firestore])
      : _db = firestore ?? FirebaseFirestore.instance;

  final FirebaseFirestore _db;
  final Map<String, Subscription> _cache = {};

  DocumentReference<Map<String, dynamic>> _doc(String uid) =>
      _db.collection('users').doc(uid).collection('subscription').doc('main');

  Subscription _normalise(String uid, Map<String, dynamic> data) {
    final sanitised = Map<String, dynamic>.from(data);
    for (final k in const ['trialEndsAt', 'currentPeriodEndsAt']) {
      final raw = sanitised[k];
      if (raw is Timestamp) {
        sanitised[k] = raw.toDate().toIso8601String();
      }
    }
    return Subscription.fromJson(uid, sanitised);
  }

  @override
  Stream<Subscription?> watch(String uid) {
    return _doc(uid).snapshots().map((snap) {
      if (!snap.exists) {
        _cache.remove(uid);
        return null;
      }
      final data = snap.data();
      if (data == null) return null;
      final s = _normalise(uid, data);
      _cache[uid] = s;
      return s;
    });
  }

  @override
  Subscription? cached(String uid) => _cache[uid];

  @override
  Future<void> save(Subscription sub) async {
    await _doc(sub.uid).set(sub.toJson(), SetOptions(merge: true));
    _cache[sub.uid] = sub;
  }

  @override
  Future<void> delete(String uid) async {
    await _doc(uid).delete();
    _cache.remove(uid);
  }
}
