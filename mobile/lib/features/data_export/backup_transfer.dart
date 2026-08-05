/// H2b — what actually travels in a transfer backup, and why it is so little.
///
/// The obvious answer is "everything", and it is wrong. Profile, workout
/// history and schedule all live on the server and come back on their own the
/// moment the user signs in on the new phone. Putting them in the backup would
/// make the file large enough to need a file picker, and would restore data
/// that is already there — with the added risk of writing a stale copy over a
/// newer one.
///
/// What does NOT come back is the half H1a moved onto the device: the health
/// questionnaire, plus smoking and alcohol. That is the entire loss a reinstall
/// causes, so that is the entire backup.
///
/// The consequence is a pleasant one. A filled questionnaire is a few hundred
/// bytes; encrypted and base64'd it is roughly a thousand characters — the size
/// of a long recovery code. It can be shared as a file or simply pasted, which
/// is why restore needs no file-picker dependency and works between Android and
/// iOS, which Android's own Auto Backup does not.
///
/// The full, human-readable GDPR export is a different feature with a different
/// purpose and stays exactly as it was: plain JSON, everything, no passphrase.
/// Encrypting that one would have made a data-portability export unreadable
/// without a secret, which is the opposite of portable.
library;

import 'dart:convert';

import '../profile/data/sensitive_profile.dart';

/// Identifies the payload inside the envelope, so a future backup that carries
/// something else can be told apart after decryption rather than misread.
const String kTransferKind = 'sensitive-profile';

/// Raised when the file decrypts but is not a transfer payload this app knows.
class TransferPayloadException implements Exception {
  const TransferPayloadException(this.message);
  final String message;
  @override
  String toString() => 'TransferPayloadException: $message';
}

String buildTransferPayload(SensitiveProfile sensitive) => jsonEncode({
      'kind': kTransferKind,
      'version': 1,
      'data': sensitive.toJson(),
    });

/// Parses what [buildTransferPayload] produced.
///
/// Separate from the envelope's own checks: by the time this runs the
/// passphrase has already been proven correct by the GCM tag, so anything
/// wrong here is a *content* problem and must not be reported as a passphrase
/// one.
SensitiveProfile readTransferPayload(String payload) {
  final Object? decoded;
  try {
    decoded = jsonDecode(payload);
  } on FormatException {
    throw const TransferPayloadException('backup contents are damaged');
  }
  if (decoded is! Map) {
    throw const TransferPayloadException('backup contents are damaged');
  }
  final j = Map<String, dynamic>.from(decoded);
  if (j['kind'] != kTransferKind) {
    throw const TransferPayloadException('not a profile backup');
  }
  if (j['version'] != 1) {
    throw TransferPayloadException(
      'made by a newer version (${j['version']})',
    );
  }
  final data = j['data'];
  if (data is! Map) {
    throw const TransferPayloadException('backup contents are damaged');
  }
  return SensitiveProfile.fromJson(Map<String, dynamic>.from(data));
}
