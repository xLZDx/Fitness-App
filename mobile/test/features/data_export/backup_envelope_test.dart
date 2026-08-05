import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/data_export/backup_envelope.dart';

/// H2 — the encrypted backup that pays back what H1a charged.
///
/// Moving the health questionnaire onto the device cost the user their profile
/// on reinstall and on a second phone. This is the way back, and it is only
/// worth having if it is actually opaque without the passphrase and actually
/// opens with it.
///
/// Iteration counts here are deliberately tiny. The KDF is exercised for
/// correctness, not for cost — 210,000 rounds in a loop over a dozen tests
/// would add minutes to every run for no extra coverage. One test pins the
/// production constant so a fat-finger cannot lower it unnoticed.
void main() {
  const secret = 'correct horse battery staple';

  group('pbkdf2', () {
    /// RFC 6070 publishes vectors for PBKDF2-HMAC-SHA1; the SHA-256 vectors in
    /// common use come from the same test set, re-run. This is the widely
    /// reproduced one for ("password", "salt", 1) — it pins the construction
    /// itself: block index big-endian, and the first block taken whole.
    test('matches the published vector for one iteration', () {
      final out = pbkdf2(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 1,
      );
      expect(
        out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b',
      );
    });

    test('matches the published vector for two iterations', () {
      final out = pbkdf2(
        password: utf8.encode('password'),
        salt: utf8.encode('salt'),
        iterations: 2,
      );
      expect(
        out.map((b) => b.toRadixString(16).padLeft(2, '0')).join(),
        'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43',
      );
    });

    test('a different salt gives a different key', () {
      final a = pbkdf2(
          password: utf8.encode('p'), salt: const [1], iterations: 4);
      final b = pbkdf2(
          password: utf8.encode('p'), salt: const [2], iterations: 4);
      expect(a, isNot(equals(b)));
    });

    test('zero iterations is refused rather than silently weak', () {
      expect(
        () => pbkdf2(password: const [1], salt: const [2], iterations: 0),
        throwsArgumentError,
      );
    });
  });

  group('backup envelope', () {
    test('round-trips the payload', () {
      final sealed = encryptBackup(
        plaintext: '{"profile":{"health":{"medications":["ramipril"]}}}',
        passphrase: secret,
        iterations: 8,
      );
      final out = decryptBackup(envelopeJson: sealed, passphrase: secret);
      expect(out, contains('ramipril'));
    });

    /// The point of the whole feature. A file the user emails to themselves
    /// must not contain their medications in the clear.
    test('the payload is opaque in the file', () {
      final sealed = encryptBackup(
        plaintext: '{"medications":["ramipril"],"injuries":["knee"]}',
        passphrase: secret,
        iterations: 8,
      );
      expect(sealed, isNot(contains('ramipril')));
      expect(sealed, isNot(contains('knee')));
      expect(sealed, isNot(contains('medications')));
      // And the passphrase itself is nowhere in it.
      expect(sealed, isNot(contains(secret)));
    });

    test('a wrong passphrase is refused, not silently garbled', () {
      final sealed = encryptBackup(
        plaintext: 'payload',
        passphrase: secret,
        iterations: 8,
      );
      expect(
        () => decryptBackup(envelopeJson: sealed, passphrase: 'wrong'),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    /// Two files made from the same data with the same passphrase must differ,
    /// or an observer learns that the user's answers did not change between
    /// backups.
    test('the same input twice produces different files', () {
      final a = encryptBackup(
          plaintext: 'same', passphrase: secret, iterations: 8);
      final b = encryptBackup(
          plaintext: 'same', passphrase: secret, iterations: 8);
      expect(a, isNot(equals(b)));
      // Both still open.
      expect(decryptBackup(envelopeJson: a, passphrase: secret), 'same');
      expect(decryptBackup(envelopeJson: b, passphrase: secret), 'same');
    });

    /// A tampered file must fail closed. GCM's tag proves this; the test is
    /// here because a future swap to a mode without one would pass every other
    /// test in this file.
    test('a modified payload fails authentication', () {
      final sealed = encryptBackup(
          plaintext: 'payload', passphrase: secret, iterations: 8);
      final j = Map<String, dynamic>.from(jsonDecode(sealed) as Map);
      final bytes = base64Decode(j['payload'] as String);
      bytes[0] ^= 0xff;
      j['payload'] = base64Encode(bytes);

      expect(
        () => decryptBackup(envelopeJson: jsonEncode(j), passphrase: secret),
        throwsA(isA<BackupPassphraseException>()),
      );
    });

    /// "This is not the right file" and "your passphrase is wrong" need
    /// different sentences on screen; a user told the second when the first is
    /// true retypes a correct passphrase forever.
    test('a file that is not ours is reported as such', () {
      expect(
        () => decryptBackup(
            envelopeJson: '{"hello":"world"}', passphrase: secret),
        throwsA(isA<BackupFormatException>()),
      );
      expect(
        () => decryptBackup(envelopeJson: 'not json at all', passphrase: secret),
        throwsA(isA<BackupFormatException>()),
      );
    });

    test('a newer format version says so instead of blaming the passphrase',
        () {
      final sealed = encryptBackup(
          plaintext: 'payload', passphrase: secret, iterations: 8);
      final j = Map<String, dynamic>.from(jsonDecode(sealed) as Map);
      j['version'] = 2;
      expect(
        () => decryptBackup(envelopeJson: jsonEncode(j), passphrase: secret),
        throwsA(isA<BackupFormatException>()),
      );
    });

    /// The iteration count travels in the file, so raising the constant later
    /// must not orphan backups made today.
    test('opens a file whose iteration count differs from the current default',
        () {
      final sealed = encryptBackup(
          plaintext: 'payload', passphrase: secret, iterations: 5);
      final j = jsonDecode(sealed) as Map;
      expect((j['kdf'] as Map)['iterations'], 5);
      expect(decryptBackup(envelopeJson: sealed, passphrase: secret),
          'payload');
    });

    test('an empty passphrase is refused at creation', () {
      expect(
        () => encryptBackup(plaintext: 'x', passphrase: '', iterations: 8),
        throwsArgumentError,
      );
    });

    /// Pins the production cost parameter. Lowering it is a security change
    /// and has to be a deliberate one that comes past a failing test.
    test('the shipped iteration count is the OWASP floor', () {
      expect(kDefaultIterations, 210000);
    });
  });
}
