/// H2 — an encrypted backup a user can carry to another device.
///
/// ## Why this is not the device key
///
/// H1a moved the health questionnaire onto the phone, which bought a real
/// benefit and charged a real price: a reinstall or a second device starts
/// with an empty profile, and the contraindication filter forgets every
/// injury. This is the way back.
///
/// A backup meant to be *carried* cannot be encrypted with a device key, by
/// definition: the whole point is that it opens on a phone which does not have
/// that key. So the key comes from something the user carries instead — a
/// passphrase, stretched with PBKDF2.
///
/// The consequence has to be said out loud on the screen that creates one,
/// before the button, not in a help page: **a forgotten passphrase is a lost
/// backup.** There is no recovery path and there must not be one; an operator
/// who can open a user's backup is an operator who is storing their health
/// data again, one indirection further away.
///
/// ## Why PBKDF2 and not Argon2
///
/// Argon2id is the better function and it is not available without adding a
/// dependency. PBKDF2-HMAC-SHA256 is buildable on `package:crypto`, which is
/// already a direct dependency, and at [kDefaultIterations] it is what OWASP
/// currently recommends for exactly this construction. The threat here is an
/// attacker who has the file and is guessing passphrases offline; iteration
/// count is what makes that expensive, and this is the honest version of "we
/// used what we could audit".
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as crypto;

import '../progress_photos/data/aes_photo_cipher.dart';
import '../progress_photos/data/photo_encryption.dart';

/// OWASP's current floor for PBKDF2-HMAC-SHA256.
///
/// Costs roughly a second of pure-Dart work on a mid-range phone, which is why
/// callers should run [encryptBackup] / [decryptBackup] off the UI isolate. A
/// second, once, on a deliberate action is the right trade against making an
/// offline guessing attack a thousand times cheaper.
const int kDefaultIterations = 210000;

/// Marks the file as ours before anything tries to decrypt it, so a user who
/// picked the wrong file is told that, rather than being told their passphrase
/// is wrong.
const String kBackupFormat = 'fitness-app-backup';

/// Raised when the file is not one of ours, or is truncated.
class BackupFormatException implements Exception {
  const BackupFormatException(this.message);
  final String message;
  @override
  String toString() => 'BackupFormatException: $message';
}

/// Raised when the passphrase does not open the file.
///
/// Distinct from [BackupFormatException] because the two need different
/// sentences on screen: one is "try again", the other is "this is not the
/// right file". AES-GCM's tag is what tells them apart — a wrong key fails
/// authentication rather than producing garbage, which is the property that
/// makes this distinction trustworthy at all.
class BackupPassphraseException implements Exception {
  const BackupPassphraseException();
  @override
  String toString() => 'BackupPassphraseException';
}

final _rng = math.Random.secure();

Uint8List _randomBytes(int n) =>
    Uint8List.fromList(List<int>.generate(n, (_) => _rng.nextInt(256)));

/// PBKDF2-HMAC-SHA256, per RFC 8018.
///
/// Written out rather than pulled from a package because the only Dart
/// implementation available here would be PointyCastle's, reached as a
/// transitive dependency of `package:encrypt` — depending on a package the
/// pubspec does not name is how a build breaks on an unrelated upgrade.
Uint8List pbkdf2({
  required List<int> password,
  required List<int> salt,
  required int iterations,
  int keyLength = 32,
}) {
  if (iterations < 1) {
    throw ArgumentError.value(iterations, 'iterations', 'must be >= 1');
  }
  final hmac = crypto.Hmac(crypto.sha256, password);
  final out = Uint8List(keyLength);
  var offset = 0;
  var block = 1;
  while (offset < keyLength) {
    final chunk = _block(hmac, salt, iterations, block);
    final take = math.min(chunk.length, keyLength - offset);
    out.setRange(offset, offset + take, chunk);
    offset += take;
    block++;
  }
  return out;
}

List<int> _block(crypto.Hmac hmac, List<int> salt, int iterations, int index) {
  var u = hmac
      .convert(<int>[
        ...salt,
        (index >> 24) & 0xff,
        (index >> 16) & 0xff,
        (index >> 8) & 0xff,
        index & 0xff,
      ])
      .bytes;
  final acc = List<int>.from(u);
  for (var i = 1; i < iterations; i++) {
    u = hmac.convert(u).bytes;
    for (var j = 0; j < acc.length; j++) {
      acc[j] ^= u[j];
    }
  }
  return acc;
}

/// Wraps [plaintext] into a self-describing, passphrase-encrypted envelope.
///
/// The envelope is JSON with base64 fields rather than a packed binary blob:
/// it survives being pasted into a message or a cloud drive that mangles
/// binary, and a user can open it in a text editor and satisfy themselves that
/// it is opaque. Everything needed to decrypt except the passphrase is in the
/// file, including the iteration count — a backup made today must still open
/// after the constant is raised.
String encryptBackup({
  required String plaintext,
  required String passphrase,
  int iterations = kDefaultIterations,
}) {
  if (passphrase.isEmpty) {
    throw ArgumentError.value(passphrase, 'passphrase', 'must not be empty');
  }
  final salt = _randomBytes(16);
  final key = pbkdf2(
    password: utf8.encode(passphrase),
    salt: salt,
    iterations: iterations,
  );
  final envelope =
      AesPhotoCipher(key).encrypt(Uint8List.fromList(utf8.encode(plaintext)));
  return const JsonEncoder.withIndent('  ').convert({
    'format': kBackupFormat,
    'version': 1,
    'kdf': {
      'name': 'PBKDF2-HMAC-SHA256',
      'iterations': iterations,
      'salt': base64Encode(salt),
    },
    'cipher': 'AES-256-GCM',
    'iv': base64Encode(envelope.iv),
    'tag': base64Encode(envelope.tag),
    'payload': base64Encode(envelope.cipherText),
  });
}

/// Reverses [encryptBackup]. Throws [BackupFormatException] for a file that is
/// not one of ours and [BackupPassphraseException] for the wrong passphrase.
String decryptBackup({
  required String envelopeJson,
  required String passphrase,
}) {
  final Map<String, dynamic> j;
  try {
    final decoded = jsonDecode(envelopeJson);
    if (decoded is! Map) {
      throw const BackupFormatException('not a backup file');
    }
    j = Map<String, dynamic>.from(decoded);
  } on FormatException {
    throw const BackupFormatException('not a backup file');
  }

  if (j['format'] != kBackupFormat) {
    throw const BackupFormatException('not a backup file');
  }
  if (j['version'] != 1) {
    // Forward, not backward: a file from a newer app must say so plainly
    // rather than fail as a passphrase problem and send the user round in
    // circles typing it again.
    throw BackupFormatException('made by a newer version (${j['version']})');
  }

  final kdf = Map<String, dynamic>.from((j['kdf'] as Map?) ?? const {});
  final iterations = kdf['iterations'];
  final saltRaw = kdf['salt'];
  if (iterations is! int || iterations < 1 || saltRaw is! String) {
    throw const BackupFormatException('backup is missing its key settings');
  }

  final Uint8List salt, iv, tag, payload;
  try {
    salt = base64Decode(saltRaw);
    iv = base64Decode(j['iv'] as String);
    tag = base64Decode(j['tag'] as String);
    payload = base64Decode(j['payload'] as String);
  } catch (_) {
    throw const BackupFormatException('backup file is damaged');
  }

  final key = pbkdf2(
    password: utf8.encode(passphrase),
    salt: salt,
    iterations: iterations,
  );
  final Uint8List clear;
  try {
    clear = AesPhotoCipher(key).decrypt(
      PhotoEnvelope(cipherText: payload, iv: iv, tag: tag),
    );
  } catch (_) {
    // GCM authentication failed. That is overwhelmingly a wrong passphrase;
    // it is also what a tampered file looks like, and the two are not
    // distinguishable by design — the tag proves both at once.
    throw const BackupPassphraseException();
  }
  try {
    return utf8.decode(clear);
  } on FormatException {
    throw const BackupFormatException('backup file is damaged');
  }
}
