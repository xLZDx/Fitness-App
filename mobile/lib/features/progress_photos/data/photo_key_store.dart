import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'aes_photo_cipher.dart';
import 'photo_encryption.dart';

/// The platform key store is there but would not open.
///
/// Distinct from "this account has no key yet", and the distinction is the
/// whole point: the first is transient and must never cause a new key to be
/// written, because that overwrites the one every existing photo was encrypted
/// with. Surfaced instead of swallowed so the store fails to build for this
/// launch and the photos tab shows its demo state, which is recoverable.
class PhotoKeyUnavailable implements Exception {
  PhotoKeyUnavailable(this.keyName, this.cause);

  final String keyName;
  final Object cause;

  @override
  String toString() =>
      'PhotoKeyUnavailable($keyName): secure storage could not be read '
      '— $cause. No key was written; existing photos are untouched.';
}

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

/// The three operations this file needs from platform secure storage.
///
/// A seam, not indirection for its own sake: `FlutterSecureStorage` is a
/// concrete class over a method channel, so without it the key-loss paths the
/// Act gate found — a read that throws, a stored value that is not a key —
/// cannot be exercised by any test at all. That is how they shipped.
abstract class SecureKeyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// The real one.
class PlatformSecureKeyStorage implements SecureKeyStorage {
  const PlatformSecureKeyStorage([
    this._storage = const FlutterSecureStorage(),
  ]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
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
    SecureKeyStorage? storage,
    SharedPreferences? prefs,
  })  : _storage = storage ?? const PlatformSecureKeyStorage(),
        _injectedPrefs = prefs;

  /// The account this key belongs to.
  final String uid;

  /// The pre-A2-sec key name. One per install, no uid — the bug itself.
  static const legacyPrefsKey = 'progress_photos.key.v1';

  static String secureKeyFor(String uid) => 'progress_photos.key.v2.$uid';

  final SecureKeyStorage _storage;
  final SharedPreferences? _injectedPrefs;
  Uint8List? _cached;

  String get _name => secureKeyFor(uid);

  @override
  Future<Uint8List> loadOrCreate() async {
    final cached = _cached;
    if (cached != null) return cached;

    // Throws [PhotoKeyUnavailable] rather than returning null when the store
    // is present but unreadable — see [_read] for why that distinction is
    // load-bearing.
    final existing = await _read(_name);
    if (existing != null) return _cache(existing);

    // Nothing yet under this uid. Before minting a new key — which would make
    // every already-captured photo permanently unreadable — look for the
    // single install-wide key A2-sec replaced, and adopt it.
    final migrated = await _adoptLegacyKey();
    if (migrated != null) return _cache(migrated);

    final fresh = AesPhotoCipher.newKey();
    await _storage.write(_name, keyToBase64(fresh));
    return _cache(fresh);
  }

  Uint8List _cache(Uint8List key) {
    _cached = key;
    return key;
  }

  /// One secure entry, or null when the account genuinely has no key yet.
  ///
  /// **Three outcomes, and collapsing any two of them destroys photos.** The
  /// first version of this method had two, and the Act gate on A2-sec caught
  /// it: a `read` that THREW returned null, the caller could not tell that
  /// from "never written", and so it minted a fresh key and wrote it over the
  /// alias whose read had just failed. A transient Keystore error — a real,
  /// documented failure mode, and one that leaves `write` working — silently
  /// destroyed the only key that could open every existing photo. The comment
  /// that stood here claimed the opposite of what the code did.
  ///
  ///   - **absent** (`raw == null`): nothing was ever written. Mint one.
  ///   - **unreadable** (`read` threw): a key may well be there. Throw
  ///     [PhotoKeyUnavailable] and let the store fail to build. The photos tab
  ///     falls back to the demo repository for this launch, which is
  ///     recoverable; overwriting the key is not.
  ///   - **corrupt** (present, but not 32 bytes): whatever wrote the blobs is
  ///     unrecoverable either way, so minting loses nothing that was not
  ///     already lost — and refusing forever would strand the user in demo
  ///     mode with no way out.
  Future<Uint8List?> _read(String name) async {
    String? raw;
    try {
      raw = await _storage.read(name);
    } catch (e) {
      throw PhotoKeyUnavailable(name, e);
    }
    if (raw == null) return null;

    Uint8List key;
    try {
      key = keyFromBase64(raw);
    } catch (e) {
      // Corrupt, not unreadable: the value came back, it is simply not a key.
      // Same treatment as a wrong length below.
      debugPrint('progress photos: stored key for $name is not base64: $e');
      return null;
    }
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

    Uint8List key;
    try {
      key = keyFromBase64(legacy);
    } catch (e) {
      // Same class as a wrong length: the value is there and is not a key, so
      // nothing it could have opened is recoverable. Discard it rather than
      // let a FormatException out of a method whose caller is trying to build
      // the photos tab.
      debugPrint('progress photos: legacy key is not base64: $e');
      await prefs.remove(legacyPrefsKey);
      return null;
    }
    if (key.length != 32) {
      await prefs.remove(legacyPrefsKey);
      return null;
    }
    await _storage.write(_name, keyToBase64(key));
    // Only after the secure copy is committed. The other order loses the key
    // outright if the process dies between the two, and with it every photo.
    await prefs.remove(legacyPrefsKey);
    return key;
  }

  /// Forgets this account's key. Called by the account-deletion wipe: the
  /// envelopes are deleted with the directory, and a key left behind in the
  /// Keystore is a dangling secret for data that no longer exists.
  static Future<void> forget(String uid, {SecureKeyStorage? storage}) async {
    final store = storage ?? const PlatformSecureKeyStorage();
    try {
      await store.delete(secureKeyFor(uid));
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
