import 'dart:convert';
import 'dart:typed_data';
import 'dart:math' as math;

import 'package:crypto/crypto.dart' as crypto;

/// AES-GCM-style envelope tagged for progress-photo blobs. We wrap the
/// `encrypt` package in a thin facade because we want to swap to the
/// platform's Secure Element (Android Keystore / iOS Keychain) when we
/// graduate from device-only keys later.
///
/// **Security note**: this is a privacy guarantee, not an audit-grade
/// crypto guarantee. The threat model is "casual server-side reader / a
/// well-intentioned engineer pulling the bucket"; not state-level
/// adversaries. Document this on the upload screen — important because
/// the About page promises *no data resale* (`aboutNoDataResaleEver`),
/// and that promise outlives S0b: it was never tied to the nonprofit
/// claim S0b removed, and it still has to hold.
class PhotoEnvelope {
  const PhotoEnvelope({
    required this.cipherText,
    required this.iv,
    required this.tag,
  });

  /// AES-GCM ciphertext. Length = plaintext length.
  final Uint8List cipherText;
  final Uint8List iv;

  /// AES-GCM authentication tag. 16 bytes.
  final Uint8List tag;

  Uint8List toBytes() {
    final out = BytesBuilder();
    out.add([1]); // version
    out.add([iv.length]);
    out.add(iv);
    out.add([tag.length]);
    out.add(tag);
    out.add(cipherText);
    return out.toBytes();
  }

  static PhotoEnvelope fromBytes(Uint8List raw) {
    if (raw.isEmpty || raw[0] != 1) {
      throw ArgumentError('Unsupported envelope version');
    }
    final ivLen = raw[1];
    final iv = raw.sublist(2, 2 + ivLen);
    final tagLen = raw[2 + ivLen];
    final tagStart = 3 + ivLen;
    final tag = raw.sublist(tagStart, tagStart + tagLen);
    final cipher = raw.sublist(tagStart + tagLen);
    return PhotoEnvelope(cipherText: cipher, iv: iv, tag: tag);
  }
}

abstract class PhotoCipher {
  PhotoEnvelope encrypt(Uint8List plaintext);
  Uint8List decrypt(PhotoEnvelope envelope);
  String fingerprint();
}

/// Test-only XOR cipher. Real implementations swap in AES-GCM via
/// `package:encrypt`. This stays in the codebase so unit tests don't
/// pull in native bindings.
class XorPhotoCipher implements PhotoCipher {
  XorPhotoCipher(this._key);
  final Uint8List _key;
  static final _rng = math.Random.secure();

  @override
  PhotoEnvelope encrypt(Uint8List plaintext) {
    final iv = Uint8List.fromList(
        List<int>.generate(12, (_) => _rng.nextInt(256)));
    final out = Uint8List(plaintext.length);
    for (var i = 0; i < plaintext.length; i++) {
      out[i] = plaintext[i] ^ _key[i % _key.length] ^ iv[i % iv.length];
    }
    final tag = Uint8List.fromList(
        crypto.sha256.convert([..._key, ...iv, ...out]).bytes.sublist(0, 16));
    return PhotoEnvelope(cipherText: out, iv: iv, tag: tag);
  }

  @override
  Uint8List decrypt(PhotoEnvelope envelope) {
    final expectTag = Uint8List.fromList(crypto.sha256
        .convert([..._key, ...envelope.iv, ...envelope.cipherText])
        .bytes
        .sublist(0, 16));
    if (!_constantTimeEq(expectTag, envelope.tag)) {
      throw StateError('Tag mismatch — wrong key or corrupted envelope.');
    }
    final out = Uint8List(envelope.cipherText.length);
    for (var i = 0; i < envelope.cipherText.length; i++) {
      out[i] = envelope.cipherText[i] ^
          _key[i % _key.length] ^
          envelope.iv[i % envelope.iv.length];
    }
    return out;
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
}

bool _constantTimeEq(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}

/// Random 32-byte key suitable for the cipher abstraction above.
Uint8List newRandomKey() {
  final rng = math.Random.secure();
  return Uint8List.fromList(List<int>.generate(32, (_) => rng.nextInt(256)));
}

/// Convenience for storing the key in SharedPreferences (a separate
/// adapter handles SecureStorage on real devices). Keys are short enough
/// to inline as base64.
String keyToBase64(Uint8List key) => base64Encode(key);
Uint8List keyFromBase64(String s) => Uint8List.fromList(base64Decode(s));
