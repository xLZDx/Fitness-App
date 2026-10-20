/// The sanitising wrapper of the recorder (S04 design 10, S04-31, S04-R-052).
///
/// Pure Dart, no Flutter. Every `catch` in `recording/**`, the journal frame
/// decoder, the worker entry and the global handlers call [sanitizeRecorderError]
/// so that no raw exception (whose message may carry a coordinate) leaves its
/// layer. The content-free [RecorderSafeError] holds a bare code and the
/// original runtime type name only.
library;

import '../l10n/recording_error_codes.dart';

/// A recorder failure stripped of every message, value and path. Safe to log,
/// rethrow, cross an isolate boundary and hand to a crash reporter.
class RecorderSafeError implements Exception {
  const RecorderSafeError(this.code, this.originalType);

  /// The bare error code.
  final RecorderErrorCode code;

  /// The original exception's runtime type name, restricted to identifier
  /// characters (see [safeTypeName]).
  final String originalType;

  @override
  String toString() => 'RecorderSafeError(${code.logName}, $originalType)';
}

/// Converts any error to a [RecorderSafeError] without reading its message. An
/// already sanitised error is returned unchanged.
RecorderSafeError sanitizeRecorderError(Object error) {
  if (error is RecorderSafeError) return error;
  return RecorderSafeError(recorderErrorCodeOf(error), safeTypeName(error));
}

final RegExp _frameLine = RegExp(r'^#\d+\s+[^\n]*\((package|dart|file):[^)\s]*\)$');
final RegExp _suspensionLine = RegExp(r'^<asynchronous suspension>$');

/// Keeps only well-formed stack frame lines; any other text (for example the
/// message that an isolate re-throw puts into the stack text) is dropped.
StackTrace sanitizeRecorderStack(StackTrace stack) {
  final kept = <String>[];
  for (final line in stack.toString().split('\n')) {
    final trimmed = line.trim();
    if (_frameLine.hasMatch(trimmed) || _suspensionLine.hasMatch(trimmed)) {
      kept.add(trimmed);
    }
  }
  return StackTrace.fromString(kept.join('\n'));
}

/// Runs [body]; any error is rethrown as a [RecorderSafeError] with a sanitised
/// stack.
T runRecorderSanitized<T>(T Function() body) {
  try {
    return body();
  } catch (e, s) {
    Error.throwWithStackTrace(sanitizeRecorderError(e), sanitizeRecorderStack(s));
  }
}

/// Async twin of [runRecorderSanitized].
Future<T> runRecorderSanitizedAsync<T>(Future<T> Function() body) async {
  try {
    return await body();
  } catch (e, s) {
    Error.throwWithStackTrace(sanitizeRecorderError(e), sanitizeRecorderStack(s));
  }
}

/// A stack frame path that marks recorder code.
const String kRecorderStackMarker = 'features/recording/';

/// True when [error] is already a [RecorderSafeError] or its [stack] has a
/// frame in `features/recording/`.
bool isRecorderOrigin(Object error, StackTrace? stack) {
  if (error is RecorderSafeError) return true;
  return stack != null && stack.toString().contains(kRecorderStackMarker);
}

/// The hook for the global handlers (`FlutterError.onError`,
/// `PlatformDispatcher.onError`, the zone handler, Crashlytics calls): an error
/// of recorder origin is replaced by its sanitised form, any other error passes
/// through untouched. Wired by the `main.dart` lane.
({Object error, StackTrace? stack}) sanitizeForGlobalHandler(
  Object error,
  StackTrace? stack,
) {
  if (!isRecorderOrigin(error, stack)) return (error: error, stack: stack);
  return (
    error: sanitizeRecorderError(error),
    stack: stack == null ? null : sanitizeRecorderStack(stack),
  );
}
