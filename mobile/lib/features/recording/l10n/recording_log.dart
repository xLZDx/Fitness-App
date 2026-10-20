/// The log mapper of the recorder (S04-27, design 10). Pure Dart.
///
/// A recorder `catch` calls [logRecorderError]: the error is mapped to a bare
/// code first, and only the fixed scope, the code and the type name reach the
/// sink. Coordinates, paths, uids and exception messages never do.
library;

import 'recording_error_codes.dart';

/// Where recorder log lines go. The app wires `debugPrint` here; a test wires a
/// capture. Null means silent.
void Function(String line)? recorderLogSink;

/// Builds one content-free log line. The [scope] must be a fixed identifier
/// chosen in code; characters outside `[A-Za-z0-9_.]` are dropped.
String recorderLogLine(String scope, Object error) {
  final safe = sanitizeScope(scope);
  final code = recorderErrorCodeOf(error).logName;
  return 'recorder.$safe code=$code type=${safeTypeName(error)}';
}

/// Maps and emits one error. Never throws.
void logRecorderError(String scope, Object error) {
  final sink = recorderLogSink;
  if (sink == null) return;
  try {
    sink(recorderLogLine(scope, error));
  } catch (_) {
    // A failing sink must not break the recorder.
  }
}

/// Maps and emits a fixed event word with no error attached (counts only).
void logRecorderEvent(String scope, String event) {
  final sink = recorderLogSink;
  if (sink == null) return;
  try {
    sink('recorder.${sanitizeScope(scope)} event=${sanitizeScope(event)}');
  } catch (_) {}
}

/// Keeps identifier characters only.
String sanitizeScope(String scope) {
  final buffer = StringBuffer();
  for (final unit in scope.codeUnits) {
    final ok = (unit >= 0x30 && unit <= 0x39) ||
        (unit >= 0x41 && unit <= 0x5A) ||
        (unit >= 0x61 && unit <= 0x7A) ||
        unit == 0x5F ||
        unit == 0x2E;
    if (ok) buffer.writeCharCode(unit);
    if (buffer.length >= 32) break;
  }
  return buffer.toString();
}
