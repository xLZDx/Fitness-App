# S02 test epic 3: telemetry sink buffer, schema parity, redaction (U25, U26, U34, U35, I14)

## What
- Tests:
  - `mobile/test/core/diagnostics/debug_telemetry_sink_test.dart`: U34 (failures of kind permission-denied / unavailable / timeout / plain never reach the caller; 1 + 3 attempts with 1 s, 2 s, 4 s injected delays; the caller returns while the callable is pending; buffer of 500 events drops the OLDEST; byte cap evicts the oldest; dropped count reported once in the next batch and capped at 255), U35 (client field table equals `functions/src/__tests__/activity/fixtures/telemetry_schema.json`, with positive controls), U25 (no location / heart-rate / place field or enumeration value, with positive controls), I14 source guard (callable used, no `debug_sessions`).
  - `mobile/test/core/diagnostics/debug_telemetry_test.dart`: U26 group (coordinate pairs, labelled lat/lon, geohash, heart-rate readings, place labels do not survive `redact()`; ordinary lines are untouched).
- Production changes (found by the new tests; the tests failed first):
  1. `debug_telemetry_sink.dart`: the sink had NO buffer (design 8.1 asks for 500 events / 64 KiB). Added `maxBufferEvents` (500), `maxBufferBytes` (64 KiB), `flush()`, `bufferedCount`, `bufferedBytes`. `send` now queues and starts a background drain (it no longer waits for the network); a batch that fails after the 3 retries stays in the buffer for the next send; overflow drops the oldest events and counts them; the count is reported (capped at 255) in the next delivered batch.
  2. `debug_telemetry.dart`: `redact()` had no location / heart-rate / place rule. Added minimal regex rules (over-redaction accepted, as the function documents).
  3. `main.dart`: one shared `CallableDebugTelemetrySink` for the run, because a sink created per flush loses its buffer and dropped counter.

## Why
Design 8.1 (client sink resilience) and plan U25, U26, U34, U35.

## Affected paths
`mobile/lib/core/diagnostics/debug_telemetry_sink.dart`, `mobile/lib/core/diagnostics/debug_telemetry.dart`, `mobile/lib/main.dart`, the two test files above.

## Verification state
Command (from `mobile/`): `flutter test test/core/diagnostics/debug_telemetry_sink_test.dart test/core/diagnostics/debug_telemetry_test.dart`
Result: `All tests passed!` (48 tests). `main.dart` itself is not exercised by any test (one-line change).
