import 'dart:typed_data';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aes_photo_cipher.dart';
import 'photo_encryption.dart';

/// Where the photo encryption key lives between launches.
///
/// A2-sec moved it. The previous implementation (`PrefsPhotoKeyStore`, kept
/// below only as the thing migrated FROM) wrote the key base64-encoded into
/// SharedPreferences, which on Android is a plain XML file in the app's data
/// dir: readable by anything running as the app's uid, by root, and by anyone
/// holding a backup of the data partition. The key sat next to the ciphertext
/// it unlocks, which made the encryption a formality against the attacker it
/// was supposed to stop.
///
/// [SecurePhotoKeyStore] puts it in `flutter_secure_storage`: on Android a
/// Keystore-held master key wrapping the entry, on iOS the Keychain. The
/// defaults are used deliberately — the `encryptedSharedPreferences: true`
/// Android option that would have been the obvious thing to pass is deprecated
/// (Jetpack Security is discontinued) and the plugin now ignores it, migrating
/// existing entries to its own ciphers on first access.
///
/// The key material is then held by the OS, not by a file the app can read
/// back on its own terms.
///
/// Be precise about what that does and does not buy, because the UI copy has
/// to match it (`profileEncryptedOnDevice`, corrected in this same gate):
///
///   - It DOES stop a photo sitting on disk as a readable JPEG, and it DOES
///     stop the key travelling in a filesystem backup.
///   - It does NOT defend against an attacker with code execution as this app
///     on an unlocked device: they can ask the Keystore to decrypt, same as
///     the app does. That is the ceiling of any client-side scheme, and it is
///     why the copy says "encrypted on your device" and not "end-to-end".
abstract class PhotoKeyStore {
  /// Returns the persisted key, generating and storing one on first call.
  Future<Uint8List> loadOrCreate();
}

/// The key for ONE account, in platform secure storage.
///
/// Scoped by uid for the same reason the photo directory is: two people
/// sharing a phone were sharing one key and one folder, so the second to sign
/// in inherited the first one's timeline. An account's key is now
/// `progress_photos.key.v2.<uid>` and unlocks only that account's envelopes.
class SecurePhotoKeyStore implements PhotoKeyStore {
  SecurePhotoKeyStore({
    required this.uid,
    FlutterSecureStorage? storage,
    SharedPreferences? prefs,
  })  : _storage = storage ?? const FlutterSecureStorage(),
        _injectedPrefs = prefs;

  /// The account this key belongs to.
  final String uid;

  /// The pre-A2-sec key name. One per install, no uid — the bug itself.
  static const legacyPrefsKey = 'progress_photos.key.v1';

  static String secureKeyFor(String uid) => 'progress_photos.key.v2.$uid';

  final FlutterSecureStorage _storage;
  final SharedPreferences? _injectedPrefs;
  Uint8List? _cached;

  String get _name => secureKeyFor(uid);

  @override
  Future<Uint8List> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    final existing = await _readValid(_name);
    if (existing != null) return _cache(existing);

    // Nothing yet under this uid. Before minting a new key — which would make
    // every already-captured photo permanently unreadable — look for the
    // single install-wide key A2-sec replaced, and adopt it.
    final migrated = await _adoptLegacyKey();
    if (migrated != null) return _cache(migrated);

    final fresh = AesPhotoCipher.newKey();
    await _storage.write(key: _name, value: keyToBase64(fresh));
    return _cache(fresh);
  }

  Uint8List _cache(Uint8List key) {
    _cached = key;
    return key;
  }

  /// Reads and validates one secure entry, or null.
  Future<Uint8List?> _readValid(String name) async {
    String? raw;
    try {
      raw = await _storage.read(key: name);
    } catch (e) {
      // A Keystore that will not open is not a reason to lose the photos tab
      // forever, but it IS a reason not to silently mint a second key and
      // orphan the blobs. Surfaced to the caller as "no key", which mints one
      // — the same outcome as a first run, and the fingerprint check in
      // PhotoStore.read then names the mismatch instead of returning garbage.
      return null;
    }
    if (raw == null) return null;
    final key = keyFromBase64(raw);
    // A key of the wrong length throws inside AesPhotoCipher's assert in debug
    // and produces garbage in release. Treat it as absent.
    return key.length == 32 ? key : null;
  }

  /// Moves the pre-A2-sec install-wide key into this account's secure slot.
  ///
  /// One-way and one-time: after the copy, the plaintext prefs entry is
  /// deleted, so the key stops being readable from the app's XML. Whoever
  /// signs in first after the upgrade inherits it, which is the one residual
  /// window of the old shared-key design — see `progress_photos_providers.dart`
  /// for why adopting is still better than the alternative, which is deleting
  /// a user's own photos to close a window that a single-tester beta has never
  /// been through.
  Future<Uint8List?> _adoptLegacyKey() async {
    final prefs = _injectedPrefs ?? await SharedPreferences.getInstance();
    final legacy = prefs.getString(legacyPrefsKey);
    if (legacy == null) return null;
    final key = keyFromBase64(legacy);
    if (key.length != 32) {
      await prefs.remove(legacyPrefsKey);
      return null;
    }
    await _storage.write(key: _name, value: keyToBase64(key));
    // Only after the secure copy is committed. The other order loses the key
    // outright if the process dies between the two, and with it every photo.
    await prefs.remove(legacyPrefsKey);
    return key;
  }

  /// Forgets this account's key. Called by the account-deletion wipe: the
  /// envelopes are deleted with the directory, and a key left behind in the
  /// Keystore is a dangling secret for data that no longer exists.
  static Future<void> forget(String uid, {FlutterSecureStorage? storage}) async {
    final store = storage ?? const FlutterSecureStorage();
    try {
      await store.delete(key: secureKeyFor(uid));
    } catch (_) {
      // Best effort. The blobs are already gone by the time this runs, so a
      // surviving key unlocks nothing — worth attempting, never worth
      // failing the deletion over.
    }
  }
}

/// The pre-A2-sec store. Retained so [SecurePhotoKeyStore] has something to
/// name in its migration and so the old key's location stays documented; it is
/// no longer wired into the app.
@Deprecated('Key moved to platform secure storage in A2-sec. '
    'Use SecurePhotoKeyStore.')
class PrefsPhotoKeyStore implements PhotoKeyStore {
  PrefsPhotoKeyStore({SharedPreferences? prefs}) : _injected = prefs;

  static const _prefsKey = SecurePhotoKeyStore.legacyPrefsKey;

  final SharedPreferences? _injected;
  Uint8List? _cached;

  @override
  Future<Uint8List> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;
    final prefs = _injected ?? await SharedPreferences.getInstance();
    final existing = prefs.getString(_prefsKey);
    if (existing != null) {
      final key = keyFromBase64(existing);
      if (key.length == 32) {
        _cached = key;
        return key;
      }
    }
    final fresh = AesPhotoCipher.newKey();
    await prefs.setString(_prefsKey, keyToBase64(fresh));
    _cached = fresh;
    return fresh;
  }
}

/// Test double. Holds the key in memory for the life of the instance.
class InMemoryPhotoKeyStore implements PhotoKeyStore {
  InMemoryPhotoKeyStore([Uint8List? key]) : _key = key ?? AesPhotoCipher.newKey();

  final Uint8List _key;

  @override
  Future<Uint8List> loadOrCreate() async => _key;
}
