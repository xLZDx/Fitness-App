import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;
import 'package:encrypt/encrypt.dart' as enc;

import 'photo_encryption.dart';

/// Production [PhotoCipher] backed by AES-256-GCM (via `package:encrypt`,
/// which wraps PointyCastle).
///
/// Compared with the [XorPhotoCipher] used in tests:
///   - Confidentiality: real AES-256.
///   - Integrity: GCM tag detects tampering.
///   - Performance: hardware-accelerated on most ARM64 devices.
///
/// Threat model is still "casual server-side reader / well-intentioned
/// engineer pulling the bucket." For state-level adversaries the user
/// should not put progress photos on any cloud, encrypted or not.
class AesPhotoCipher implements PhotoCipher {
  AesPhotoCipher(this._key)
      : assert(_key.length == 32, 'AES-256 needs a 32-byte key');

  final Uint8List _key;
  static final _rng = math.Random.secure();

  @override
  PhotoEnvelope encrypt(Uint8List plaintext) {
    final iv = enc.IV.fromLength(12);
    // package:encrypt's AES-GCM wraps PointyCastle's GCM mode and
    // returns ciphertext+tag concatenated. We pull them apart so the
    // envelope's tag/iv/ciphertext fields stay distinct (matches the
    // XOR test impl's shape).
    final cipher = enc.Encrypter(enc.AES(
      enc.Key(_key),
      mode: enc.AESMode.gcm,
    ));
    final encrypted = cipher.encryptBytes(plaintext, iv: iv);
    final all = encrypted.bytes;
    // GCM tag is the last 16 bytes by spec.
    if (all.length < 16) {
      throw StateError('AES-GCM output unexpectedly short.');
    }
    final tag = Uint8List.fromList(all.sublist(all.length - 16));
    final ct = Uint8List.fromList(all.sublist(0, all.length - 16));
    return PhotoEnvelope(
      cipherText: ct,
      iv: Uint8List.fromList(iv.bytes),
      tag: tag,
    );
  }

  @override
  Uint8List decrypt(PhotoEnvelope envelope) {
    if (envelope.tag.length != 16) {
      throw StateError('AES-GCM tag must be 16 bytes.');
    }
    final cipher = enc.Encrypter(enc.AES(
      enc.Key(_key),
      mode: enc.AESMode.gcm,
    ));
    final combined = Uint8List.fromList(
      [...envelope.cipherText, ...envelope.tag],
    );
    final out = cipher.decryptBytes(
      enc.Encrypted(combined),
      iv: enc.IV(envelope.iv),
    );
    return Uint8List.fromList(out);
  }

  @override
  String fingerprint() {
    return crypto.sha256
        .convert(_key)
        .bytes
        .sublist(0, 8)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// Generate a fresh 32-byte key suitable for [AesPhotoCipher].
  static Uint8List newKey() {
    return Uint8List.fromList(
      List<int>.generate(32, (_) => _rng.nextInt(256)),
    );
  }
}
