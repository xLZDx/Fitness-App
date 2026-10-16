/// Client mirror of the closed debug-telemetry schema (S02 design 8.1, story
/// S02-09; GPS-PRIV-050 / 098).
///
/// The server (`functions/src/activity_streams/telemetry_schema.ts`, data form
/// `functions/src/__tests__/activity/fixtures/telemetry_schema.json`) is the
/// guarantee; this table is what the client builds batches from, so a valid
/// batch is never refused and the two tables can be compared by a parity test.
///
/// Rules of the table: strings come from enumerations only, numbers are integer
/// counters capped at [kTelemetryCounterMax], events are flat, and there is no
/// field for a coordinate, geohash, heart rate or place name. Adding such a
/// field means editing this table AND the reviewed server schema.
library;

/// Maximum of every counter (design 8.1).
const int kTelemetryCounterMax = 255;

/// Events per call and serialised bytes per call (design 8.1 starting values).
const int kTelemetryMaxEvents = 100;
const int kTelemetryMaxBatchBytes = 16 * 1024;

/// One field of the event table: an enumeration (non-null [values]) or a
/// counter (non-null [max]).
class TelemetryFieldSpec {
  const TelemetryFieldSpec.enumeration(this.values, {required this.required})
      : max = null;
  const TelemetryFieldSpec.counter(this.max, {required this.required})
      : values = null;

  final List<String>? values;
  final int? max;
  final bool required;
}

/// Event field table, identical in names, enumerations and maxima to the server.
const Map<String, TelemetryFieldSpec> kTelemetryEventFields = {
  'type': TelemetryFieldSpec.enumeration(
    ['log', 'lifecycle', 'error', 'metric', 'permission', 'network'],
    required: true,
  ),
  'level': TelemetryFieldSpec.enumeration(
    ['debug', 'info', 'warn', 'error'],
    required: true,
  ),
  'component': TelemetryFieldSpec.enumeration(
    [
      'app',
      'auth',
      'scanner',
      'camera',
      'catalog',
      'recognition',
      'workout',
      'nutrition',
      'activity',
      'sync',
      'export',
      'settings',
      'print',
      'other',
    ],
    required: true,
  ),
  'code': TelemetryFieldSpec.enumeration(
    [
      'none',
      'ok',
      'failed',
      'denied',
      'timeout',
      'unavailable',
      'cancelled',
      'fallback',
      'retry',
      'started',
      'stopped',
      'other',
    ],
    required: false,
  ),
  'count': TelemetryFieldSpec.counter(kTelemetryCounterMax, required: false),
  'seq': TelemetryFieldSpec.counter(kTelemetryCounterMax, required: false),
};

/// Maps a free-form `LogEvent.area` to the `component` enumeration; anything
/// not in the table becomes `other`, so a caller's text never leaves the device.
String telemetryComponentFor(String area) {
  final values = kTelemetryEventFields['component']!.values!;
  return values.contains(area) ? area : 'other';
}

/// Maps a `LogLevel.name` to the `level` enumeration (unknown becomes `info`).
String telemetryLevelFor(String level) {
  final values = kTelemetryEventFields['level']!.values!;
  return values.contains(level) ? level : 'info';
}

/// Clamps a counter into 0..[kTelemetryCounterMax].
int telemetryCounter(int value) =>
    value < 0 ? 0 : (value > kTelemetryCounterMax ? kTelemetryCounterMax : value);
