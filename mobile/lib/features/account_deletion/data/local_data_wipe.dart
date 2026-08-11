import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../progress_photos/data/photo_directory.dart';
import '../../progress_photos/data/photo_key_store.dart';

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
  Future<void> wipe(String uid);
}

class DeviceLocalDataWipe implements LocalDataWipe {
  DeviceLocalDataWipe({SharedPreferences? prefs, Directory? documentsDir})
      : _injectedPrefs = prefs,
        _injectedDir = documentsDir;

  final SharedPreferences? _injectedPrefs;
  final Directory? _injectedDir;

  /// Keys that describe a PERSON. Everything under `moment.` is a counter
  /// about how this user has used the app, and `settings.tier_override` is a
  /// debug entitlement that must not outlive the account it was set for.
  ///
  /// The health blob is matched by its EXACT key, `profile.sensitive.{uid}`,
  /// not by the `profile.sensitive.` prefix. The prefix would also erase a
  /// different, still-existing account's blob on a shared phone — deleting
  /// someone else's health data as a side effect of deleting yours. Their own
  /// deletion is what removes theirs.
  /// Keys erased for every deletion, regardless of who else uses this phone.
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
    try {
      for (final key in prefs.getKeys().toList()) {
        final personal =
            personalKeys.contains(key) || _personalPrefixes.any(key.startsWith);
        if (personal) {
          await prefs.remove(key);
        }
      }
    } catch (e) {
      debugPrint('local data wipe: could not clear preferences: $e');
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
      debugPrint('local data wipe: could not delete progress photos: $e');
    }

    // The envelopes are gone; the key that opened them must not outlive them
    // in the Keystore. Best-effort by the same contract as everything else
    // here — it already unlocks nothing.
    await SecurePhotoKeyStore.forget(uid);
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
