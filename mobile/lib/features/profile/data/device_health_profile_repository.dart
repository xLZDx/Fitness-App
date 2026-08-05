import 'dart:async';

import 'local_sensitive_store.dart';
import 'profile_models.dart';
import 'profile_repository.dart';
import 'sensitive_profile.dart';

/// Keeps the health block off the server without any caller knowing.
///
/// ## Why a decorator
///
/// Ten call sites read `profile.health.injuries` — the exercise filter, the
/// plan builder, safety coverage, the injuries page, the questionnaire. Every
/// one of them is on the device, because no Cloud Function reads the profile
/// at all. Splitting the model into a server half and a device half would have
/// touched all ten and every test that builds a `UserProfile`.
///
/// So the split happens at the one boundary that already exists. Callers keep
/// receiving a whole [UserProfile]; what changed is where each half of it came
/// from. [FirestoreProfileRepository] is untouched and still writes whatever
/// it is handed — it is simply never handed the sensitive fields again.
///
/// ## Reading before the migration has run
///
/// A profile written before this class existed still has its health block in
/// Firestore. [mergeSensitive] leaves the server's values in place when the
/// local store is empty, so those users keep their injuries and their filter
/// keeps working. H1b is what moves the block down and deletes it up there;
/// until it runs, this class is additive and loses nothing.
class DeviceHealthProfileRepository implements ProfileRepository {
  DeviceHealthProfileRepository(this._inner, this._store);

  final ProfileRepository _inner;
  final LocalSensitiveStore _store;

  /// Mirrors what the store holds, because [cached] is synchronous and the
  /// store is not. Populated by every path that reads or writes.
  final Map<String, SensitiveProfile> _cache = {};

  @override
  Stream<UserProfile?> watch(String uid) =>
      _inner.watch(uid).asyncMap((p) async {
        if (p == null) return null;
        final s = await _read(uid);
        return mergeSensitive(p, s);
      });

  /// Synchronous, so it answers from the mirror. Before the first async read
  /// the mirror is empty, and an empty [SensitiveProfile] merges to a no-op —
  /// the caller gets the server profile rather than a profile with the health
  /// block silently blanked. Blanking would read as "no injuries reported",
  /// which is the one wrong answer a contraindication filter must never give.
  @override
  UserProfile? cached(String uid) {
    final p = _inner.cached(uid);
    if (p == null) return null;
    return mergeSensitive(p, _cache[uid] ?? SensitiveProfile.empty);
  }

  @override
  Future<UserProfile?> load(String uid) async {
    final p = await _inner.load(uid);
    if (p == null) return null;
    return mergeSensitive(p, await _read(uid));
  }

  /// Writes the two halves to two places.
  ///
  /// Local first, deliberately. If the process dies between the two calls, the
  /// device holds the newer health answers and the server holds the older
  /// everything-else — recoverable, and the filter stays correct. The other
  /// order would publish a stripped profile while the answers it stripped were
  /// still nowhere, which for one restart looks exactly like "the user has no
  /// injuries".
  @override
  Future<void> save(UserProfile profile) async {
    final sensitive = extractSensitive(profile);
    await _store.write(profile.uid, sensitive);
    _cache[profile.uid] = sensitive;
    await _inner.save(stripSensitive(profile));
  }

  @override
  Future<void> delete(String uid) async {
    await _store.clear(uid);
    _cache.remove(uid);
    await _inner.delete(uid);
  }

  Future<SensitiveProfile> _read(String uid) async {
    final s = await _store.read(uid);
    _cache[uid] = s;
    return s;
  }
}
