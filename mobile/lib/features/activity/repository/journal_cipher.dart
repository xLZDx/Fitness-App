/// Encryption at rest for `streams.bin` and the secure-storage key abstraction
/// (S02 design 3.4, 3.5; GPS-PRIV-084; test plan I07, I24).
///
/// Pattern: `progress_photos/data/aes_photo_cipher.dart` (AES-256-GCM through
/// `package:encrypt`) and `photo_key_store.dart` (a secure-storage seam with
/// three outcomes: absent, unreadable, corrupt). The seam is re-declared here
/// instead of importing the photo feature so the two features stay independent.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:encrypt/encrypt.dart' as enc;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// The sealed bytes could not be opened: wrong key, a flipped byte (GCM tag
/// mismatch), truncation or an unknown format.
class JournalDecryptFailure implements Exception {
  const JournalDecryptFailure(this.reason);

  final String reason;

  @override
  String toString() => 'JournalDecryptFailure($reason)';
}

abstract class JournalCipher {
  /// Encrypts [plain]; every call uses a fresh random IV.
  Uint8List seal(Uint8List plain);

  /// Decrypts bytes produced by [seal]; throws [JournalDecryptFailure].
  Uint8List open(Uint8List sealed);
}

/// AES-256-GCM. Layout: 4-byte magic `AJS1`, 12-byte IV, ciphertext and the
/// 16-byte tag. The plaintext is never present in the output (no coordinate
/// text or float bytes at rest).
class AesGcmJournalCipher implements JournalCipher {
  AesGcmJournalCipher(this._key)
      : assert(_key.length == 32, 'AES-256 needs a 32-byte key');

  static const List<int> magic = [0x41, 0x4A, 0x53, 0x31]; // "AJS1"
  static const int _ivLength = 12;
  static const int _tagLength = 16;

  final Uint8List _key;

  enc.Encrypter get _encrypter =>
      enc.Encrypter(enc.AES(enc.Key(_key), mode: enc.AESMode.gcm));

  @override
  Uint8List seal(Uint8List plain) {
    final iv = enc.IV.fromSecureRandom(_ivLength);
    final sealed = _encrypter.encryptBytes(plain, iv: iv).bytes;
    return Uint8List.fromList([...magic, ...iv.bytes, ...sealed]);
  }

  @override
  Uint8List open(Uint8List sealed) {
    if (sealed.length < magic.length + _ivLength + _tagLength) {
      throw const JournalDecryptFailure('too short');
    }
    for (var i = 0; i < magic.length; i++) {
      if (sealed[i] != magic[i]) throw const JournalDecryptFailure('bad magic');
    }
    try {
      final iv = enc.IV(
          Uint8List.fromList(sealed.sublist(magic.length, magic.length + _ivLength)));
      final body = Uint8List.fromList(sealed.sublist(magic.length + _ivLength));
      return Uint8List.fromList(_encrypter.decryptBytes(enc.Encrypted(body), iv: iv));
    } catch (e) {
      throw JournalDecryptFailure('authentication failed: ${e.runtimeType}');
    }
  }
}

/// Where the journal key lives. Three outcomes, never collapsed (the photo
/// store learned this the hard way): [loadKey] returns null when there is no
/// usable key (absent or corrupt), THROWS when the platform store would not
/// answer (transient; a new key must not be minted then).
abstract class JournalKeyProvider {
  Future<Uint8List?> loadKey();

  /// The stored key, or a freshly minted one when none is usable. Throws when
  /// the store is unreadable.
  Future<Uint8List> loadOrCreateKey();

  /// Deletes the key (wipe, account deletion). Best effort.
  Future<void> forget();
}

/// The three operations the key provider needs from platform secure storage.
abstract class JournalSecureStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

class PlatformJournalSecureStorage implements JournalSecureStorage {
  const PlatformJournalSecureStorage([
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

class SecureStorageJournalKeyProvider implements JournalKeyProvider {
  /// [scopeId] (the account scope of an account-scoped journal) is appended to
  /// the key name so each account's journal has its own key. Null keeps the
  /// original single key name.
  SecureStorageJournalKeyProvider({JournalSecureStorage? storage, String? scopeId})
      : _storage = storage ?? const PlatformJournalSecureStorage(),
        keyNameInUse = scopeId == null ? keyName : '$keyName.$scopeId';

  /// Base key name. Without a scope there is one key per install.
  static const String keyName = 'activity_journal.key.v1';

  /// The secure-storage key name this instance reads and writes.
  final String keyNameInUse;

  final JournalSecureStorage _storage;
  Uint8List? _cached;

  Uint8List? _decode(String? raw) {
    if (raw == null) return null;
    try {
      final key = base64Decode(raw);
      return key.length == 32 ? Uint8List.fromList(key) : null;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> loadKey() async {
    final cached = _cached;
    if (cached != null) return cached;
    final key = _decode(await _storage.read(keyNameInUse));
    _cached = key;
    return key;
  }

  @override
  Future<Uint8List> loadOrCreateKey() async {
    final existing = await loadKey();
    if (existing != null) return existing;
    final rng = math.Random.secure();
    final fresh = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
    await _storage.write(keyNameInUse,base64Encode(fresh));
    _cached = fresh;
    return fresh;
  }

  @override
  Future<void> forget() async {
    _cached = null;
    try {
      await _storage.delete(keyNameInUse);
    } catch (_) {
      // Best effort: the data it protected is deleted first.
    }
  }
}

/// Test double and fallback: holds the key in memory.
class InMemoryJournalKeyProvider implements JournalKeyProvider {
  InMemoryJournalKeyProvider([this._key]);

  Uint8List? _key;

  @override
  Future<Uint8List?> loadKey() async => _key;

  @override
  Future<Uint8List> loadOrCreateKey() async {
    final existing = _key;
    if (existing != null) return existing;
    final rng = math.Random.secure();
    return _key = Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
  }

  @override
  Future<void> forget() async {
    _key = null;
  }
}
