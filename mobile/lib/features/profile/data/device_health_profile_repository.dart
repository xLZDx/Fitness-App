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

  /// Uids whose one-way move off the server has been attempted this session.
  ///
  /// Set BEFORE the write, not after: [watch] is a stream, and the write it
  /// performs makes the inner stream emit again. Marking afterwards would let
  /// the second emission start a second migration while the first is still in
  /// flight.
  final Set<String> _migrated = {};

  @override
  Stream<UserProfile?> watch(String uid) =>
      _inner.watch(uid).asyncMap((p) async {
        if (p == null) return null;
        return _resolve(uid, p);
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
    return _resolve(uid, p);
  }

  /// H1b — moves a pre-split profile's health block down to the device and
  /// clears it upstream, then answers from the device like any other read.
  ///
  /// Runs on the user's next read rather than as a bulk admin job, because
  /// that is where the data already flows and it needs no elevated
  /// credentials. Its blind spot is exact and worth naming: an account whose
  /// owner never opens the app again is never migrated by this path, so the
  /// server keeps their health block indefinitely. That is what
  /// `scripts/ops/strip_health_from_profiles.py` is for, and why H1c cannot
  /// claim the data is gone until that script has run.
  Future<UserProfile> _resolve(String uid, UserProfile server) async {
    final local = await _read(uid);
    final onServer = extractSensitive(server);

    // The trigger is "the server still carries it", NOT "the device does not
    // have it yet". Those come apart precisely in the case worth surviving:
    // the local write lands, the upstream clear fails offline, and the device
    // now holds a copy. Keying off the local store would then read as "already
    // migrated" forever, and the block would sit in Firestore for good --
    // silently, since every screen would look correct.
    if (onServer.isEmpty || _migrated.contains(uid)) {
      return mergeSensitive(server, local);
    }

    _migrated.add(uid);
    // A device copy outranks the server's: it is what the user has been
    // editing since the split.
    final keep = local.isEmpty ? onServer : local;
    try {
      if (local.isEmpty) {
        await _store.write(uid, onServer);
        _cache[uid] = onServer;
      }
      await _inner.save(stripSensitive(server));
    } catch (_) {
      // Offline, or a rules rejection. The user must keep seeing their own
      // injuries either way, so this returns what it already has and lets a
      // later read try again. Rethrowing would take down every screen watching
      // the profile over a housekeeping write.
      _migrated.remove(uid);
    }
    return mergeSensitive(server, keep);
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
