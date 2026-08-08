import 'dart:typed_data';

import 'package:shared_preferences/shared_preferences.dart';

import 'aes_photo_cipher.dart';
import 'photo_encryption.dart';

/// Where the photo encryption key lives between launches.
///
/// **This abstraction exists because the current implementation is the wrong
/// one and we intend to replace it.** [PrefsPhotoKeyStore] puts the key in
/// SharedPreferences, which on Android is a plain XML file in the app's data
/// dir. That is readable by anything running as the app's uid and by anyone
/// with root or a backup of the data partition — see the comment in
/// `progress_photos_page.dart`, which already called this out.
///
/// So be precise about what shipping it does and does not buy:
///
///   - It DOES stop a photo from sitting on disk as a readable JPEG. A file
///     manager, a gallery scanner, another app with storage permission, and
///     any future cloud-backup path all see AES-256-GCM ciphertext.
///   - It does NOT defend against an attacker who already has code execution
///     as this app, or root. Such an attacker reads the key and then the
///     photos.
///
/// The right home is the Android Keystore / iOS Keychain, which means a new
/// native dependency. That was deliberately not added in the same gate that
/// introduced on-disk photos: an unverified native plugin would put every
/// later gate's build at risk, and the swap is one class behind this
/// interface. Do it as its own gate, with a device build to prove it.
abstract class PhotoKeyStore {
  /// Returns the persisted key, generating and storing one on first call.
  Future<Uint8List> loadOrCreate();
}

class PrefsPhotoKeyStore implements PhotoKeyStore {
  PrefsPhotoKeyStore({SharedPreferences? prefs}) : _injected = prefs;

  static const _prefsKey = 'progress_photos.key.v1';

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
      // A key of the wrong length would throw inside AesPhotoCipher's assert
      // in debug and produce garbage in release. Treat it as absent and mint
      // a new one: the old photos are unreadable either way, and crashing the
      // photos tab forever is worse than losing access to blobs whose key is
      // already corrupt.
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
