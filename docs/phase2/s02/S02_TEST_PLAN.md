# S02 test plan: Unified activity (E1)

Status: DRAFT revision 2 for review. Date: 2026-10-16. Branch `phase2/s02-unified-activity`, base head `a5f4a755`. Plan only: no test code exists, no test was run for this document.
Revision 2: re-aligned to the revised design (round 1 review, 24 findings applied: sections 3.5, 3.6, 4 tombstone, 5.1a, 5.2, 5.3, 5.4, 6.1-6.3, 7.1, 8.1, 9.1, 10, 12.1). New tests are in section 1.13 (ids U31-U37, I19-I30, R26-R31, F44-F75, E04-E05); the requirement-to-test map is section 1.14; counts are section 1.15. Design questions DQ-1..DQ-15 now carry the lead's proposed answers (design section 14 is being written in parallel; each answer must be confirmed there); see section 6.
Inputs read: `docs/phase2/s02/S02_DESIGN.md` (all sections incl. 13), `D:\Temp\claude\d--Repo\c10b37ff-3506-44a4-9cd1-d2e82bb71961\scratchpad\s02_dq_proposed_answers.md`, `S02_CODE_MAP.md`, `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (ACs of the GPS-PRIV ids below), `scripts/ci/data_lifecycle_policy.json`, names and patterns of `mobile/test/features/activity/data/*`, `functions/src/__tests__/*` (esp. `body_scan/fakes.ts`, `body_scan/delete.test.ts`, `account_deletion_reconcile.test.ts`, `account_export*.test.ts`), `functions/src/__rules__/*`.
Tags: FACT = read in a file; PROPOSED = choice of this plan; DQ-n = design question (end of file).

## 0. Conventions

| Item | Rule (FACT = follows existing practice) |
|---|---|
| Test ids | `S02-<level><nn>`: U = Dart unit, I = Dart integration (real temp-dir files, real crypto, injectable FS/clock, fake backend), R = Firestore rules emulator, S = Storage rules, F = functions unit with fakes, E = E2E (fake-backed whole flow). Existing ids use `ACT-nn` (FACT); S02 does not reuse them, ACT-01..13 are regression-run (U23, U29) |
| Dart paths | unit: `mobile/test/features/activity/data/`; repository / journal: `mobile/test/features/activity/repository/`; support: `mobile/test/support/` (FACT dir exists); telemetry client: `mobile/test/core/diagnostics/debug_telemetry_test.dart` (FACT exists, extend) |
| Rules paths | `functions/src/__rules__/firestore_rules.test.ts` (new `describe("S02 activities")`), `data_access_policy.test.ts` (CONDITIONAL cells, name format `CONDITIONAL cell activities/create: ...`, FACT format), `storage_rules.test.ts` |
| Functions paths | `functions/src/__tests__/activity/*.test.ts`; reuse `functions/src/__tests__/body_scan/fakes.ts` (stateful Firestore, Storage double with failure injection, signed-URL recording, logger mock; FACT) via import, extended in place only if a missing capability is proven (for example `getFiles` prefix paging for a second bucket) |
| Time / ids | Injected clock everywhere (never wall clock in assertions). Fixed corpus seed (section 2). No test depends on order or on another test's data |
| Refusal pairing | Every rules "denied" assertion is paired with the same operation done with rules disabled or with a valid body that succeeds (FACT pattern of `storage_rules.test.ts`), so a broken emulator cannot fake a pass |
| Failure shape | Server refusals assert a bare error code and that NOTHING was stored/deleted (state after), not only that an exception was thrown |

Commands (FACT from `functions/package.json` and the config headers):
- Dart: `cd mobile && flutter test <files>`
- Functions unit: `cd functions && npx jest <files>`
- Rules: `cd functions && node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules <files>`; Storage rules additionally need `firestore,storage` as the service list (FACT, header of `storage_rules.test.ts`).

## 1. Acceptance criterion -> test

Columns: Test id | Criterion (GPS-PRIV id or design story) | Level | File | Assertion that FAILS if the guarded behaviour breaks.

### 1.1 Model, summary, migration (S02-01; 072, 036)

| Id | Criterion | Level | File (under `mobile/test/features/activity/data/`) | Fails when |
|---|---|---|---|---|
| U01 | S02-01 round trip of 100 sessions | Dart unit | `activity_roundtrip_100_test.dart` | any of the 100: `tryFromJson(migrate(toJson(s)))` not deep-equal to `s` (field-by-field compare of summary, laps, provenance, userEdits, privacy, extras, stream samples). Also asserts the corpus has 100 distinct ids so an empty or duplicated corpus cannot pass |
| U02 | S02-01 schema 1 read | Dart unit | `activity_migration_test.dart` | the 5 `schema=1` records do not load with the same summary values, or A-5 fields are not defaulted |
| U03 | S02-01 newer schema read-only | Dart unit | `activity_migration_test.dart` | a `schema=99` record loses an unknown key, or the writer would emit it again at a lower schema (downgrade write) |
| U04 | corrupt / unknown-schema tolerated | Dart unit | `activity_migration_test.dart` | any of 20 hostile maps (not a map, wrong types, end before start, bad id, unknown sport, unknown stream kind, 1e308, huge list) makes `migrate` throw, or a batch of 100 with 7 corrupt entries yields other than exactly 93 loaded sessions |
| U05 | 072 summary has no list, map, geometry, HR, friend data | Dart unit | `activity_cloud_summary_test.dart` | for any of the 100 sessions a value is not num/String/bool/DateTime, or a key is in the forbidden set (`avgHrBpm`, `maxHrBpm`, `lats`, `lons`, `polyline`, `points`, `bbox`, `startLat`, `startLon`, `laps`, `provenance`, `extras`, `userEdits`, `mergeNotes`, `place*`, `friend*`, `visibility`); a session with sentinel lat tail `7351` and HR `173.25` has either string in `jsonEncode(summary)` |
| U06 | design 3.1 allowlist parity | Dart unit | `summary_allowlist_parity_test.dart` | a summary key is missing from the `hasOnly` list parsed out of `firestore.rules`, or the max value the generator can emit for a numeric key exceeds the bound parsed from the rules. Adding a field to the serializer without the rules fails |
| U07 | 072 `hasRoute` is a flag only | Dart unit | `activity_cloud_summary_test.dart` | GPS session gives `hasRoute != true`, indoor session gives `true`, or the flag is accompanied by any coordinate |
| U08 | 036 / D-16 HR never in the cloud payload | Dart unit | `activity_stream_payload_test.dart` | `fromSession(s, allowedKinds: all 8 kinds)` still contains `heartRate`, or any lap `avgHrBpm`, or the serialized payload contains the HR sentinel `173.25`. Passing all kinds is the point: the builder hard-denies HR, not trusting the caller (DQ-1 answered YES). Also: a GPS sample record, a lap and a provenance record each carrying an HR-named key are dropped or the build throws a typed error, and `meta` never contains `userEdits` or `mergeNotes` (design 5.1) |
| U09 | cadence/power/strokeRate/temperature device-only | Dart unit | `activity_stream_payload_test.dart` | with `allowedKinds` = all 8 kinds, the output holds a kind outside {gps, altitude, speed} (DQ-2 default; widening it is an operator decision and changes this test and F02) |
| U10 | native dedup: deterministic id | Dart unit | `activity_ids_test.dart` | same `sourceId|externalId` gives two ids; an id of any of the 100 fails `^act_[0-9a-f]{40}$`; two different externalIds collide |
| U11 | replay of the same import twice -> one session | Dart unit | `activity_merger_replay_test.dart` | `merge(corpus ++ corpus)` differs from `merge(corpus)` (count and content), or the order of the duplicate list changes the result |
| U12 | migration is total | Dart unit | `activity_migration_test.dart` | seeded fuzz of 1000 mutated maps (key drop, type swap, nesting) makes any migrate step throw |
| U13 | A-5 provenance fields | Dart unit | `activity_cloud_summary_test.dart` | `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion` empty or longer than 32, `sourceTermsSnapshot` longer than 64 or containing whitespace (terms text smuggled) |
| U14 | A-1 quarantine stage | Dart unit | `activity_quarantine_test.dart` | a hostile input (200 001 samples, depth 100 nesting, 10 MB string, duplicate keys, NaN offsets) reaches the merger, or is not rejected with a reason code; a valid input is rejected |
| U15 | A-2 cursor record | Dart unit | `source_cursor_test.dart` | `(sourceId, cursor, windowInclusive)` does not round trip; a corrupt cursor file crashes instead of resetting to "no cursor" |
| U16 | A-3 interface surface | Dart unit | `device_source_surface_test.dart` | `healthStatus()` or `deleteCached()` missing from `DeviceSource`, or source text contains `writeIfAuthorized` (compile-level fake implementing the interface plus a source-text guard) |
| U20 | 051 full-series owner export, trim only for shared | Dart unit | `gpx_encoder_test.dart` | owner export has fewer points than the stream, or shared export does not drop the first and last `routeTrimMeters` (200 m) |
| U24 | design 9 consent matrix | Dart unit | `cloud_upload_policy_test.dart` | any of 12 table rows (source kind x datatype x consent on/off) returns a different allowed-kinds set than the matrix; HR allowed with every consent flag true |
| U27 | corpus generator is deterministic | Dart unit | `synthetic_corpus_test.dart` | two runs differ, or the sha256 of the canonical JSON differs from the committed digest |
| U28 | corpus meets its own spec | Dart unit | `synthetic_corpus_test.dart` | counts per quota of section 2.2 differ (GPS 38, HR 60, pool 10, and so on), edge cases of 2.3 missing, any coordinate outside the synthetic area |
| U30 | golden summaries drift guard | Dart unit | `summary_golden_test.dart` | summaries regenerated from the corpus differ from `functions/src/__rules__/fixtures/s02_summaries_100.json` (the file the rules test R25 loads) |

### 1.2 Export encoders (S02-07; 051)

| Id | Criterion | Level | File | Fails when |
|---|---|---|---|---|
| U17 | GPX structural round trip | Dart unit | `gpx_encoder_test.dart` | parsed `trkpt` count differs from GPS samples, any lat/lon differs by more than 1e-6, times not strictly increasing, `ele` missing where altitude exists, XML not well formed |
| U18 | GPX of an indoor session | Dart unit | `gpx_encoder_test.dart` | indoor / no-GPS session yields anything but the typed result `no_geometry` (no file, no invented points, no empty-track file); the same session still encodes to FIT and to the summary export without error (DQ-3 answered); a GPS session never returns `no_geometry` |
| U19 | FIT structural round trip | Dart unit | `fit_encoder_test.dart` | test-only decoder (`mobile/test/support/fit_test_decoder.dart`) finds wrong `record` count, missing `file_id`/`session`, bad CRC; one flipped byte MUST make the decoder report CRC failure (proves the decoder can fail) |

### 1.3 Performance and dedup (S02-10)

| Id | Criterion | Level | File | Fails when |
|---|---|---|---|---|
| U21 | merge 300 candidates x 3 600 GPS points | Dart unit | `activity_merger_perf_test.dart` | the pairwise-comparison count reported through the `onPairCompared` seam (design 10) exceeds 100 000. This count is the ONLY pass/fail criterion (DQ-14 answered); wall clock is printed as information, never asserted. A guard asserts the count is greater than 0 and at least the analytic lower bound so a seam that is never invoked cannot pass |
| U22 | merge 2 000 sessions without streams | Dart unit | `activity_merger_perf_test.dart` | comparison count exceeds 4 000 000 (twice the analytic n^2/2 = 2 000 000), or is 0; no wall-clock assertion |
| U23 | order independence on corpus; ACT-05..13 green | Dart unit | `activity_merger_test.dart` (existing, regression) + `activity_merger_replay_test.dart` | 5 seeded shuffles of the 155 raw records give different merge results |
| U25 | 050 client event schema | Dart unit | `mobile/test/core/diagnostics/debug_telemetry_test.dart` | an event type with a lat/lon/HR/place field type can be declared without the test failing |
| U26 | 050 client redaction | Dart unit | same | coordinate pair, geohash, HR value, place name placed in event data survive `redact()` |
| U29 | architecture guards stay green | Dart unit | existing `mobile/test/core/architecture/pure_data_layer_guard_test.dart`, `import_graph_guard_test.dart` | a new file in `activity/data` imports `dart:io`, flutter, firestore or a sibling feature (regression run only, no new code) |

### 1.4 Local journal and repository (S02-02; 014, 083, 084, 085, 013)

All Dart integration, files under `mobile/test/features/activity/repository/`.

| Id | Criterion | File | Fails when |
|---|---|---|---|
| I01 | journal round trip of 100 sessions with streams | `file_activity_journal_test.dart` | a session read back differs from the one stored, or `list()` count is not 100 |
| I02 | crash between temp write and rename | `file_activity_journal_crash_test.dart` | after the injected kill the previously committed version of that session is missing or half-written, a `.tmp` file survives the next start, or the new version is visible without the rename |
| I03 | torn index at every byte offset of the last line | `file_activity_journal_crash_test.dart` | for any truncation offset, a previously committed session disappears or start throws |
| I04 | index missing or unreadable | `file_activity_journal_crash_test.dart` | rebuilt set differs from the set before deletion |
| I05 | `synced` marker only after success, idempotent re-upload | `activity_sync_test.dart` | callable failure still writes a `synced` marker; kill after upload before marker followed by a second sync creates a second server row/object (fake backend counts exactly 1); the second sync receives `already_stored` and the client treats it as success and then writes the marker (a client that treats it as an error never converges) |
| I06 | replay of the same import twice -> one session | `file_activity_journal_test.dart` | two put calls with the same recording give two directories or two live index entries |
| I07 | 084 no plaintext coordinates at rest | `file_activity_journal_encryption_test.dart` | bytes of `streams.bin` contain the ASCII `7351` tail, the sentinel latitude as text or as float64 little/big endian; wrong key opens the file; one flipped ciphertext byte is not detected (GCM tag) |
| I08 | 083 backup exclusion | `backup_exclusion_test.dart` | either `backup_rules.xml` or `data_extraction_rules.xml` lacks the journal/stream/quarantine path constants. The checker itself is run against 2 bad XML fixtures (one missing in each file) and MUST fail on both |
| I09 | 085 wipe on sign-out and on deletion success | `activity_wipe_test.dart` | `activities/`, `sources/`, `quarantine/`, queue files not empty after account deletion (no prompt, no export offer) or after a CONFIRMED sign-out. The sign-out prompt rules are I25 |
| I10 | 085 relaunch with auth failure wipes | `activity_wipe_test.dart` | journal survives a start with no valid session for the stored uid, or the user-not-found response |
| I11 | repository sends only the summary; no client Firestore delete | `firestore_activity_repository_test.dart` | the map handed to the fake Firestore has a key outside the summary allowlist, or the fake records a `delete` on `activities` (delete must go through the callable) |
| I12 | offline summary queue is an idempotent upsert | `firestore_activity_repository_test.dart` | after offline, reconnect and a second flush the fake holds more than one document per id |
| I13 | offline `deleteActivity` retry survives restart | `firestore_activity_repository_test.dart` | local entry still listed after delete, or a new repository instance on the same dir does not retry the queued delete |
| I14 | 098 sink uses callable and survives denial | `mobile/test/core/diagnostics/debug_telemetry_test.dart` | sink still calls `.add` on `debug_sessions`; a thrown permission-denied or any other callable error escapes the sink (DQ-9 answered: swallowed, counted in a local dropped-event counter). Retry/buffer/dropped-counter behaviour is U34 |
| I15 | 013 flag OFF: no upload path | `activity_stream_upload_test.dart` | with `ACTIVITY_CLOUD_STREAMS` off and consent granted the fake upload callable is invoked even once |
| I16 | D-16 HR attempted upload | `activity_stream_upload_test.dart` | gunzip of the PUT body (flag ON, consent ON, session with HR stream and HR laps) contains `heartRate`, `avgHrBpm` or the HR sentinel `173.25` |
| I17 | consent missing -> no upload | `activity_stream_upload_test.dart` | upload callable invoked with `cloudStreams` consent absent or revoked |
| I18 | corrupt local files tolerated | `file_activity_journal_test.dart` | a zero-length or garbage `record.json`, or a corrupt `streams.bin`, crashes `list()` or hides the other sessions; the damaged session must surface as "stream unavailable" or be skipped with a diagnostic |

### 1.5 Firestore rules (S02-03; 058, 060, 061, 070, 071, 072)

All Firestore emulator, `functions/src/__rules__/firestore_rules.test.ts` unless noted. Paths: `users/{uid}/activities/{id}`, `activity_streams/{id}`, `activity_settings/main`. Valid id in all tests: `act_` + 40 hex.

| Id | Criterion | Fails when |
|---|---|---|
| R01 | 071 allowlisted-only write succeeds | owner create with only allowlisted keys (a minimal and a full all-keys document) is denied |
| R02 | 058 cross-user and signed-out | another signed-in user, or signed-out, can read, create, update or delete the owner's activity (6 operations); on `activity_streams`/`activity_settings`/`activity_tombstones` same |
| R03 | 070 canary and non-ordinary token | canary token allowed any operation on any of the 4 paths |
| R04 | 071/072 geometry keys at flag OFF | owner create or update with any of `polyline`, `points`, `bbox`, `startLat`, `startLon`, `lats`, `lons`, `route`, `geohash`, `placeName` succeeds (10 cases, each next to a valid control write) |
| R05 | 061 HR keys | `avgHrBpm`, `maxHrBpm`, `heartRate`, `hr` accepted |
| R06 | 061 list/map values | `distanceM: [1,2]`, `sport: {}`, or keys `laps`, `provenance`, `extras` with list/map accepted |
| R07 | 061 wrong types | `sport` number, `startUtc` string, `schema` 1.5, `distanceM` string, `hasRoute` string accepted |
| R08 | 061 numeric bounds | table over all numeric keys of design 3.2: min and max accepted, min-1 and max+1 denied (off-by-one detected); negative `movingTimeS`, `utcOffsetMinutes` 841 |
| R09 | id pattern | ids `foo`, `act_` + 39 hex, `act_` + 41 hex, uppercase hex accepted |
| R10 | open sport pattern | `Run` and a 33-char name accepted, or `newSport7` (future sport) denied |
| R11 | time order | `endUtc < startUtc` accepted; `endUtc == startUtc` denied |
| R12 | required keys | document missing any of `schema`, `sport`, `startUtc`, `endUtc` accepted |
| R13 | string bounds / enums | `primarySourceId` 65 chars, `sourceTermsSnapshot` 65 chars, `primarySourceKind` outside the 5 names, `formulaVersion` 33 chars accepted |
| R14 | delete denied | owner `delete` on `activities` succeeds |
| R15 | server-authored `activity_streams` | owner create/update/delete succeeds; owner read denied; other user read succeeds |
| R16 | server-authored `activity_settings/main` | owner can write a forged `cloudStreams` consent |
| R17 | 071 exclusion falsification | with the `coll != 'activities'` term removed from the WRITE clause in a text copy of the rules loaded into a second test environment, the R04 `polyline` write is still DENIED. The test asserts it is ALLOWED in the mutated copy (proves R04 can detect the removal). Same for `activity_streams` owner write, and now for all FOUR exclusions (`activities`, `activity_streams`, `activity_settings`, `activity_tombstones`): in the mutated copy an owner write of a forged `cloudStreams` consent / `expiresAt` / tombstone is ALLOWED, proving the floor probes can detect each removal |
| R18 | 071 both clauses (read and write) | rules-text lint finds each of the 4 names missing from the parsed read clause or the write clause (read-clause removal is not behaviourally observable for owner-readable paths, so it is a text check; DQ-4 answered: lint accepted) |
| R19 | update via merge | `update` adding `polyline` to an existing valid document succeeds; an update that changes `startUtc` or `sport` is covered by R29 |
| R20 | `updatedAt` type | non-timestamp `updatedAt` accepted. DQ-5 answered: `updatedAt` is a hint, rules do NOT force `request.time`; so an offline-queued write with an old `updatedAt` MUST be accepted (a rule forcing `request.time` would break the offline queue and fails this test) |
| R21 | document size bound | a document with every key at its maximum string length exceeds 4 KiB when serialised (arithmetic assertion on the fixture, design 4) |
| R22 | 098 `debug_sessions` | client create succeeds after the change (must be denied); the old valid-shape document must be denied too. Revertible separately from the permanent floor (design 8.1, 12.1): the test file keeps R22 apart from R31 so reverting `create: false` cannot fail the floor tests |
| R23 | policy cell `activities` create | `data_access_policy.test.ts`: `CONDITIONAL cell activities/create: an allowlisted summary is accepted, a geometry key or unknown key is refused` fails either half |
| R24 | policy cell `activities` update | same file, `activities/update` |
| R25 | seam: real serializer output accepted | every one of the 100 golden summaries (`fixtures/s02_summaries_100.json`, produced by Dart, U30) is accepted by the emulator; one mutated copy per key class is denied. Catches serializer/rules drift across the language boundary |

### 1.6 Storage rules and bucket isolation (S02-04; 059, 064)

| Id | Level | File | Fails when |
|---|---|---|---|
| S01 | Storage rules | `storage_rules.test.ts` | owner, other user or anonymous can read, write, list or delete `streams/{uid}/{id}/v1.json.gz` or `quarantine/{uid}/...` in the default bucket (default stays deny-all, option (b) of design 5; each denial paired with an Admin-equivalent success) |
| S02 | Storage rules | `storage_rules.test.ts` | owner can create under `quarantine/` (signed URL is the only write path) |
| S03 | Storage rules (source) | `storage_rules.test.ts` | `storage.rules` gains any `allow` other than the single deny-all (loosening guard, FACT existing "storage.rules source" describe) |

### 1.7 Stream upload, validation, retention (S02-04, S02-05; 013, 015, 059, 064)

All functions unit with fakes, `functions/src/__tests__/activity/`.

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F01 | valid object promoted | `stream_validator.test.ts` | a valid gps+altitude+speed object is rejected |
| F02 | D-16 server rejects HR | `stream_validator.test.ts` | table of 7 (`kinds.heartRate`, `heart_rate`, `hr`, mixed-case `HeartRate`, lap `avgHrBpm` in meta, HR key in `meta.userEdits`, an unknown kind name) is accepted (an HR series relabelled `speed` is not detectable: DQ-6 accepted residual risk, documented, no test claims otherwise), or promoted object exists, or quarantine object not deleted. Closed-schema depth cases are F51 |
| F03 | coordinate ranges | `stream_validator.test.ts` | lat 90.0001, lon -180.0001, `null`, string accepted; exactly +/-90 and +/-180 rejected |
| F04 | monotonic offsets, equal lengths | `stream_validator.test.ts` | equal or decreasing offsets, `lats.length != lons.length != offsets.length` accepted |
| F05 | size bounds, zip bomb | `stream_validator.test.ts` | compressed 5 MiB + 1 byte, 200 001 samples accepted; a 1 KB gzip expanding to 100 MB is not aborted (assert decompressed bytes read stays under 32 MiB + one chunk) |
| F06 | integrity | `stream_validator.test.ts` | sha256 mismatch, non-gzip, truncated gzip, invalid JSON, unknown `schema` accepted without a bare code |
| F07 | preconditions | `upload.test.ts` | table: unauthenticated, bucket unset, flag off, no `cloudStreams` consent, no summary doc, bad `activityId`, declared bytes over limit each yields a signed URL, a row or a quarantine path |
| F08 | signed URL parameters | `upload.test.ts` | method is not PUT, content type not `application/gzip`, length-range header missing, TTL not 10 min, path not `quarantine/<callerUid>/<activityId>/<uploadId>` |
| F09 | commit happy path | `upload.test.ts` | object not at `streams/<uid>/<id>/v1.json.gz`, quarantine object remains, row not `state=stored`, `expiresAt` hint != summary-`startUtc` (server-read, clamped) + retention, `contentSha256`/`storedSha256`/`bytes`/`kinds`/`settingsGeneration` wrong |
| F10 | commit retry / duplicate upload | `upload.test.ts` | second `commit` or second upload for the same activity yields two objects or two rows (state-machine detail is F45-F48) |
| F11 | cross-user commit | `upload.test.ts` | user B can commit or read user A's `uploadId` |
| F12 | 064 bucket isolation | `upload.test.ts` | `ACTIVITY_STREAM_BUCKET` equal to `BODY_SCAN_BUCKET` is accepted; unset bucket does not refuse |
| F13 | settings validation | `settings_retention.test.ts` | retention 0, -1, 1e9, 1.5, string accepted; 90 / 365 / 730 refused. "never" (null) is an operator decision (DQ-7, proposed offered): the table has a PENDING row for it that is enabled only when the operator confirms; until then the test asserts only that the choice is consistent between settings validation (F13) and purge (F15) |
| F14 | recompute is paged, idempotent, resumable | `settings_retention.test.ts` | with 250 rows and page size 100, failure injected on page 2 then rerun leaves any row with a wrong `expiresAt` hint or double-applied. The crash-resume and generation-race detail is F66, F67 |
| F15 | expired stream purge | `purge.test.ts` | object whose DERIVED expiry (activity date + current setting, F63) is due is not deleted, row not `expired`, summary document deleted (the summary must stay: purge never deletes it); derived expiry `== now` or `now - 1 ms` left in place (both are due); `now + 1 ms` purged; setting "never" (when offered) is NOT purged and a stored hint in the past does not purge it; other user's row purged |
| F16 | purge second run no-op | `purge.test.ts` | second run issues any storage delete or row write |
| F17 | purge failures | `purge.test.ts` | non-404 storage error marks row `expired`; 404 does not mark it `expired`; run budget exceeded and next run does not continue. No-give-up behaviour past the attempt cap is F65 (the earlier "attempt cap terminal" expectation is withdrawn by design 5.3) |
| F18 | shorten / lengthen | `purge.test.ts` | shortening does not make old rows due once the hints are rewritten (next purge run); lengthening resurrects an `expired` row |
| F19 | overdue metric | `purge.test.ts` | oldest-overdue age missing or any metric label/log field contains a uid |

### 1.8 Deletion cascade (S02-06; 054, 055, 066, 076, 077)

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F20 | `deleteActivity` order | `delete_activity.test.ts` | call log is not tombstone write FIRST, then objects in `streams/` and `quarantine/`, then index row, then summary last, then late-sweep job scheduled (tombstone semantics are F59) |
| F21 | idempotent, 404 | `delete_activity.test.ts` | second call throws; object already gone (404) throws |
| F22 | failure injection after each step | `delete_activity.test.ts` | kill after object delete, after row delete, and on a storage error: the summary is deleted while an object or row remains (orphan unreachable), or rerun does not finish the cascade |
| F23 | cross-user delete | `delete_activity.test.ts` | user B deleting A's activity id removes or reveals anything of A |
| F24 | `sweepActivityStreamObjects` prefix | `sweep_account.test.ts` | objects under `streams/<uid>/` and `quarantine/<uid>/` remain, or another user's objects (including uid `abc` vs `abcd` prefix collision) are deleted |
| F25 | sweep error contract (FACT `index.ts` 2405-2423) | `sweep_account.test.ts` | unset bucket throws (must be a logged no-op); all-404 throws; other error does not throw a bare code or leaks a path/message. The both-prefix contract is F57 |
| F26 | reconciler retry after Storage failure | `sweep_account.test.ts` | with Storage failing on the first attempt, the deletion record is not retried, or after the second attempt streams remain, or `accountDeletionRetries` record not removed (pattern `account_deletion_reconcile.test.ts`); with the failure repeated, the retry count stays below `RETRY_MAX_ATTEMPTS = 12` because the second prefix is no longer left untouched (F57) |
| F27 | orphan reconciler | `orphan_reconciler.test.ts` | row without summary kept; object without row older than upload TTL kept, or younger one deleted; `pending` row older than 1 h kept (and NOT deleted when F72 repair conditions hold); a healthy `stored` row touched. Repair and signal cases are F72 |
| F28 | reconciler failure injection | `orphan_reconciler.test.ts` | kill mid-cascade leaves an object readable that the owner deleted after the reconciler ran |

### 1.9 Export (S02-07; 051, 052, 053, 067, 068, 094)

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F29 | 067 parity | `account_export_activities.test.ts` | seeded summary, stream row and settings absent from the response, or response contains stream samples (`lats`) |
| F30 | 053/067 truncation | `account_export_activities.test.ts` | 2 001 activity docs return 2 001 rows or omit `activities` from `truncated`; byte-budget overflow (`fitToByteBudget`) drops rows without `truncated`; the note "heart-rate streams are on your device only" missing; the response contains an `activity_tombstones` section (the design exports none; the assertion changes only if the design adds it). Worst-case sizing with 2 000 rows of each type is F70 |
| F31 | export isolation | `account_export_activities.test.ts` | another user's seeded rows appear |
| F32 | 052/094 download URLs | `download_urls.test.ts` | 21 ids accepted; method not GET; TTL not 15 min; URL issued for another user's id or for an `expired`/`deleted`/`pending` row. Per-state result codes and the no-existence-oracle check are F69 |
| F33 | 068/094 log hygiene | `log_hygiene.test.ts` | across upload, commit (ok and failing), delete, export and download URLs, any captured log line or thrown message contains the sentinel latitude, HR `173.25`, or a signed-URL string (`X-Goog-Signature`) |

### 1.10 Lifecycle docs and policy (S02-08; 004, 065)

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F38 | 065 checkers pass | `functions/src/__tests__/activity/lifecycle_policy.test.ts` (pattern of `guard_scripts.test.ts`) | `check_data_lifecycle_coverage.js` or `check_data_access_policy.js` exits nonzero on the repo files |
| F39 | checker sensitivity | same | the same checkers on a copy of `data_lifecycle_policy.json` with the `activities` row removed (and again with each of `activity_streams`, `activity_settings`, `activity_tombstones`, and the server-only `activity_late_sweeps` row) do not fail; the policy file lacks the `activity_tombstones` (BOTH, read OWNER, writes NONE) or `activity_late_sweeps` (server-only, client NONE) row |
| F40 | indexes for purge and recompute queries | `functions/src/__tests__/activity/indexes.test.ts` (pattern `firestore_indexes_body_scan.test.ts`) | `firestore.indexes.json` lacks either collection-group composite index on `activity_streams`: (1) `state` ASC + `expiresAt` ASC (purge), (2) `state` ASC + `settingsGeneration` ASC (recompute backlog); existing indexes of the file are removed by the merge (the old entries must still be present: snapshot of the old index names is asserted) |
| F41 | callables registered and authenticated | `functions/src/__tests__/activity/callables.test.ts` (uses `discover_callables.ts`) | a new callable (`createActivityStreamUpload`, `commitActivityStream`, `setActivityCloudSettings`, `deleteActivity`, `getActivityStreamDownloadUrls`, telemetry callable) is missing or runs unauthenticated; the callable list differs from the six names of design 5.4 (a seventh unreviewed callable fails the list; the quota/validation tests F60-F62 iterate this same list so a new callable cannot dodge hardening) |
| F42 | privacy text before flag | `functions/src/__tests__/activity/privacy_text.test.ts` | `public/privacy.html` lacks GPS-upload, expiry setting and "heart rate stays on the device" statements (wording DQ-10; weak by nature, see section 5) |
| F43 | matrix rows | same file | `DATA_LIFECYCLE_MATRIX.md` lacks the `activities`/`activity_streams`/`streams/<uid>/` rows (weak string check, section 5) |

Required policy rows (FACT shape from `body_scans`/`body_scan_settings`): `activities` BOTH, read OWNER, create/update CONDITIONAL with `conditionalRefs` -> R23/R24 test names exactly, delete NONE; `activity_streams` BOTH, read OWNER, writes NONE; `activity_settings` BOTH, read OWNER, writes NONE; round 1 adds `activity_tombstones` BOTH, read OWNER, writes NONE and top-level server-only `activity_late_sweeps` (client NONE).

### 1.11 Telemetry server guarantee (S02-09; 050, 098)

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F34 | valid event accepted | `telemetry_callable.test.ts` | a valid batch from the real client schema is rejected or stored in a different shape from the Phase 1 document |
| F35 | modified client | `telemetry_callable.test.ts` | any of 12 cases (coordinate pair, geohash, HR value, place name; each as top-level value, nested map, list element) is accepted or leaves a partial write; a batch of 499 valid events plus 1 poisoned event stores any of the valid ones (whole batch rejected) |
| F36 | closed schema limits | `telemetry_callable.test.ts` | unknown event type, free-text string, 101 events (cap is 100 per call, design 8.1), non-integer or out-of-range counter (51.5007 in an integer counter) accepted. Strings are enumeration-only: an identifier-shaped string that is not in the enumeration (a geohash, `a1b2c3`) is rejected. Counter table, caps, quota and server-set fields are F73, F74 (counter ranges DQ-8: story deliverable before code; tests pin the table once it exists) |
| F37 | identity | `telemetry_callable.test.ts` | unauthenticated call accepted, or a `uid` field in the payload overrides the authenticated uid |

### 1.12 E2E (fake-backed, whole flow)

| Id | Criterion | Level | File | Fails when |
|---|---|---|---|---|
| E01 | gate: 100-session round trip | E2E | `mobile/test/features/activity/e2e/s02_roundtrip_e2e_test.dart` | corpus -> merge -> journal -> restart -> repository (fake backend, real rules-shaped check via allowlist) -> GPX/FIT export: any session lost, altered, or any cloud-bound payload containing geometry/HR |
| E02 | 085 delete account, kill, relaunch | E2E | `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart` | journal directory or caches non-empty after relaunch with auth failure (exact AC of 085) |
| E03 | stream lifecycle | E2E | `functions/src/__tests__/activity/lifecycle_e2e.test.ts` | upload -> commit -> download URL -> shorten retention -> purge -> delete activity -> account sweep: at any step state differs from design 5-7 (object present after delete, row left, summary left, URL issued after expiry) |

### 1.13 Revised-design tests (round 1 requirements)

Concurrency convention (PROPOSED, applies to every race test below): races are driven by DETERMINISTIC interleaving hooks in the fakes (a named gate such as `afterPromote`, `beforeTxn2`, `betweenFirestoreDeleteAndSweep` that pauses one actor until the test releases it), never by sleeps, timers or wall-clock luck. Each race test runs BOTH orders of the two actors and asserts the same invariant. The fake Firestore transaction must really abort-and-retry or throw on a conflicting write (a fake that always commits would let every race test pass); a self-test in `fakes` proves that a conflicting write between read and commit makes the transaction fail, and it is a prerequisite step (step 0). If `body_scan/fakes.ts` lacks this capability it is extended in place (section 0 rule), and the extension is itself covered by that self-test.

#### 1.13.1 Dart unit (files under `mobile/test/features/activity/data/` unless noted)

| Id | Criterion | File | Fails when |
|---|---|---|---|
| U31 | design 3.6 ownership of the three workout models | `workout_model_ownership_test.dart` | the `SportType`-to-model constant is not total over all 12 `SportType` values plus the unknown-sport fallback, maps a sport to two models or to none, or the pinned table differs from the one in design 3.6 once the OPEN table is fixed (until then the test pins whatever the constant says and asserts totality and disjointness, so an unreviewed edit shows in the diff) |
| U32 | design 5.1 `meta` content and closed builder | `activity_stream_payload_test.dart` | `meta` contains `userEdits` or `mergeNotes`; a lap in `meta` has any HR-named key (`avgHrBpm`, `maxHrBpm`, `hr`, `heartRate`, any case); a provenance record has a key outside the closed provenance key set; a corrupted session whose GPS sample map carries an extra `hr` key serialises that key |
| U33 | gate "no external-source dedup promise" (DQ-13 answered: add copy lint) | `mobile/test/features/activity/copy_lint_test.dart` | an S02 localisation string or screen text matches the forbidden claim list (`dedup`, `duplicate removal`, `merged with your watch`, `no duplicates`, and the translated equivalents of the shipped locales) . Positive control: a fixture string containing `no duplicates` MUST be flagged by the same scanner. Weak by nature (strings only); labelled as such, native-id rule stays U10/U11 |
| U34 | design 8.1 client sink resilience | `mobile/test/core/diagnostics/debug_telemetry_sink_test.dart` | a callable failure (permission-denied, unavailable, timeout) throws into the caller; more than 3 retries are attempted or backoff is absent (injected clock records the delays); the local buffer exceeds 500 events or 64 KiB or drops the NEWEST instead of the oldest; the dropped-event count is not reported as a bounded counter in the next batch; the send is awaited on the user path (the caller's future completes while the fake callable is still pending) |
| U35 | telemetry schema parity client to server | same file | the client event field table (names, enumerations, counter maxima) differs from the shared fixture `functions/src/__tests__/activity/fixtures/telemetry_schema.json` that F74 also reads; an event type with a coordinate, geohash, HR or place field can be declared |
| U36 | design 10 seam is behaviour-neutral | `activity_merger_perf_test.dart` | `merge(corpus)` with `onPairCompared: null` differs in any session (count, content, order) from `merge(corpus, onPairCompared: counter)`, or the counter stays 0 on a corpus that needs comparisons |
| U37 | design 5.1a key sets pinned | `stream_schema_pin_test.dart` | the key names produced by `SampleStream.toJson` for gps, altitude and speed, the lap key set and the provenance key set differ from the shared fixture `functions/src/__tests__/activity/fixtures/stream_schema_keys.json` that the validator test F53 also reads. A rename on either side breaks both; a key containing `hr` or `heart` (case-insensitive) in the fixture fails the test |

#### 1.13.2 Dart integration (files under `mobile/test/features/activity/repository/`)

Fault-injection file system: a wrapper over real temp-dir I/O that can fail or kill at a named operation (`writeTemp`, `flush`, `fsync`, `rename`, `dirSync`, `appendIndex`, `delete`) and records the operation log. Fake clock and fake random are injected.

| Id | Criterion | File | Fails when |
|---|---|---|---|
| I19 | design 10 write order | `file_activity_journal_order_test.dart` | the operation log of one `put` is not exactly: streams temp write, flush, fsync, rename, dir sync; record temp write, flush, fsync, rename, dir sync; index append, fsync. An old file removed before its replacement is durable (replacement renamed after the delete) fails; verified for a first write and for an overwrite |
| I20 | design 10 fault injection at every step incl. disk full | `file_activity_journal_fault_test.dart` | for each injected failure (temp write, flush, rename, dir sync, index append; each also as `FileSystemException` "no space left"): a previously committed session is changed or missing after restart, a half-written record is visible, no typed `storage full` error surfaces, or the recording is not kept in memory for retry. Control: with no fault the same `put` succeeds |
| I21 | design 10 single writer | same file | two concurrent `put`/`delete` calls from two async callers (and one from the compute isolate seam) interleave their file steps (operation log shows overlap), or the final state equals neither serial order; a second journal instance on the same directory is detected or refused (cross-process writers are unsupported: documented behaviour asserted) |
| I22 | design 10 index is a rebuildable cache | `file_activity_journal_crash_test.dart` | after deleting `index.jsonl` and rebuilding from `record.json` files: a deleted id (tombstone line in `record.json`) reappears in `list()`, a `synced` entry is re-queued for upload (fake backend counts uploads), or the rebuilt order differs from the sequence order |
| I23 | design 10 monotonic ordering | `file_activity_journal_test.dart` | moving the fake clock back by 1 day or forward by 10 years between two mutations reorders them, or ordering reads `updatedAt`; sequence numbers are not strictly increasing across a restart |
| I24 | design 3.5 key loss | `file_activity_journal_encryption_test.dart` | with the secure-storage key missing, or `streams.bin` undecryptable, the repository throws, wipes anything, or loses another record; the damaged record is not marked `streamLost = true` in `record.json`, summary/laps/provenance not readable, the local counter not incremented, or the "stream unavailable" state not surfaced. Variant: record with a missing `streams.bin` file starts as `streamLost`, not dropped. Variant (flag on, fake cloud copy exists): re-download restores the stream and clears `streamLost` |
| I25 | design 3.5 sign-out with unsynced data | `activity_wipe_test.dart` | table over: (a) all entries synced and uploadable, (b) one entry with an HR stream, (c) one with laps/provenance only on device, (d) one stream while the flag is off, (e) one `upload_failed` entry. Sign-out in (b)-(e) wipes without the warning, or wipes before explicit confirmation, or does not offer local export (GPX/FIT/JSON) first; (a) shows a warning (control, no false alarm); declining confirmation leaves every file intact; account deletion wipes without a prompt (I09) |
| I26 | design 6.2 delete wins on the device | `activity_tombstone_sync_test.dart` | a local entry whose id is in the fake owner-readable tombstone list is not marked deleted (tombstone line in `record.json`) and its local data removed on sync; a `permission-denied` on a summary `put` is not interpreted the same way; a re-import of the same `sourceId|externalId` while the tombstone lives is accepted (must be refused with a typed reason), or a NATIVE recording with a new uuid is refused (must be unaffected) |
| I27 | design 5.2 item 4 client retry policy | `activity_stream_upload_retry_test.dart` | more than 5 attempts per run, no exponential growth of the injected delays, no jitter (two runs with different random seeds give identical delays), total beyond 10 minutes of fake time; after the PUT completed and the app was killed, restart does not resume at `commit` (it re-uploads); with the PUT incomplete restart does not create a new upload; after the cap the entry is not `upload_failed`, or it is retried more than once per app start (hot loop: count attempts over 1 hour of fake time) |
| I28 | design 9.1 consent withdrawal on the client | `activity_consent_withdrawal_test.dart` | after withdrawal a queued upload is still sent, the "delete my cloud streams now" option is not offered, choosing it does not call the bulk-delete callable (fake records exactly one call), or choosing it removes local data / summaries (it must not); not choosing it leaves cloud streams in place (no silent deletion) |
| I29 | design 3.6 no dual write | `workout_ownership_repository_test.dart` | saving one workout of each sport class (fake stores count writes): the same workout is written to two of `activities`, `workout_sessions`, `workout_logs`; a gym/plan sport writes into `activities`; an endurance sport writes into an old collection; any code path copies existing old records into `activities` (seed 3 old records, run the S02 sync, fake counts 0 writes to `activities`) |
| I30 | DQ-15 immutable `startUtc` and `sport` on the client | `firestore_activity_repository_test.dart` | a local edit that changes `startUtc` or `sport` produces a summary update with a changed value for either key (user changes go to `userEdits`); the deterministic id changes after an edit |

#### 1.13.3 Firestore rules emulator (`functions/src/__rules__/firestore_rules.test.ts`, describe `S02 activities revised`)

| Id | Criterion | Fails when |
|---|---|---|
| R26 | 6.2 tombstone blocks resurrection | with `activity_tombstones/{id}` present, an owner `create` or `update` of `activities/{id}` with a valid body is allowed. Controls in the same test: the same body for an id WITHOUT a tombstone is allowed; after the tombstone document is removed (Admin) the write is allowed again (proves the denial is the `exists()` check and not a body error). A batch of 500 summary writes each with the `exists()` lookup stays within emulator limits (lookup budget) |
| R27 | tombstone path permissions | owner create, update or delete of `activity_tombstones/{id}` succeeds; the owner read is denied (devices must learn deleted ids, so it must be allowed); another user, signed-out or canary token reads it successfully. Each denial paired with the Admin write succeeding |
| R28 | 4 `startUtc` clamp | `startUtc` 1999-12-31T23:59:59Z accepted; 2000-01-01T00:00:00Z denied (the lower bound is inclusive, so it must be allowed); a value 23 h after the emulator `request.time` denied (must be allowed), or 25 h after accepted (margins of 1 h around the 1-day bound so an emulator clock skew cannot flip the result; the exact bound is a text assertion on the rules source); `endUtc` has no separate clamp (assert only `endUtc >= startUtc`) |
| R29 | DQ-15 immutability | an `update` that changes `startUtc` or `sport` is accepted; an `update` that keeps both and changes `distanceM` is denied (control: must be allowed); `create` with any valid `sport` is denied (must still work) |
| R30 | 6.1 `activity_late_sweeps` and top-level default deny | a client (owner, other user, signed-out, canary) can read or write any document under top-level `activity_late_sweeps`, each paired with the Admin write succeeding; if the rules have no explicit default deny for unknown top-level collections the test fails and reports the OPEN item of design 6.1 |
| R31 | 12.1 permanent floor lint | rules-source parse finds one of the four names missing from the read-clause exclusions, the write-clause exclusions, or finds a missing `match` block for any of the four paths; finds `allow write` for `activity_streams`, `activity_settings` or `activity_tombstones` that is not `if false`; finds `allow delete` for `activities` that is not `if false`. The same lint run on 5 mutated copies (one exclusion removed per copy for 4 copies, the `activities` delete opened for the fifth) MUST fail each time. The floor tests are independent of the `debug_sessions` rule (R22) so a separate revert of the telemetry rule cannot break them. Process rule "never reverted" cannot be proven by a test; it is covered by this lint staying in the suite |

#### 1.13.4 Functions unit with fakes (`functions/src/__tests__/activity/`)

Upload, commit, state machine (design 5.2, 5.1a):

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F44 | create preconditions, fence and tombstone in the transaction | `upload_fence.test.ts` | table: `accountDeletionRetries/{uid}` exists; `users/{uid}` absent; `activity_settings/main.deleteFenceAt` set; tombstone present (bare `deleted`); no summary; consent withdrawn (`consent_withdrawn`); consent absent. Any case yields a signed URL, a `pending` row or a quarantine path. Control: all clear yields a URL. Each refusal returns a bare code with no echo of the input. A write to the fence document by a second actor between the transaction's reads and its commit makes the create refuse or retry (not issue a URL) |
| F45 | create idempotency, attempt cap, supersede | `upload_state.test.ts` | row `stored` with the same `contentSha256` does not return `already_stored` with no URL; row `stored` with a different hash creates a `pending` row; the 6th create of the day for one activity does not return `too_many_attempts` (5th succeeds, boundary at the injected day rollover resets); a new create does not supersede the older pending `uploadId` and delete its quarantine object; `attempts` and `pendingSince` not set |
| F46 | commit is idempotent (sequential) | `commit_idempotent.test.ts` | a second `commit` with the same `uploadId` after success does not return success; it writes the object again, rewrites the row (fake write counters unchanged is asserted), returns an error, or leaves a stray quarantine object; a commit of a row already `stored` with the same hash returns success; a commit with a stale `uploadId` returns bare `superseded` and changes nothing |
| F47 | commit is idempotent (concurrent) | `commit_concurrent.test.ts` | two concurrent commits with different `uploadId` (both orders, gate hooks) end with other than exactly one `stored` row, exactly one object under `streams/`, and zero objects under `quarantine/`; the loser does not get `superseded`; two concurrent commits with the SAME `uploadId` produce two writes of different content or an error for the second |
| F48 | pending to stored is one transaction with compensation | `commit_transaction.test.ts` | transaction 2 does not write `state`, `bytes`, `kinds`, `storedSha256`, `expiresAt` hint and `settingsGeneration` in one commit (a fake that fails the commit shows a half-written row); transaction 2 refusing (fence set, tombstone created, `uploadId` replaced after the object was promoted) leaves the promoted object or quarantine object in place; a failure injected in the compensation delete is not retried by the late sweep/reconciler. Crash window: kill between promotion and transaction 2 leaves the row `pending` and the object present (asserted as the intermediate state), after which the reconciler outcome is F72 |
| F49 | generation pin and validated-equals-promoted | `commit_generation.test.ts` | the commit reads the object more than once (fake counts reads of the quarantine object bytes: exactly 1, with `ifGenerationMatch`); replacing the quarantine object between metadata and read (generation changes) does not reject with `generation_changed` and promote nothing; replacing it AFTER the single read changes what is promoted (the promoted object's sha256 must equal `storedSha256`, which must equal the hash of the canonical re-serialisation of the bytes that were read) |
| F50 | decompression limits | `decompression_limits.test.ts` | ratio exactly 20 is rejected or exactly 21 is accepted; decompressed 32 MiB exactly rejected or 32 MiB + 1 byte accepted; a 5 MiB gzip that stays under the ratio but over the cap is not aborted at the cap; the wall-clock budget (10 s, injected clock advanced by a slow stream fake) does not abort; bare codes `bomb` / `timeout`; memory proxy: decompressed bytes read stay below cap + one chunk (streaming fake, no inflation). Each rejection deletes the quarantine object and restores the previous row state |
| F51 | closed schema rejects unknown keys at every depth | `closed_schema.test.ts` | table over positions (top level; `kinds`; gps, altitude, speed stream record; `meta`; one lap; one provenance record; one sample element) x payloads (`avgHrBpm`, `hr`, `heartRate`, `unknownKey`, `__proto__`, a nested object, a list where a scalar belongs, `NaN`/`Infinity`, an over-long string, too many list elements): any case accepted (rejected, not stripped), or leaves a promoted object, or does not delete the quarantine object. Specific HR placements demanded by the plan: HR key in `meta`, in a lap, in `userEdits` inside `meta`, in a GPS sample record. Control: the clean payload is accepted |
| F52 | canonical re-serialisation | `canonical_reserialisation.test.ts` | the promoted bytes equal the uploaded bytes for a payload that has different key order, whitespace or number formatting (they must equal the canonical form instead); `storedSha256` not the hash of the promoted bytes; re-serialising the promoted object again is not a fixed point; a clean canonical payload is not stored byte-equal |
| F53 | key sets pinned (server side) | `closed_schema.test.ts` | the validator's allowed key sets differ from the shared fixture `fixtures/stream_schema_keys.json` read also by U37; an unknown key in any set position is accepted (complements F51 on the fixture) |

Fence, deletion races, late sweep (design 6, 6.1, 6.2):

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F54 | commit racing `deleteActivity` | `commit_delete_race.test.ts` | with hooks after promotion and before transaction 2, `deleteActivity` runs fully (tombstone first): the commit leaves any object under `streams/` or `quarantine/` or a `stored` row (compensation must remove them); with delete running AFTER commit finished: object, row, summary remain after the delete; with the tombstone written but the object delete failing, the late sweep (F55) removes the object; both interleavings are run |
| F55 | late upload after erasure | `late_sweep.test.ts` | seed a signed URL, delete the account, then PUT to the quarantine path with the fake bucket: before `runAfter` (deletion + 10 min TTL + 5 min margin) the object is present (control proving the scenario is real); at `runAfter - 1 s` the job did not run; at `runAfter` the sweep leaves any object under `quarantine/<uid>/` or `streams/<uid>/`, or leaves the job after success, or removes the job after a failure (the job must remain for retry) |
| F56 | account deletion order | `account_deletion_order.test.ts` | the recorded call order is not: fence set, prefix sweep (both prefixes attempted), `recursiveDelete(users/{uid})`, Auth deletion, SECOND prefix-only sweep, late job created; the second sweep needs a Firestore row or the settings document (it runs with those already deleted); with an upload injected between the Firestore delete and the first sweep, both prefixes are not empty after the second sweep / reconcile; `deleteFenceAt` not the first write |
| F57 | both-prefix sweep attempt | `sweep_account.test.ts` | prefix `streams/` failing leaves `quarantine/<uid>/` untouched (and the reverse); both failing throws more than one code or an unbare message; one failing throws other than ONE bare code; no failure but 404 on both returns success; objects of another uid (`abc` vs `abcd`) deleted |
| F58 | late sweep job collection | `late_sweep.test.ts` | the job survives `recursiveDelete(users/{uid})` (it lives outside the user tree; fake recursive delete asserted not to touch it); scope `activity` with id deletes only that activity's sub-prefix (a sibling activity's object is deleted); scope `account` leaves either prefix; a job for user A touches user B's objects; the sweep run is not idempotent (second run issues storage deletes) |
| F59 | tombstone-first `deleteActivity` and callable refusals | `delete_activity.test.ts` | the tombstone is not the first write (failure injected on the following storage delete: tombstone must remain and a rerun completes the cascade); `expireAt` missing; a tombstoned id accepted by `createActivityStreamUpload`, `commitActivityStream`, `getActivityStreamDownloadUrls` (must be bare `deleted` or `not_found` as designed); a replayed `createActivityStreamUpload` after delete yields a `pending` row, URL or object. Summary-level replay (`put` after delete) is R26 and the combined flow E04 |

Hardening, quota, hygiene (design 5.4):

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F60 | shared input validation for every callable (iterate the F41 list) | `callable_input_validation.test.ts` | `activityId` of `act_x/../y`, containing `/`, `..`, uppercase hex, 39 or 41 hex, empty, number is accepted by any callable, OR any storage call is made for it (fake bucket records zero calls); `bytes` 0, 5 MiB + 1, 1.5, string accepted (5 MiB exactly and 1 accepted); `contentSha256` of 63/65 chars or non-hex accepted; `activityIds` of 21 refused; duplicate ids not deduplicated; a client-supplied `path`, `prefix`, `uid`, `bucket` or `objectPath` field changes the object path (it must be ignored: the path is built from `request.auth.uid` and the validated id) |
| F61 | quota per callable | `callable_quota.test.ts` | for each of the six actions (`activity_stream_upload` 30, `activity_stream_commit` 60, `activity_delete` 100, `activity_download_urls` 60, `activity_settings_set` 20, `debug_telemetry_send` 200 per user per day): call N succeeds and N+1 returns a bare quota code without side effects; the next injected day resets the count; another user is unaffected; the six action names are NOT all present in `REDACTED_QUOTA_ACTIONS` exported from `functions/src/abuse_guard.ts`; a log line of an over-limit call contains the uid. The limits are unmeasured starting values pinned to the design; changing a limit requires updating this plan |
| F62 | error and log hygiene of the new callables | `log_hygiene.test.ts` (extends F33) | an error message or log line of any callable, for every failure path, contains a client-supplied value (send sentinel strings as `activityId`, `uploadId`, `contentSha256`; use values that pass validation where needed), a uid, a path, a coordinate sentinel or a signed URL; any thrown error is not a bare code |

Expiry, recompute, consent (design 5.3, 9.1):

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F63 | effective expiry derived at purge time | `purge_derived_expiry.test.ts` | the purge uses the stored `expiresAt` hint instead of `activityDateUtc + current streamRetentionDays`: (a) hint in the past but setting lengthened to make it not due: the object is deleted (must be kept and the hint rewritten); (b) hint in the future, setting shortened and hints not yet rewritten: documented behaviour asserted (not purged this run, purged after the recompute); (c) a hint that disagrees with the derivation while the derivation says due does not purge (the hint can never extend retention). `activityDateUtc` taken from a client parameter or from a `startUtc` outside [2000-01-01, now] unclamped (summary seeded with 1990 and with next year: clamped to the bounds; a request payload carrying a date is ignored) |
| F64 | purge transaction re-read and delete order | `purge_transaction.test.ts` | the per-candidate transaction does not re-read the row and settings (row set to `deleted` or `expired` between query and transaction: a storage delete is still issued); the order is not object delete FIRST then `state = expired` (kill after the object delete: rerun finishes, 404 counts as success, no second storage error); a non-404 error marks `expired`; `purgeAttempts` not incremented and `lastErrorCode` (bare), `lastPurgeAttemptAt` not set on failure |
| F65 | purge has no give-up state | `purge_no_giveup.test.ts` | after `purgeAttempts` exceeds `MAX_PURGE_ATTEMPTS` (set small in the test) the row is skipped by the next run (it must still be retried every run), the capped-row signal is not raised, or the oldest-overdue age signal does not grow; once storage recovers the row is purged and the counters cleared |
| F66 | recompute resumable after a crash | `recompute_resume.test.ts` | with 250 rows and page size 100, a throw after page 1: `recomputeCursor` not persisted; the rerun restarts from the beginning (page-1 rows rewritten twice: fake write counter per row must be 1); the rerun skips a page; crash between the row rewrites and the cursor advance loses or doubles a row; continuation is not scheduled (every 5 minutes) until the backlog is empty |
| F67 | recompute generation races | `recompute_races.test.ts` | a commit that stamped generation g-1 (hook: setting changed between commit's read and transaction 2) is not caught by the final pass (`state == stored` and `settingsGeneration < current`); a second setting change during a recompute does not reset the cursor; purge racing a lengthen deletes the object (derivation must say not due); purge racing a shorten leaves the row stored forever (it must become due after the hint is rewritten) |
| F68 | consent withdrawal | `consent_withdrawal.test.ts` | after withdrawal `createActivityStreamUpload` or `commitActivityStream` succeeds (bare `consent_withdrawn` expected); `cloudStreams.withdrawnAt` not recorded or `settingsGeneration` not incremented; the reconciler leaves a `pending` row or its quarantine object; the bulk "delete my cloud streams" call leaves a stored object/row, deletes any summary, or touches another user's objects; stored streams disappear WITHOUT the bulk call (must remain until expiry); individual `deleteActivity` unavailable |
| F75 | settings change is atomic | `settings_transaction.test.ts` | `setActivityCloudSettings` does not update `streamRetentionDays`, `settingsGeneration + 1` and reset `recomputeCursor` in one transaction (failure after the first write leaves a partial state); a rejected value (F13) changes the generation; the callable is writable by the client (rules R16) |

Download, export, signals, telemetry (design 7.1, 6.3, 8.1):

| Id | Criterion | File | Fails when |
|---|---|---|---|
| F69 | download URL per-state results | `download_urls.test.ts` | `stored` does not give URL plus expiry; `expired` is not code `expired`; `pending` is not `not_ready`; `deleted`, tombstoned, missing and another user's id do not all return the IDENTICAL response (deep equal, including timing-independent fields), i.e. an existence oracle exists; a URL is returned for any non-`stored` row; 20 ids ok, 21 refused, duplicates deduplicated |
| F70 | export worst-case sizing and paging | `account_export_activities.test.ts` | seed 2 000 `activities` and 2 000 `activity_streams` rows with every key at its maximum size plus every existing section at its cap: the response exceeds 8 MiB, or an omitted row is not listed in `truncated`; with 2 500 rows of each type the continuation (`fitPaged` path) does not return the remaining rows, drops rows silently, or returns a row twice; the byte size of each seeded row is computed in the test (arithmetic assertion that the seed really is the worst case) |
| F71 | operations signals, forced-failure checks | `ops_signals.test.ts` (`it.each` over the 9 rows of design 6.3) | for each row the stated forced failure does not turn the signal on: (1) 2 h old `pending` row, then the reconciler clears it and the signal falls; (2) old quarantine object; (3) one failing prefix gives a counted bare code and an `accountDeletionRetries` row older than 1 day raises; (4) failing delete: the row is retried and overdue age grows, capped row counted; (5) continuation stopped after one page leaves a visible backlog count and age; (6) one payload per code `hr_kind`, `unknown_key`, `bomb`, `bad_sha`, `generation_changed` increments exactly its own code; (7) commit after fence set counts a fence refusal; (8) oversize batch, over-quota batch and a reported dropped counter are counted; (9) the purge/recompute query on a fake without the index entry fails with FAILED_PRECONDITION and the missing-index signal fires. Every signal label/value set contains no uid, id, path or coordinate |
| F72 | orphan reconciler repair rules | `orphan_reconciler.test.ts` | `pending` row with a valid matching-hash object, existing summary and clear fence/tombstone is deleted instead of repaired to `stored`; the same with a hash mismatch, missing summary, set fence or present tombstone is repaired instead of deleted (4 negative cases, each separately); a `stored` row whose object is missing does not become `deleted` with a signal; a `pending` row of a user with withdrawn consent is not aborted |
| F73 | telemetry caps, quota, server-set fields | `telemetry_callable.test.ts` | 100 events accepted and 101 rejected; serialised batch of exactly 16 KiB accepted and 16 KiB + 1 byte rejected; the daily event ceiling (5 000) not enforced (across several calls), an over-quota call is not a bare code, or `debug_telemetry_send` quota (200 calls) not enforced; `uid` and `receivedAt` come from the payload instead of `request.auth` and the server clock; `droppedCount` above its bound accepted; callable timeout configured above the design value (read from the exported function options) |
| F74 | telemetry closed schema table | `telemetry_schema.test.ts` | the table in `fixtures/telemetry_schema.json` (shared with U35): any enumeration value outside the table accepted; for any counter field, max rejected or max + 1, -1 or 1.5 accepted; a 6-digit counter, a geohash string, a nested map, a list element or a free-text string accepted; the fixture contains a string field not backed by an enumeration, or a counter whose max exceeds 65 535 (a wide counter can carry a scaled coordinate or an HR value). Remaining honest limit: a small counter carrying a heart rate cannot be detected (DQ-6) |

#### 1.13.5 E2E additions

| Id | Criterion | Level | File | Fails when |
|---|---|---|---|---|
| E04 | delete wins across devices (design 6.2) | E2E (Dart, two journals on separate temp dirs, shared fake backend that enforces the rules shape and the tombstone check) | `mobile/test/features/activity/e2e/s02_delete_wins_e2e_test.dart` | device A deletes an activity; device B had a queued offline `put` and a local copy: after B reconnects there is a summary document or a stream object for the id, or B keeps its local data, or B's replayed `put` is accepted. The real rules are exercised by R26; this test proves the client reaction chain |
| E05 | deletion races end to end (design 6.1) | E2E (functions fakes, whole flow) | `functions/src/__tests__/activity/deletion_race_e2e.test.ts` | upload URL minted, bytes PUT, account deletion started with a commit injected between the Firestore delete and the first sweep, a second PUT after Auth deletion: after the late sweep and the reconciler both prefixes are not empty, a row or settings document exists, or the job remains; second reconciler run issues any write |

E03 (stream lifecycle) is extended by two steps: consent withdrawal (creates refuse, pending aborted, bulk delete works) after the retention shortening, and a tombstoned replay after the activity delete.

### 1.14 Requirement to test map (revised design)

| Revised requirement (design section) | Tests |
|---|---|
| Delete fence in create and commit (6.1, 5.2) | F44, F54, F56, E05 |
| Late upload after erasure, late sweep (6.1) | F55, F58, E05 |
| Commit racing a delete (6.1, 5.2) | F54, F48, E05 |
| Second prefix-only sweep and both-prefix attempt (6, 6.1) | F56, F57, F26 |
| Tombstone, resurrection, replayed put after delete (6.2, 4) | R26, R27, F59, I26, E04 |
| Idempotent commit: sequential and concurrent (5.2) | F46, F47, F45, I05 |
| pending to stored transaction and compensation (5.2) | F48, F72 |
| Purge re-read and transaction (5.3) | F64 |
| Effective expiry derived at purge time, hint only (5.3) | F63, F67, F15 |
| Recompute resumable after a crash (5.3) | F66, F67, F14, F75 |
| Purge has no give-up state (5.3) | F65, F71 |
| Closed schema: unknown keys incl. HR in meta/lap/userEdits/GPS record (5.1a) | F51, F02, U32, U08, U37, F53 |
| Re-serialised promotion, validated bytes equal promoted bytes (5.1a, 5.2) | F52, F49 |
| Compression-ratio bomb, absolute cap, time budget (5.2) | F50, F05 |
| Telemetry callable limits, quota, enumeration-only strings (8.1) | F73, F74, F36, F35, U35 |
| Redacted quota actions (5.4, 8.1) | F61 |
| Sentinel logs (5.4, 8.1, GPS-PRIV-094) | F62, F33 |
| Telemetry client sink hardening (8.1) | U34, I14 |
| Journal write order, lock, full disk, fault injection (10) | I19, I20, I21, I02, I03 |
| Index rebuild keeps tombstones and synced (10) | I22, I04 |
| Monotonic ordering (10) | I23 |
| Key loss (3.5) | I24 |
| Sign-out behaviour for unsynced data (3.5) | I25, I09 |
| Ownership of the three workout models, no dual write (3.6) | U31, I29 |
| Consent withdrawal (9.1) | F68, F44, I28, E03 |
| Id, path, bytes, date-clamp validation (5.4, 4) | F60, R09, R28, F63 |
| Export worst case with 2 000 rows of each type, paging with 2 500 (7.1) | F70, F30 |
| Download-URL result states (7.1) | F69, F32 |
| Operations signals with forced failures (6.3) | F71 |
| Permanent rules floor, four exclusions (12.1, 4) | R31, R17, R18, R02, R03 |
| Copy lint, no dedup promise (9, DQ-13) | U33 |
| `no_geometry` GPX result (DQ-3) | U18 |
| Immutable `startUtc` and `sport` (DQ-15) | R29, I30 |
| Hard-deny HR in the builder (DQ-1) | U08, U32 |
| Operation-count gate and seam (10, DQ-14) | U21, U22, U36 |
| Two composite indexes (4, 5.3) | F40, F71 (row 9) |
| Policy rows for tombstones and late sweeps (6) | F38, F39 |
| `updatedAt` hint, no forced `request.time` (DQ-5) | R20, I23 |

### 1.15 Counts

| Level | Count | Ids |
|---|---|---|
| Dart unit | 37 | U01-U30, U31-U37 |
| Dart integration | 30 | I01-I18, I19-I30 |
| Firestore rules emulator | 31 | R01-R25, R26-R31 |
| Storage rules | 3 | S01-S03 |
| Functions unit with fakes | 75 | F01-F43, F44-F75 (F38-F43 lifecycle/policy guards; F44-F75 revised-design tests) |
| E2E (fake-backed) | 5 | E01-E05 (E03 extended) |
| Total | 181 | `it.each` / table tests count once; they carry the listed case counts inside |

Before revision 2 the plan had 122 tests; 59 are new (7 U, 12 I, 6 R, 32 F, 2 E). Roughly 20 existing tests changed their expectation (U08, U09, U18, U21, U22, I05, I09, I14, R02, R03, R17-R20, R22, F02, F09, F13-F15, F17, F20, F25-F27, F30, F32, F36, F38-F41).

## 2. Synthetic corpus: 100 real-shaped sessions

### 2.1 Mechanics

| Item | Spec |
|---|---|
| File | `mobile/test/support/synthetic_activity_corpus.dart` (test-only, pure, deterministic); `mobile/test/support/synthetic_corpus_digest.txt` holds the sha256 of its canonical JSON (U27) |
| PRNG | own SplitMix64, not `dart:math` (stream is stable across SDK versions). Master seed `20261016`; session `i` uses `seed ^ (i * 0x9E3779B97F4A7C15)`; second corpus for fuzz uses master `20261017` |
| Clock | base `2026-01-01T00:00:00Z`; workout `i` starts `base + i*17 h + jitter(0..90 min)`; never `DateTime.now()` |
| Output | 100 logical workouts, 155 raw `ActivitySession` candidates (60 workouts with 1 source, 25 with 2, 15 with 3), plus the merged expectation per workout |
| Privacy of data | all positions fabricated, never copied from any person: tracks are bounded random walks (step 3-9 m at 1 Hz, heading drift sigma 6 degrees) starting on a synthetic grid in open ocean (lat 0..5, lon -30..-25); the pole and antimeridian cases use bounds only |
| Sentinels | every GPS latitude ends in the digits `7351` (the fixture rounds to 6 decimals then forces the tail); HR values use the tail `.25` (for example `173.25`); lets F33, I07, I16, U05, U08 grep bytes |
| Golden | `functions/src/__rules__/fixtures/s02_summaries_100.json` (summaries of the 100 merged sessions), regenerated only by an explicit `--update` flag of U30, otherwise compared |

### 2.2 Quotas (exact counts, not probabilities)

| Dimension | Spec |
|---|---|
| Sport | all 12 `SportType` values at least 6 times each (running 12, cycling 10, walking 8, hiking 6, trailRunning 6, mountainBiking 6, indoorCycling 8, swimmingPool 10, swimmingOpenWater 4, rowing 6, strength 12, other 12 of which 4 carry an unknown sport string such as `futureSport7`) |
| GPS-bearing | 38 workouts (running, trailRunning, walking, hiking, cycling, mountainBiking, swimmingOpenWater, rowing outdoors); length tiers: 20 x 600-1 800 points, 12 x 1 800-7 200, 5 x 7 200-14 400, 1 x 43 200 (12 h heavy) |
| Indoor / no GPS | 62 (strength, indoorCycling, swimmingPool, treadmill-as-`running` without stream, other) |
| Heart rate | exactly 60 with an HR stream (1 Hz, 40-210 bpm, slow drift plus 3 dropout runs of 5-20 s); 23 of them GPS-bearing, 37 indoor; the other 40 have none |
| Other streams | altitude on 30 GPS workouts; speed on 25; cadence on 20; power on 15 (cyclists); strokeRate on 8 rowers/swimmers; temperature on 5 (feeds DQ-2 cases) |
| Laps | 10 pool swims with 20-80 laps each, `poolLengthM` in {25, 33.33, 50}, strokes and `avgSwolf`; 12 runs with auto laps per 1 km; 1 workout with 1 000 laps (boundary of `lapCount`) |
| Sources | `bleSensor`, `platformHealth`, `companionApp`, `vendorCloud` (and native `app`) mix; `fileImport` kind appears in 5 records |
| Platform-health echoes | 8 workouts where the extra record is an echo of the native one (same start within 30 s, `appPackage` set) |
| Split pair | 1 workout recorded as two halves (gap 2 min) that the merger must keep consistent with its documented behaviour |

### 2.3 Edge cases (each is a named record, asserted present by U28)

| # | Case |
|---|---|
| E-1 | zero-distance indoor session with duration; `distanceM = 0` |
| E-2 | `startUtc == endUtc` (duration 0) |
| E-3 | `utcOffsetMinutes` in {0, 345, -720, 840, -840}; local midnight crossing |
| E-4 | GPS gap of 120 s (offsets jump) and a 30 s stationary cluster |
| E-5 | position at lat 89.99999 / lon 179.99999, and one at lat -90 / lon -180 (exact bounds); a (0,0) point |
| E-6 | stream with non-monotonic offsets inside an otherwise valid session (tolerant reader drops the stream, keeps the session) |
| E-7 | unknown extra keys at session, summary, lap and source-record level (kept in `extras`, dropped from the cloud summary) |
| E-8 | `schema=1` x 5 records; `schema=3` x 2 records (future) |
| E-9 | `sourceId` of exactly 64 chars (boundary), and unicode in `externalId` |
| E-10 | two sources with the same `externalId` (exact-duplicate rule) |
| E-11 | one session with every summary key at its rules maximum; one with all keys at 0 |
| E-12 | HR-only (no GPS) and GPS-only (no HR) sessions, plus a session with HR laps (`avgHrBpm` in laps) |
| E-13 | native session id generated from a fixed UUID, uploaded twice (idempotent upsert) |
| E-14 | `avgSpeedMps` 120, `ascentM` 100 000, `steps` 1 000 000 at the bounds |

A separate set of 20 hostile maps (not part of the 100) feeds U04, U14 and F06 (corrupt documents, oversize, bad types).

## 3. Run order for the test-writing agents

Agents: `functional-test-reviewer` writes and runs U, I, R, S, F; `e2e-runner` writes and runs E and re-runs the cross-layer seams (R25, U30, I11). The coordinator runs nothing (v4). After each epic the author runs the COMPLETE set of every file it has written so far (all files, not only the new ones) and reports exact command lines and results; after the last epic everything is run once more. Never repo-wide suites, lint, typecheck, build.

| Step | Epic / story | Files written then run (cumulative sets run in addition) | Notes |
|---|---|---|---|
| 0 | Support | corpus generator, `synthetic_corpus_test.dart` (U27, U28), FIT test decoder self-test, fault-injection FS wrapper self-test, fake Firestore transaction-conflict self-test and interleaving hooks (section 1.13), shared fixtures `stream_schema_keys.json` and `telemetry_schema.json` | Everything else depends on the corpus and the fakes; pin the digest only after U28 is green; a fake that never conflicts invalidates every race test |
| 1 | S02-01 model v2 (+ ownership 3.6) | U01-U13, U30, U31, U32, U37 | writes the golden JSON; U06 needs the rules from step 3, mark pending until then, not skipped; U31 pins the sport-to-model constant |
| 2 | S02-02 journal | I01-I10, I18-I25, I29, I30 | injectable FS and clock must exist; U01-U32, U37 so far re-run; I24/I25 need the secure-storage fake |
| 3 | S02-03 rules | R01-R21, R23-R31 (R22 deferred to step 9) | R17 needs two emulator environments (now four mutated exclusions); R31 mutated copies; unlocks U06 and R25 |
| 4 | S02-04 stream upload | F01-F12, F44-F53, F60-F62, S01-S03, I15-I17, I27, U08, U09 | F12 needs both bucket env settings; F47/F48/F49 need the interleaving hooks; F53 shares a fixture with U37 |
| 5 | S02-05 retention | F13-F19, F63-F67, F75, F68, I28 | injected clock; F66/F67 need small page and attempt-cap constants injectable |
| 6 | S02-06 deletion | F20-F28, F54-F59, F72, I13, I26 | pattern of `account_deletion_reconcile.test.ts`; F56 needs the order log across callable and reconciler; R30 default-deny finding goes to the design OPEN list |
| 7 | S02-07 export | U17-U20, F29-F33, F69, F70, I11, I12 | FIT decoder must be proven able to fail (U19) first; F70 needs the worst-case seed builder |
| 8 | S02-08 lifecycle | F38-F43, F71 | F71 runs after steps 4-6 because it forces failures in their code |
| 9 | S02-09 telemetry | F34-F37, F73, F74, R22, I14, U25, U26, U34, U35 | U35 and F74 read the same fixture; counter table is a pending prerequisite (DQ-8) |
| 10 | S02-10 perf and dedup | U14-U16, U21-U24, U29, U33, U36, I05, I06 | the operation-count thresholds are fixed by the design (100 000, 4 000 000), no calibration pinning from the first run (DQ-14); wall clock printed only |
| 11 | E2E | E01-E05 (E03 extended) | `e2e-runner`; E04 needs two journals over one fake backend; E05 reuses the F55/F56 fakes |
| 12 | Final | all 181 tests (section 1.15) and every file above in one pass: Dart (`flutter test` on all listed files), functions jest, rules emulator (firestore), storage rules (firestore,storage) | the only run that goes to the final GPT review as evidence, with git head |

Evidence table to report per run: Claim | Evidence | Command | Head | Result | Not covered (verification-contract format).

## 4. Not testable here (marked NOT_RUN by design)

| Item | Why | What is covered instead |
|---|---|---|
| Deployed Firebase rules, functions, scheduled purge, indexes | no deployed project; operator-only | emulator rules tests, fake-backed functions tests, F40 index file check |
| Real GCS bucket: IAM, public access prevention, soft-delete/versioning windows (078/079), real signed-URL behaviour, lifecycle | infra, not in the repo; runbook is a deliverable | fakes record signed-URL parameters (F08, F32); runbook existence is a doc check only |
| Real device: Android Auto Backup actually excluding the journal, keystore, file system fsync/atomic rename on device, performance factor on a mid phone | no device | XML parse (I08), injected-FS crash tests (I02-I04), op-count perf proxy (U21) |
| Deployed Cloud Logging content (log redaction in production) | no log sink | logger mock capture (F33) |
| `public/privacy.html` correctness as legal text | not a test matter | string presence only (F42) |
| Firestore point-in-time recovery / backups window | infra | none |
| Firestore TTL policy on `activity_tombstones.expireAt` (400 days) actually deleting tombstones; residual resurrection risk after expiry | infra; time-based | the tombstone document shape and `expireAt` presence (F59); expiry behaviour NOT_RUN |
| Bucket lifecycle rule on `quarantine/` (1 day backstop) | real GCS only | the quarantine-age signal (F71 row 2) and reconciler (F27, F72) |
| Real signed-URL validity after the 10 min TTL (late PUT outcome on real GCS), real GCS generation semantics of `ifGenerationMatch` | no deployed bucket | fake bucket models generation and a late PUT (F49, F55); fidelity of the fake is an assumption |
| Deploy order of the telemetry change (callable, client, rules last) and revertibility of `debug_sessions create: false` | deployment procedure | R22 isolated from the floor lint (R31); order itself NOT_RUN |
| Permanent-floor process rule "rules exclusions never reverted" | process, not code | R31 lint stays in the suite; a revert PR would have to delete it |
| App Check requirement on new callables, runbook execution, signal owners and alert delivery | infra / people | forced-failure checks prove the signal turns on (F71), not that anyone is paged |
| Heart rate disguised as an allowed stream kind or a small telemetry counter (DQ-6) | undetectable by any structural check, accepted residual risk | closed schemas, small counter ranges, sentinel tests; no test claims to detect it |
| Hydrate of an empty journal from the cloud (new device, reinstall) | out of S02 scope (design 3.5) | I24 re-download of a lost stream only |
| Wall-clock performance on a mid phone | no device | operation counts only (U21, U22) |
| FIT acceptance by a vendor tool | no validator in repo | structural round trip with a test-only decoder (U19) |

## 5. Tests that pass without proving anything, and how each is avoided

| Risk | Where | Avoidance |
|---|---|---|
| "Denied" is an emulator or path error, not the rule | R02-R16, S01-S02 | refusal paired with a valid control write or rules-disabled success (section 0) |
| Exclusion removal not detected | R04, R15, R16 | R17 runs the same probe against a mutated copy of the rules and requires it to be allowed; R18 text-lints the read clause (DQ-4) |
| Golden/fixture drift hides a serializer change | U06, U30, R25 | allowlist and bounds are parsed from the real `firestore.rules`; the golden is regenerated only by an explicit flag |
| Corpus is empty or trivially small | U01, I01, E01 | assert 100 distinct ids and the quotas (U28) before asserting equality |
| Substring grep for coordinates matches nothing because the writer changed encoding | I07, F33, I16 | sentinels in several encodings (text, float64 LE/BE); a positive control writes an unencrypted copy and the same grep MUST find the sentinel |
| Test passes because the code under test is a mock | F-series | fakes are the existing stateful doubles; assertions are on state after (object map, rows, call order), not on "was called" |
| "Did not throw" as proof | F21, F25, I03 | assert resulting store contents and counters, not absence of exceptions |
| Purge boundary and clock | F15 | injected clock, tests at `now - 1 ms`, `now`, `now + 1 ms` |
| Perf test flakes or never fails | U21, U22 | operation-count proxy is the main assertion, wall clock is a generous ceiling; the proxy is calibrated once and pinned |
| FIT decoder accepts garbage | U19 | one flipped byte MUST be reported as CRC failure; a record-count mutation MUST change the decoded count |
| Zip-bomb test allocates the memory it should prevent | F05 | assert decompressed bytes read, using a streaming fake, not by inflating |
| Weak text checks | F42, F43 | explicitly labelled low-value guards; they never stand in for behaviour; the policy checkers (F38, F39) are the real gate |
| Hidden skip / pending | all | no `skip`, `xit`, `test.todo` or `markTestSkipped` in S02 files; a final grep over the listed files is part of the step 12 report |
| Shared mutable fixtures | corpus | generator returns fresh objects per call; tests never mutate the committed golden |
| Order dependence | F-series | each test builds its own fake; no module-level state |
| Cross-language drift Dart vs rules vs functions | R25, U30, F06, U37/F53, U35/F74 | the same hostile, golden and schema fixture JSON files are read by both sides |
| Race test passes because the fake never conflicts | F44, F47, F48, F54, F66, F67, E05 | step 0 self-test: a conflicting write between a transaction's read and commit must fail or retry it; deterministic gate hooks, both actor orders run, no sleeps |
| Concurrency test passes in one order only | F47, F54, F67 | each runs both orders and asserts the same invariant |
| Idempotency test passes because the second call is a no-op error | F46, I05 | assert success result AND unchanged write counters AND one object/row, not only "no duplicate" |
| Seam never invoked, op-count budget trivially met | U21, U22, U36 | assert count greater than 0 and at least the analytic lower bound; neutrality check against null seam |
| Fault injection never triggers | I20, I19 | the fault wrapper logs the injected operation and the test asserts the injection happened; a no-fault control run succeeds |
| Derived-expiry test passes with hint equal to derivation | F63, F67 | hint and derivation are made to disagree in both directions |
| Telemetry limit tests assert only the boundary below | F73, F74 | each limit tests max (accepted) and max + 1 (rejected) |
| Quota tests pin unmeasured starting values | F61, F73 | values pinned to the design; changing one requires a plan update; they do not claim the values are right |
| Signals proven only by metric name | F71 | each forced failure is run and the changed metric value is asserted, plus the uid-free label check |

## 6. Design questions (acceptance text that is not testable or is ambiguous)

### 6.1 Status after revision 2

ANSWERED = the lead's proposed answer exists (`s02_dq_proposed_answers.md`) and the tests follow it; each must be confirmed in design section 14 when that section lands (if section 14 differs, the named tests change). PENDING-OPERATOR = a product decision owned by the operator; tests are written for the proposed default and flagged.

| DQ | Status | Answer the tests follow | Tests |
|---|---|---|---|
| DQ-1 | ANSWERED | builder hard-denies `heartRate` regardless of `allowedKinds`; server rejects too | U08, U32, F51 |
| DQ-2 | PENDING-OPERATOR (cloud stream kinds beyond GPS) | default: only gps, altitude, speed go to the cloud; cadence, power, strokeRate, temperature device-only | U09, U24, F02, F51 |
| DQ-3 | ANSWERED | GPX of a no-GPS session returns typed `no_geometry`; FIT/summary export allowed | U18 |
| DQ-4 | ANSWERED | rules-text lint plus emulator write negatives | R17, R18, R31 |
| DQ-5 | ANSWERED with a caveat | `updatedAt` is a hint, rules do not force `request.time`; ordering by a local monotonic counter. The proposed answer also mentions a server `receivedAt`, but the revised design has the client write the summary directly (no callable), so no server `receivedAt` exists: UNTESTABLE until the design says where it is set | R20, I23 |
| DQ-6 | ANSWERED (accepted residual risk) | disguised HR is undetectable; no test claims otherwise | F02, F74, section 4 |
| DQ-7 | PENDING-OPERATOR ('never' retention) | proposed: offered. The 'never' rows of F13/F15 are enabled only when confirmed; 'never' means indefinite GPS storage | F13, F15 |
| DQ-8 | ANSWERED as a process rule | the counter/enumeration table is defined before code and reviewed; tests read the shared fixture, so they cannot be finalised until the table exists | F74, U35, F73 |
| DQ-9 | ANSWERED | sink swallows every error, counts drops | I14, U34 |
| DQ-10 | ANSWERED | privacy text edit owned by the S02 PR; flag stays off until then | F42 (string check only) |
| DQ-11 | ANSWERED | 014 applies to the S04 recording journal; S02's store is the permanent device copy; contract gets a one-line clarification | I05, I09 |
| DQ-12 | ANSWERED | `storage.rules` stays deny-all; 064 AC replaced by S01-S03 plus functions-level signed-URL and prefix tests; contract wording amended | S01-S03, F08, F60 |
| DQ-13 | ANSWERED | add copy lint | U33 |
| DQ-14 | ANSWERED | operation-count assertion is the only gate; wall clock informational | U21, U22, U36 |
| DQ-15 | ANSWERED | `startUtc` and `sport` immutable after creation; rules enforce | R29, I30 |

New questions raised by revision 2:

| DQ | Status | Question | Tests affected |
|---|---|---|---|
| DQ-16 | PENDING-OPERATOR (default expiry) | default expiry value (2 years proposed, shown to the user) and whether C2 follows it | F13, F15, F63 (the default is a constant; tests read it) |
| DQ-17 | OPEN | App Check requirement for the new callables (design 5.4) | F41, F60 |
| DQ-18 | OPEN | quota limits, telemetry caps (100 events, 16 KiB, 5 000 per day) are unmeasured starting values | F61, F73 pinned, not validated |
| DQ-19 | OPEN | is `accountDeletionRetries/{uid}` written before the sweep starts (design 6.1 OPEN)? | F56 asserts the order via `deleteFenceAt`; if the existing code differs the account-deletion path needs a change the test will expose |
| DQ-20 | OPEN | exact `SportType`-to-model table (design 3.6), top-level default deny for `activity_late_sweeps` (6.1), tombstone TTL owner | U31, R30 |
| DQ-21 | OPEN | design 7.1 refers to `fitPaged` for continuation; paging code was not re-read | F70 |

### 6.2 Original questions (revision 1 wording, kept for traceability)

| Id | Question | Test affected |
|---|---|---|
| DQ-1 | Design 3.1 gives `ActivityStreamPayload.fromSession(s, allowedKinds)`. State that `heartRate` is hard-denied inside the builder regardless of `allowedKinds`; otherwise "HR never uploaded" depends on every caller | U08, I16 |
| DQ-2 | D-16 does not name cadence, power, strokeRate, temperature. The tests assume device-only until decided (design 12.3 Q2) | U09, U24, F02 |
| DQ-3 | What must GPX/FIT export return for a session with no GPS (empty track, error, or no file)? Not stated | U18 |
| DQ-4 | Contract 071 asks that removing the exclusion "in BOTH clauses" fails a test. For owner-readable paths the read clause is not behaviourally observable; accept a rules-text lint for it? | R17, R18 |
| DQ-5 | `updatedAt` is a client clock (design 3.2 OPEN). Should rules force `request.time`? Without that, forged future timestamps cannot be refused and no meaningful test exists | R20 |
| DQ-6 | A modified client can send HR values inside an allowed kind (for example an HR series labelled `speed`). The validator can only check kind names and ranges. Is a plausibility rule wanted, or is this accepted residual risk (the contract says rules and validator cannot judge plausibility)? Same for integer counters in telemetry carrying a heart-rate number | F02, F36 |
| DQ-7 | Is the retention option "never" offered? Test expectations for F13/F15 flip | F13, F15 |
| DQ-8 | Telemetry callable: which counters and what maximum values are in the closed schema? "numbers only from bounded counters the schema names" needs the list to be testable | F36 |
| DQ-9 | Does the debug sink swallow permission-denied after the change? Design 8 marks it OPEN | I14 |
| DQ-10 | Exact wording required in `public/privacy.html` before the flag is enabled, and the owner of the edit | F42 |
| DQ-11 | GPS-PRIV-014 says the local journal is deleted after confirmed sync, but design 3.4 keeps the local journal as the persistent store. Which reading applies (crash journal vs permanent local copy)? I05 and I09 assume the permanent copy | I05, I09 |
| DQ-12 | GPS-PRIV-064 AC lists per-prefix Storage rules tests (quarantine create-only, stream owner-read). Design option (b) keeps `storage.rules` deny-all, so those ACs become "deny-all for all prefixes" (S01-S03). Confirm the contract AC is satisfied by option (b) | S01-S03 |
| DQ-13 | "No external-source dedup promise" (gate) is a product-copy statement; there is no executable assertion beyond the native id rule (U10, U11). Should a copy lint (no strings claiming cross-source dedup in l10n) be added? | gate, S02-10 |
| DQ-14 | Perf budgets (2 s per 300 candidates, 1 s per 2 000 sessions) are unmeasured guesses; test thresholds are set from the first calibrated run, which makes the budget self-fulfilling. Is a fixed budget required from the operator? | U21, U22 |
| DQ-15 | Update semantics of `activities`: may the owner change `startUtc`/`sport` after creation (design allows any valid update)? No immutability rule is stated | R19 |

DQ-5 resolution (lead, after the design conflict was reported): the summary carries a monotonic `rev`; rules require rev == 1 on create and rev strictly greater than the stored value on update. Add rules emulator tests: update with equal rev refused, update with lower rev refused, update with higher rev accepted, create with rev != 1 refused, replayed older write refused. Counts above are raised by these five rules tests (R32-R36) once the rule exists in the design snippet.
