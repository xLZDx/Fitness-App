import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../progress_photos/data/photo_directory.dart';
import '../../progress_photos/data/photo_key_store.dart';
import '../../scanner/history/scan_history_store.dart' show kScanHistoryDir;

/// Erases everything about a user that lives on the DEVICE.
///
/// A1 exists because "delete my account" was a server-only operation: the
/// Cloud Function removed the Firestore side and the client did nothing but
/// sign out. Two consequences, both in `core/DATA_INVENTORY_2026-08-11.md`:
///
///   1. The health/injury blob (`profile.sensitive.{uid}`) stayed in
///      SharedPreferences after the account that owned it was gone.
///   2. Progress photos and their AES key are not uid-scoped at all
///      (`<docs>/progress_photos/`, `progress_photos.key.v1`), so the next
///      account signed in on the same device opened the previous account's
///      photos with the previous account's key.
///
/// (2) is why this class deletes photo DIRECTORIES rather than walking the
/// index and deleting the photos it lists: an index-driven wipe leaves behind
/// exactly the blobs whose index row was lost.
///
/// A2-sec has since landed the per-uid layout this class was written to
/// anticipate, so the target narrowed from the whole tree to
/// `<docs>/progress_photos/<uid>/` plus any loose legacy files left directly
/// under the root. Deleting the tree would now erase a DIFFERENT account's
/// photos as a side effect of deleting yours — the same mistake the exact-key
/// match on `profile.sensitive.{uid}` below exists to avoid.
///
/// Best-effort by design, and the caller must treat it that way: the account
/// IS deleted server-side by the time this runs. A failure here is a
/// leftover file on one phone, not a failed deletion, and reporting it as the
/// latter would tell the user something untrue.
abstract class LocalDataWipe {
  /// Runs every step even when one fails, then throws [LocalWipeIncomplete]
  /// naming what remains. Callers treat it as best-effort (the account is
  /// already deleted) but must not report the device as clean.
  Future<void> wipe(String uid);
}

/// Remembers WHICH accounts' device data still has to be erased.
///
/// A uid is added right AFTER the server confirms the deletion and removed only
/// after that uid's wipe finished. Added after, not before, on purpose: a marker
/// that existed while the account was still alive could later erase the only
/// copy of a live account's health answers. If the process dies between
/// confirmation and the wipe, the uid is still known and the next launch
/// finishes the job. A SET, not a single value: a second deletion must never
/// overwrite the record of a first wipe that has not completed. Holds uids only,
/// never health data.
abstract class PendingWipeMarker {
  Future<Set<String>> read();
  Future<void> add(String uid);
  Future<void> remove(String uid);
}

class PrefsPendingWipeMarker implements PendingWipeMarker {
  PrefsPendingWipeMarker({SharedPreferences? prefs}) : _injected = prefs;
  final SharedPreferences? _injected;
  static const key = 'account_deletion.pending_wipe_uids';

  Future<SharedPreferences> get _prefs async =>
      _injected ?? await SharedPreferences.getInstance();

  @override
  Future<Set<String>> read() async =>
      ((await _prefs).getStringList(key) ?? const <String>[]).toSet();

  // Read-modify-write happens with no await between the read and the call to
  // setStringList, so two concurrent add/remove calls cannot interleave.
  @override
  Future<void> add(String uid) async {
    final prefs = await _prefs;
    final next = {...?prefs.getStringList(key), uid}.toList();
    if (!await prefs.setStringList(key, next)) {
      throw StateError('could not record the pending device wipe');
    }
  }

  @override
  Future<void> remove(String uid) async {
    final prefs = await _prefs;
    final next = [...?prefs.getStringList(key)]..remove(uid);
    if (next.isEmpty) {
      await prefs.remove(key);
    } else {
      await prefs.setStringList(key, next);
    }
  }
}

class InMemoryPendingWipeMarker implements PendingWipeMarker {
  final Set<String> _uids = {};
  @override
  Future<Set<String>> read() async => {..._uids};
  @override
  Future<void> add(String uid) async => _uids.add(uid);
  @override
  Future<void> remove(String uid) async => _uids.remove(uid);
}

/// Finishes a device wipe that an interrupted account deletion left behind.
///
/// Call whenever the signed-in user changes (null when signed out). A marker for
/// the account that is STILL signed in is left alone for now: its own deletion
/// retry handles it, or the sign-out that follows triggers the next call.
/// Every other pending uid is wiped independently, so one failure never blocks
/// the rest. Returns true when at least one wipe ran to completion.
///
/// [currentUid], when given, is asked again right before each irreversible wipe
/// and wins over [signedInUid]: a sweep that waited in a queue must not act on
/// the sign-in state of the moment it was scheduled.
Future<bool> finishInterruptedWipe({
  required PendingWipeMarker marker,
  required LocalDataWipe wipe,
  required String? signedInUid,
  String? Function()? currentUid,
}) async {
  var wiped = false;
  try {
    for (final pending in await marker.read()) {
      if (pending == (currentUid != null ? currentUid() : signedInUid)) {
        continue;
      }
      if (!_looksLikeUid(pending)) {
        // The uid becomes a directory name below. A value that is empty or
        // carries a path separator is not ours; drop it instead of acting on it.
        await marker.remove(pending);
        continue;
      }
      try {
        await wipe.wipe(pending);
      } catch (e) {
        // Keep the marker so the next sweep tries again.
        debugPrint(
            'interrupted account deletion: device wipe still incomplete: ${e.runtimeType}');
        continue;
      }
      await marker.remove(pending);
      wiped = true;
    }
  } catch (e) {
    // A preferences failure must not become an unhandled async error.
    debugPrint('interrupted account deletion sweep failed: ${e.runtimeType}');
  }
  return wiped;
}

bool _looksLikeUid(String uid) =>
    uid.isNotEmpty &&
    uid != '.' &&
    uid != '..' &&
    !uid.contains('/') &&
    !uid.contains(r'\');

/// Thrown after a wipe that attempted everything but left something behind.
class LocalWipeIncomplete implements Exception {
  LocalWipeIncomplete(this.remaining);

  /// Key names with the uid masked as `<uid>`, plus `progress_photos`.
  final List<String> remaining;

  @override
  String toString() =>
      'LocalWipeIncomplete: device data remains (${remaining.join(', ')})';
}

class DeviceLocalDataWipe implements LocalDataWipe {
  DeviceLocalDataWipe({
    SharedPreferences? prefs,
    Directory? documentsDir,
    Future<void> Function(String uid)? forgetPhotoKey,
  })  : _injectedPrefs = prefs,
        _injectedDir = documentsDir,
        _forgetPhotoKey = forgetPhotoKey ?? SecurePhotoKeyStore.forget;

  final SharedPreferences? _injectedPrefs;
  final Directory? _injectedDir;
  final Future<void> Function(String uid) _forgetPhotoKey;

  /// Keys erased for every deletion, regardless of who else uses this phone.
  ///
  /// Keys that describe a PERSON: everything under `moment.` is a counter
  /// about how this user has used the app, and `settings.tier_override` is a
  /// debug entitlement that must not outlive the account it was set for.
  ///
  /// The health blob is matched by its EXACT key, `profile.sensitive.{uid}`,
  /// not by the `profile.sensitive.` prefix. The prefix would also erase a
  /// different, still-existing account's blob on a shared phone — deleting
  /// someone else's health data as a side effect of deleting yours. Their own
  /// deletion is what removes theirs.
  ///
  /// The two pre-A2-sec photo keys are NOT here, because both are conditional
  /// on who owns the legacy data — see [_legacyIsMine].
  static const _personalPrefixes = <String>['moment.'];
  static const _personalKeys = <String>['settings.tier_override'];

  /// The pre-A2-sec install-wide photo key. Still handled because an install
  /// that never re-opened the Photos tab never migrated it, and it would
  /// otherwise sit in plaintext prefs forever. The CURRENT key is not a prefs
  /// key at all — it lives in the Keystore and goes via
  /// [SecurePhotoKeyStore.forget].
  static const _legacyPhotoKey = SecurePhotoKeyStore.legacyPrefsKey;

  /// Whether this user may erase the un-migrated legacy photo data.
  ///
  /// The Act gate on A2-sec caught the first version doing this
  /// unconditionally, while the migration marker right beside it was correctly
  /// checked against the uid. That asymmetry is a real defect: when the marker
  /// names ANOTHER account, the legacy folder and key are demonstrably that
  /// account's, and deleting your own account must not take their photos with
  /// it — the same rule as the exact-key match on `profile.sensitive.{uid}`.
  ///
  /// When the marker is UNSET nobody has claimed the data and it is genuinely
  /// ambiguous. It is erased, and that is a deliberate tie-break rather than
  /// an oversight: the key and the blobs have to travel together (removing the
  /// plaintext key while leaving the ciphertext gives the other account
  /// nothing but junk it can never open), and between failing this user's
  /// deletion promise and possibly erasing an un-migrated stranger's photos on
  /// a shared phone, the promise wins. The residual window is the same one
  /// `photo_directory.dart` states for adoption, and it closes the first time
  /// anyone opens the Photos tab.
  static bool _legacyIsMine(String? marker, String uid) =>
      marker == null || marker == uid;

  /// Deliberately KEPT: `settings.language` and `settings.theme_mode`. They
  /// describe how this phone should look, not who was signed in, and wiping
  /// them would drop a Russian user back to an English login screen as a side
  /// effect of deleting an account. `settings.notifications_enabled` is kept
  /// for the same reason — the OS-level permission it mirrors is not revoked
  /// by an account deletion either, and a mismatch between the two is a worse
  /// state than a stale toggle.
  static const kept = <String>[
    'settings.language',
    'settings.theme_mode',
    'settings.notifications_enabled',
  ];

  @override
  Future<void> wipe(String uid) async {
    final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();

    final marker = prefs.getString(kLegacyPhotoMigrationMarker);
    final legacyIsMine = _legacyIsMine(marker, uid);

    final personalKeys = {
      ..._personalKeys,
      'profile.sensitive.$uid',
      // The unreadable-blob copy kept by PrefsSensitiveStore (CR-07): raw
      // health text under a separate key, so it must be erased with the rest.
      'profile.sensitive.corrupt.$uid',
      // Per-uid photo consent record (progress_photos/data/photo_consent.dart).
      'progress_photos.consent.v1.$uid',
      // Per-uid scan reminder toggle (progress_photos/scan/scan_reminder.dart).
      // The encrypted scan sidecars live under the per-uid photo directory
      // deleted below, so they need no entry of their own.
      'progress_photos.scan_reminder.v1.$uid',
      // Per-uid training-context answer (training_context/state/training_context_providers.dart).
      'training_context.v1.$uid',
      if (legacyIsMine) _legacyPhotoKey,
      // Only when it names THIS user: it holds a uid, and clearing someone
      // else's would re-arm a migration that has already happened.
      if (marker == uid) kLegacyPhotoMigrationMarker,
    };

    // Guarded separately from the directory below, and deliberately so: a
    // platform-channel hiccup on one `remove` used to abort this method before
    // the photos were touched at all, which meant the LARGER leak was the one
    // that survived the smaller failure. Each half now runs regardless of the
    // other.
    // Per key, and `remove` reports failure by returning false rather than
    // throwing: one failed key used to skip every key after it, and a false
    // was read as success. The uid is masked so the names are safe to log.
    final failed = <String>[];
    for (final key in prefs.getKeys().toList()) {
      final personal =
          personalKeys.contains(key) || _personalPrefixes.any(key.startsWith);
      if (!personal) continue;
      try {
        if (!await prefs.remove(key)) failed.add(key.replaceAll(uid, '<uid>'));
      } catch (e) {
        failed.add(key.replaceAll(uid, '<uid>'));
        debugPrint('local data wipe: could not clear a preference: $e');
      }
    }

    try {
      final dir = _injectedDir ?? await getApplicationDocumentsDirectory();
      final root = Directory('${dir.path}/progress_photos');
      final mine = Directory('${root.path}/$uid');
      if (await mine.exists()) {
        await mine.delete(recursive: true);
      }
      // Loose `index.json` / `*.bin` directly under the root are pre-A2-sec
      // leftovers no account has adopted. Erased on exactly the same condition
      // as the legacy key above, and never on a different one: the key and the
      // ciphertext it opens must travel together, or the survivor is junk.
      if (legacyIsMine) await _deleteLooseLegacyFiles(root);
    } catch (e) {
      // A locked or missing directory must not turn a completed server-side
      // deletion into an error the user sees as "your account was not
      // deleted". Logged, not thrown -- same contract as the sign-out step in
      // the caller.
      // Type only: the exception text carries the uid-named photo path.
      debugPrint('local data wipe: could not delete progress photos: ${e.runtimeType}');
      failed.add('progress_photos');
    }

    // The envelopes are gone; the key that opened them must not outlive them
    // in the Keystore. Best-effort by the same contract as everything else
    // here — it already unlocks nothing.
    try {
      await _forgetPhotoKey(uid);
    } catch (e) {
      debugPrint('local data wipe: could not forget photo key: ${e.runtimeType}');
      failed.add('photo_key');
    }

    // Developer coach recordings (joint angles + timestamps only, debug and
    // profile builds): `<docs>/coach_recordings/<uid>/`. Its own try so a
    // failure here neither skips nor is skipped by the photo step.
    try {
      final dir = _injectedDir ?? await getApplicationDocumentsDirectory();
      final recordings = Directory('${dir.path}/coach_recordings/$uid');
      if (await recordings.exists()) await recordings.delete(recursive: true);
    } catch (e) {
      debugPrint(
          'local data wipe: could not delete coach recordings: ${e.runtimeType}');
      failed.add('coach_recordings');
    }

    // The on-phone scan history (`<docs>/scan_history/<uid>/`): every scanned
    // photo, the model's raw answers and the user's ratings. Its own try, like
    // the coach recordings, so it neither skips nor is skipped by the others.
    try {
      final dir = _injectedDir ?? await getApplicationDocumentsDirectory();
      final history = Directory('${dir.path}/$kScanHistoryDir/$uid');
      if (await history.exists()) await history.delete(recursive: true);
    } catch (e) {
      debugPrint(
          'local data wipe: could not delete scan history: ${e.runtimeType}');
      failed.add('scan_history');
    }

    // Every step has run by now. The caller logs this and still treats the
    // account as deleted; what it must not do is believe the device is clean.
    if (failed.isNotEmpty) throw LocalWipeIncomplete(failed);
  }

  Future<void> _deleteLooseLegacyFiles(Directory root) async {
    if (!await root.exists()) return;
    await for (final entity in root.list()) {
      if (entity is! File) continue;
      final name = entity.uri.pathSegments.last;
      if (name == 'index.json' || name.endsWith('.bin')) {
        await entity.delete();
      }
    }
  }
}

/// Test double: records what it was asked to wipe and touches nothing.
class RecordingLocalDataWipe implements LocalDataWipe {
  final List<String> wiped = [];

  @override
  Future<void> wipe(String uid) async => wiped.add(uid);
}
