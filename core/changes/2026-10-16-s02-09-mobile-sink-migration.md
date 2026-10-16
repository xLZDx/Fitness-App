# S02-09 change record: mobile debug-telemetry sink migration

Date: 2026-10-16. Story: S02-09 (design 8, 8.1; GPS-PRIV-050 / 098; test ids U25, U26, U34, U35, I14).

## What changed

- New `mobile/lib/core/diagnostics/debug_telemetry_schema.dart`: the client mirror of the closed schema (`kTelemetryEventFields`: names, enumerations, counter maxima 255; `kTelemetryMaxEvents` 100; `kTelemetryMaxBatchBytes` 16 KiB) plus the mapping helpers `telemetryComponentFor`, `telemetryLevelFor`, `telemetryCounter`. Same values as `functions/src/__tests__/activity/fixtures/telemetry_schema.json`.
- `mobile/lib/core/diagnostics/debug_telemetry_sink.dart`: `FirestoreDebugTelemetrySink` (direct `debug_sessions.add`) is replaced by `CallableDebugTelemetrySink`, which calls `sendDebugTelemetry` through `functionsForRegion`. The `DebugTelemetrySink` interface is unchanged. Injectable callable and delay. `send` never throws; a failed batch is retried at most 3 times with doubling backoff (1 s base); events of a batch that still fails are added to a local dropped counter that is reported (capped at 255) as `droppedCount` in the next batch. Batches hold at most 100 events.
- `mobile/lib/main.dart`: `_flushTelemetry` uses `CallableDebugTelemetrySink`; the signed-out guard and the outer try/catch stay.

## Deviations and behaviour change (Phase 1, to be recorded in the sync log)

- The free-text `message` of each log event and the free-form build identity (version, build, git sha, built-at) are no longer uploaded: a closed schema cannot carry them. Events carry level, a `component` enumeration derived from the area (`other` when unknown), a `type` and a `seq` counter.
- No offline queue or extra local buffer was added: the existing writer had none (only the session ring buffer of 500 events). The design 8.1 buffer of 64 KiB is therefore not implemented; failures are counted, not queued. Test U34 clauses about a 500 event / 64 KiB buffer need the plan or the sink adjusted.
- Callers: `_flushTelemetry` is already fire-and-forget (`unawaited`) on lifecycle callbacks, so nothing awaits the send on a user path.

## Verification state

No tests, builds, analyzer or checks were run (operator rule v4).
