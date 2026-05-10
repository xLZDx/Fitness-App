import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/data/photo_encryption.dart';

void main() {
  group('XorPhotoCipher', () {
    test('encrypt → decrypt round-trip', () {
      final key = newRandomKey();
      final cipher = XorPhotoCipher(key);
      final plain = Uint8List.fromList(List.generate(256, (i) => i % 251));
      final env = cipher.encrypt(plain);
      final back = cipher.decrypt(env);
      expect(back, plain);
    });

    test('wrong key fails the tag check', () {
      final cipher = XorPhotoCipher(newRandomKey());
      final imposter = XorPhotoCipher(newRandomKey());
      final plain = Uint8List.fromList([1, 2, 3, 4, 5]);
      final env = cipher.encrypt(plain);
      expect(() => imposter.decrypt(env), throwsStateError);
    });

    test('envelope bytes round-trip', () {
      final cipher = XorPhotoCipher(newRandomKey());
      final plain = Uint8List.fromList([10, 20, 30]);
      final env = cipher.encrypt(plain);
      final bytes = env.toBytes();
      final restored = PhotoEnvelope.fromBytes(bytes);
      expect(cipher.decrypt(restored), plain);
    });

    test('fingerprint stable across instances of same key', () {
      final key = newRandomKey();
      final a = XorPhotoCipher(key).fingerprint();
      final b = XorPhotoCipher(key).fingerprint();
      expect(a, b);
      expect(a.length, 16);
    });
  });

  group('keyToBase64 / keyFromBase64', () {
    test('lossless round-trip', () {
      final key = newRandomKey();
      final back = keyFromBase64(keyToBase64(key));
      expect(back, key);
    });
  });
}
