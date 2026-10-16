# S02 test epic 3: findings (plan versus design versus code)

Scope: ids U10, U11, U14-U26, U33-U36, I11, I12, I14 (merger, encoders, telemetry sink). U29 was done in epic 1; I06 was done in epic 2.

## Contradictions and how they were resolved (design followed)

1. Plan U34 asks for a 500-event / 64 KiB local buffer; the design (8.1) requires it and the build had none (design 17 note 11 says so). Tests written first (they did not compile: no buffer API), then the buffer implemented (production change below).
2. Plan U34 "the send is awaited on the user path (the caller's future completes while the fake callable is still pending)" is read as: `send` must return while the callable is pending. The sink now queues and drains in the background; `flush()` awaits the drain.
3. Plan U24 describes a policy returning "allowed-kinds sets". No policy class exists in S02; the cloud-stream column lives in `ActivityStreamPayload.fromSession(allowedKinds)` and the summary column in `ActivityCloudSummary.fromSession`. U24 tests the design 9 table over these two seams (consent off = empty `allowedKinds`). A consent flag to `allowedKinds` mapping does not exist yet (upload caller belongs to S02-04 / S04) and is not tested.
4. Plan U25, U26, I14 name `debug_telemetry_test.dart`; U25 and the I14 source guard are in `debug_telemetry_sink_test.dart` next to the shared schema helpers, U26 is in `debug_telemetry_test.dart`. The plan puts U33 in `copy_lint_test.dart` under `mobile/test/features/activity/` (as built).
5. Plan I11 / I12 name `firestore_activity_repository_test.dart` and an "offline summary queue". The build has no such repository: the cloud path is `ActivitySyncRepository` over `ActivitySummaryBackend` (the journal's `pending` / `upload_failed` states are the queue). The tests keep the file name and run on that path with the real journal and a recording fake backend. The Firestore adapter itself is not run (no fake Firestore package in `pubspec.yaml`); only its pure `toFirestoreSummary` / `fromFirestoreSummary` and its source text are checked.
6. Plan U21 says the count must be "at least the analytic lower bound". The merger indexes its work (design 10 "if over budget" is already implemented), so the n^2/2 bound does not apply; the lower bound used is the number of records that join a cluster (200 for U21, 1 000 for U22).
7. Plan U10 "two different externalIds collide": covered. Observed, not changed: the id key is the text `<sourceId>|<externalId>`, so `("a|b","c")` and `("a","b|c")` give the same id. Source ids are fixed constants today, so this is only latent.

## Budget calibration (design 10, DQ-14)

First run, synthetic scenarios of the test file: U21 (100 workouts x 3 sources x 3 600 GPS points) = 300 comparisons, 100 merged sessions; U22 (1 000 workouts x 2 sources, no streams) = 2 000 comparisons, 1 000 merged sessions. Design ceilings kept (100 000 and 4 000 000). Frozen calibrated ceilings added: 1 000 and 6 000 (about 3x measured), because a full quadratic scan of 300 candidates (45 000) would still pass the design ceiling. Wall clock (about 0.2-0.3 s) is printed only.

## Production changes (smallest change; each found by a test that failed first)

| File | Change | Found by |
|---|---|---|
| `activity_quarantine.dart` | duplicate-key check compared raw key text; `{"a":1,"a":2}` passed while `jsonDecode` keeps the last value. Keys with a backslash are decoded before the check | U14 |
| `debug_telemetry_sink.dart` | no buffer, no non-blocking send. Added bounded buffer (500 events, 64 KiB, oldest dropped and counted), failed batch kept for the next send, dropped count reported capped at 255 in the next delivered batch, `send` returns without waiting, `flush()` | U34 |
| `debug_telemetry.dart` | `redact()` kept coordinate pairs, labelled lat/lon, geohashes, heart-rate readings and labelled places. Minimal regex rules added (over-redaction accepted) | U26 |
| `main.dart` | one shared sink for the run (a sink per flush loses its buffer and dropped counter); not exercised by a test | U34 design |

## Test-side notes

- `package:xml` is a transitive dependency; `gpx_encoder_test.dart` imports it as the independent well-formedness oracle without editing `pubspec.yaml`.
- `main.dart` passes the whole `DebugTelemetry.toJson()` (all events still in its ring and a cumulative `droppedCount`) on every flush, so a long session re-sends events. Observed, not changed (Phase 1 behaviour, secondary).
- Not verified: the real `sendDebugTelemetry` callable and Firestore adapter on a device or emulator; the shipped FIT file in a third-party FIT validator (only the test-only decoder); Russian copy beyond the regex list of `copy_lint_test.dart`.
