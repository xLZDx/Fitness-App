import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/data/photo_encryption.dart';

void main() {
  group('AesPhotoCipher', () {
    test('encrypt → decrypt round-trips arbitrary bytes', () {
      final key = AesPhotoCipher.newKey();
      final cipher = AesPhotoCipher(key);
      final plain = Uint8List.fromList(
          List.generate(1024, (i) => (i * 31) % 256));
      final env = cipher.encrypt(plain);
      final back = cipher.decrypt(env);
      expect(back, plain);
    });

    test('wrong key fails decryption', () {
      final cipher = AesPhotoCipher(AesPhotoCipher.newKey());
      final imposter = AesPhotoCipher(AesPhotoCipher.newKey());
      final env = cipher.encrypt(Uint8List.fromList([1, 2, 3, 4, 5]));
      expect(() => imposter.decrypt(env), throwsA(isA<Object>()));
    });

    test('envelope serialises/deserialises', () {
      final key = AesPhotoCipher.newKey();
      final cipher = AesPhotoCipher(key);
      final plain = Uint8List.fromList([10, 20, 30, 40]);
      final env = cipher.encrypt(plain);
      final restored = PhotoEnvelope.fromBytes(env.toBytes());
      expect(cipher.decrypt(restored), plain);
    });

    test('asserts on wrong key length', () {
      expect(
        () => AesPhotoCipher(Uint8List(16)),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fingerprint is stable + 16 hex chars', () {
      final key = AesPhotoCipher.newKey();
      final f1 = AesPhotoCipher(key).fingerprint();
      final f2 = AesPhotoCipher(key).fingerprint();
      expect(f1, f2);
      expect(f1.length, 16);
    });
  });
}
