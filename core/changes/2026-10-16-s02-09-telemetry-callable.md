# S02-09 change record: sanitising debug-telemetry callable

Date: 2026-10-16. Story: S02-09 (design 8, 8.1, 5.4; GPS-PRIV-050 / 098; test ids F34-F37, F73, F74, F90, F93).

## What changed

- New `functions/src/activity_streams/telemetry_schema.ts`: the CLOSED schema and a pure sanitiser `sanitizeTelemetryBatch(data)`. Top-level keys are only `events` and `droppedCount`; events are flat maps with the keys `type`, `level`, `component` (required enumerations), `code` (enumeration) and `count`, `seq` (integer counters 0..255). Strings come only from enumerations, so a geohash or any identifier-shaped string is rejected; a nested map, a list, a 6-digit counter, a fractional counter or an unknown key rejects the WHOLE batch with a bare code (`batch_too_large`, `too_many_events`, `invalid_batch`). Caps: 100 events, 16 KiB serialised. `identity`, `uid` and `receivedAt` are never accepted from the client.
- New `functions/src/activity_streams/telemetry.ts`: callable `sendDebugTelemetry` (exported from `functions/src/index.ts`). Pipeline: auth, anonymous refused, App Check noted (shared RARE profile flag), validation first, two daily quotas, then ONE transaction that reads the account fence (`checkAccountFence`: fence documents plus Auth existence) before creating `debug_sessions/{dbg_<random>}` with `identity` (derived from the sign-in provider into a closed enumeration), `events`, `uid` (from `request.auth`) and `receivedAt` (server clock). Fence or storage failure refunds the quotas. Injectable Firestore, Auth, clock and id generator. Timeout 30 s (`TELEMETRY_OPTIONS`).
- Drop signal (design 6.3): when the batch states `droppedCount`, the callable logs the structured metric `debug_telemetry_dropped` with that number only (no uid, no id); a batch without it emits nothing. The counter is NOT stored in the session document (test F93).
- `functions/src/abuse_guard.ts`: `QUOTAS.debugTelemetrySend = 200` (calls per day) and `QUOTAS.debugTelemetryEvents = 5000` (events per day, each call charged its event count), both added to `REDACTED_QUOTA_ACTIONS`. The pinned set test is not edited here; test agents update it.
- New data fixture `functions/src/__tests__/activity/fixtures/telemetry_schema.json`: the data form of the schema table, shared by F74 and the Dart parity test U35 (counter max 255, empty `justified` list).

## Deviations and decisions

- Two quota names instead of one: the design states both a 200-calls-per-day ceiling (5.4) and a 5 000-events-per-day ceiling (8.1), which cannot share one counter.
- The Phase 1 free-text `message` of a log event and the free-form `identity` (build version, git sha, build time) cannot pass a closed schema and are not carried any more. The build is traced by the server-derived identity only; recorded as a Phase 1 behaviour change for the sync log.
- Quota names use the camelCase style of 5.4 (`debugTelemetrySend`), not the snake_case spelling of 8.1.

## Not done here

Rules change and mobile sink migration are separate commits of the same story. Deploy order (design 8.1): callable first, client switch second, rules `create: false` last.

## Verification state

No tests, builds or checks were run (operator rule v4).
