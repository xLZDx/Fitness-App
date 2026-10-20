/// Bare, content-free error codes for the recorder (S04 design 10, S04-27).
///
/// Every `catch` in `recording/**` maps its exception to one of these first;
/// the code (and the runtime type name) is the only thing that may be logged or
/// reported. Pure Dart. Never builds a code from an exception message.
library;

import 'dart:async' show TimeoutException;

enum RecorderErrorCode {
  /// A frame or a file could not be decoded (format, length, CRC).
  decode,

  /// A frame failed authentication or decryption.
  decrypt,

  /// The journal key was unavailable.
  keyUnavailable,

  /// A file system operation failed.
  fileSystem,

  /// An operation timed out.
  timeout,

  /// An isolate failed or its result could not cross the boundary.
  isolate,

  /// A platform channel call failed (location, permission, battery).
  platform,

  /// An argument or state invariant was violated.
  invariant,

  /// Anything not recognised.
  unknown;

  /// The text that may appear in a log line.
  String get logName => name;
}

/// Maximum length of a type name kept in a log line.
const int kMaxLoggedTypeNameLength = 48;

/// Maps an error to a bare code by its type only; the message is never read.
RecorderErrorCode recorderErrorCodeOf(Object error) {
  if (error is FormatException) return RecorderErrorCode.decode;
  if (error is TimeoutException) return RecorderErrorCode.timeout;
  if (error is ArgumentError ||
      error is StateError ||
      error is UnsupportedError ||
      error is AssertionError ||
      error is TypeError) {
    return RecorderErrorCode.invariant;
  }
  // Types from other libraries are matched by name so this file stays free of
  // their imports (dart:io, services, journal layer).
  final type = safeTypeName(error);
  if (type.startsWith('FileSystemException') ||
      type.startsWith('PathAccessException') ||
      type.startsWith('PathNotFoundException') ||
      type.startsWith('PathExistsException') ||
      type.startsWith('OSError')) {
    return RecorderErrorCode.fileSystem;
  }
  if (type.startsWith('JournalKeyUnavailable')) {
    return RecorderErrorCode.keyUnavailable;
  }
  if (type.startsWith('JournalDecryptFailure') ||
      type.startsWith('SecretBoxAuthenticationError')) {
    return RecorderErrorCode.decrypt;
  }
  if (type.startsWith('RemoteError') ||
      type.startsWith('IsolateSpawnException') ||
      type.startsWith('ClosedException')) {
    return RecorderErrorCode.isolate;
  }
  if (type.startsWith('PlatformException') ||
      type.startsWith('MissingPluginException')) {
    return RecorderErrorCode.platform;
  }
  return RecorderErrorCode.unknown;
}

/// The runtime type name restricted to identifier characters, so even a hostile
/// `runtimeType` cannot carry free text into a log line.
String safeTypeName(Object error) {
  final raw = error.runtimeType.toString();
  final buffer = StringBuffer();
  for (final unit in raw.codeUnits) {
    final ok = (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x5F ||
        unit == 0x3C ||
        unit == 0x3E ||
        unit == 0x2C;
    if (ok) buffer.writeCharCode(unit);
    if (buffer.length >= kMaxLoggedTypeNameLength) break;
  }
  return buffer.toString();
}
