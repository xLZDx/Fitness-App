# S02 design: Unified activity (E1)

Status: DRAFT for GPT-PM review, revision 2 (round 1 review of architect, reliability-reviewer and security-reviewer applied and listed in section 13; answers to the 15 test-plan design questions in section 14; every changed point is marked PROPOSED). Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. No code is changed by this document.
Tags: FACT = verified in a file read for this document (path given); PROPOSED = design choice, not implemented; OPEN = unknown or needs a decision. Companion documents: `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (ids `GPS-PRIV-nnn`), `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`, `docs/phase2/s02/S02_CODE_MAP.md` (explorer facts, not re-read here).

Binding operator decisions (2026-10-16, FACT, contract section 9 "Operator decisions recorded"): D-16 GPS streams go to the cloud as private objects with a USER-SET automatic expiry (proposal for the default: 2 years, shown and changeable; retention clock = activity date; derived geometry follows the stream setting); heart-rate streams stay on the device and never reach the cloud. D-17 changes nothing in S02 except that the summary document carries no geometry and no friend data.

## 1. Scope and non-scope

Source of scope (FACT): S02 row, `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` line 80; epic E1 (line 193, items P2-006, P2-007); backlog `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` lines 158-159 (P2-006 "E1 adds persistence provenance fields (A-5)"; P2-007 "E1 adds quarantine, cursors, healthStatus (A-1..A-3)"); A-1..A-5 defined in `core/plans/PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md` lines 156-160 (FACT). Gate text (FACT, roadmap line 80): round trip of 100 real-shaped sessions; deletion removes streams; lifecycle rows; no external-source dedup promise.

| In S02 | Out of S02 (owner) |
|---|---|
| Persistence of `ActivitySession`: local journal, Firestore scalar summary, private stream object | GPS recording, location permission, recorder (S04-D, S04) |
| Rules block with shape validation, storage path, expiry, deletion cascade, export of summary rows and streams | Health Connect / HealthKit adapters, HR reads (S16) |
| Provenance fields A-5; quarantine, sync cursors, `healthStatus()` surface (A-1..A-3) as interfaces and local state | Dedup against external sources, vendor clouds (S17); S02 promises none |
| Tolerant schema versioning and migration | FIT/GPX/TCX IMPORT (P2-029, later; A-1 limits apply there) |
| FIT and GPX EXPORT from stored data | Trash/undo window (GPS-PRIV-093; UI sprint), publishing (S09) |
| Consent matrix per source and datatype (E11 start), native-session dedup | Consent centre UI (S03), privacy zones (S04-D/S09) |
| GPS-PRIV-098 debug-telemetry server guarantee (scheduled in S02 by the contract) | |

A-1 quarantine in S02 means: a validation stage with hard input limits in front of the merger (interface plus tests with synthetic hostile inputs); no importer exists in S02 (PROPOSED). A-2 cursors: a local record per source (`sourceId`, `cursor`, `windowInclusive`) in the journal (PROPOSED). A-3: `healthStatus()` and `deleteCached()` added to the `DeviceSource` interface, `streamDuringWorkout` optional, no `writeIfAuthorized` (FACT, reconciliation line 158).

## 2. Current state and design risks

| Topic | Evidence |
|---|---|
| Pure-Dart model `ActivitySession` with `summary`, `streams` (8 `StreamKind` incl. heartRate, gps), `laps`, `provenance` (list of `SourceRecord`), `userEdits`, `privacy`, `schema = 1`, `mergeNotes`, `extras`; tolerant `tryFromJson` | FACT `mobile/lib/features/activity/data/activity_session.dart` lines 52-203 |
| `toJson` emits `streams` (lists of numbers incl. `lats`/`lons`), `laps`, `provenance` as lists | FACT same file lines 127-146; `sample_stream.dart` lines 154-163 |
| Summary has 15 nullable numeric fields incl. `avgHrBpm`, `maxHrBpm` | FACT `activity_summary.dart` lines 6-39 |
| Id = `act_` + sha1 of `sourceId|externalId` or `sourceId|start:<epoch ms>` | FACT `activity_session.dart` lines 41-50 |
| `merge()` is pure, order-independent; exact-duplicate rule by `sourceId|externalId`; clustering is a linear scan of clusters per session (O(n x clusters)); echo detection is O(n^2) | FACT `activity_merger.dart` lines 33-119 |
| `SourceRecord.rawRef` points at a retained original; nothing implements that store | FACT `source_record.dart` lines 30-32 |
| `DeviceSource` interface only, no adapter; capability matrix | FACT `device_source.dart` lines 126-150 |
| Architecture guards: `activity/data` may not import `package:flutter/`, `cloud_firestore`, `shared_preferences`, `flutter_secure_storage`, riverpod or `dart:io`, nor sibling new features | FACT `mobile/test/core/architecture/pure_data_layer_guard_test.dart` lines 79-83; `import_graph_guard_test.dart` lines 9, 164-169 |
| No database package in `mobile/pubspec.yaml` (grep for sqflite, drift, isar, hive, sqlite, objectbox, sembast found none); present: `shared_preferences`, `path_provider`, `crypto`, `encrypt`, `flutter_secure_storage`, `cloud_firestore`, `cloud_functions`. No gzip-capable package other than `dart:io` | FACT `mobile/pubspec.yaml` lines 46-102 |
| Owner wildcard `users/{uid}/{coll}/{document=**}`: read exclusions lines 74-90, write exclusions lines 91-108; a new collection is client-writable with no shape check today | FACT `firestore.rules` lines 73-109 |
| Body Scan pattern: `numberIn`, `schemaOk` (lines 532-537), server-authored `body_scans` block (554-561), settings block with key allowlist (591-607) | FACT `firestore.rules` |
| `storage.rules` is deny-all for the default bucket; Body Scan uses a separate private bucket via V4 signed URLs (`getSignedUrl`, `contentType`, `extensionHeaders` length range, TTL 10 min) | FACT `storage.rules`; `functions/src/body_scan/create.ts` lines 187-196; `shared.ts` lines 37-46 |
| `sweepBodyScanObjects`: not configured = logged no-op; all-404 = nothing to delete; other errors throw with a bare code and the reconciler retries | FACT `functions/src/index.ts` lines 2405-2423 |
| Scheduled purge precedent: `purgeExpiredBodyScanPhotos` (daily `30 3 * * *`), `sweepLateBodyScanUploads` (every 5 min), run budget constants | FACT `functions/src/body_scan/purge.ts` lines 74-76, 525-542 |
| Export: `MAX_ROWS = 2000`, `MAX_EXPORT_BYTES` 8 MiB, helpers `sub`, `one`, `owned`, `fitToByteBudget` | FACT `functions/src/account_export.ts` lines 52-130, 277 |
| Debug telemetry: client writes `debug_sessions` via `.add`; rules check top-level keys and `events.size() <= 500` only | FACT `mobile/lib/core/diagnostics/debug_telemetry_sink.dart` line 36; `firestore.rules` lines 367-378 |
| No fixture corpus of real-shaped sessions; no FIT/GPX/TCX code | S02_CODE_MAP.md (explorer FACT, not re-verified here) |

Design risks (from the explorer fact sheet, re-checked above):

1. R1. A new `activities` collection is client-writable by default and `ActivitySession.toJson` contains lists (streams, laps, provenance, mergeNotes) that rules cannot validate. Mitigation: split serialisation into a scalar summary document and a stream object (section 3); exclude the collection from BOTH wildcard clauses (section 4).
2. R2. Streams need a new private store, a deletion step following the `sweepBodyScanObjects` contract, separate export delivery and a default-off flag (sections 5-7, 12).
3. R3. No local DB, no schema version, a third workout model beside `WorkoutSession` and `WorkoutLogEntry` (S02_CODE_MAP.md), and the GPS-PRIV-098 telemetry fix is easy to lose inside S02 (section 8, story S02-09).

## 3. Data model

### 3.1 Split of `ActivitySession`

PROPOSED: `ActivitySession` stays in `mobile/lib/features/activity/data` (pure, no I/O). Two new pure projections are added there; they only build maps and bytes-free structures:

| Projection | Content | Lives |
|---|---|---|
| `ActivityCloudSummary.fromSession(s)` -> `Map<String, Object>` | Scalars only (table 3.2). No lists, no maps, no geometry, no HR, no friend data | Firestore `users/{uid}/activities/{id}` |
| `ActivityStreamPayload.fromSession(s, allowedKinds)` -> structured payload | Streams of allowed kinds, plus a `meta` section (laps without HR, provenance list, mergeNotes, userEdits) | Private object (section 5); encoding to gzip bytes happens OUTSIDE `activity/data` because `dart:io` is forbidden there (FACT guard) |

PROPOSED (DQ-1, DQ-2): `ActivityStreamPayload.fromSession` HARD-DENIES `heartRate` regardless of `allowedKinds` (a caller passing `heartRate` in `allowedKinds` still gets no HR; unit test), and the server validator rejects it too (defence in depth, 5.1a). By default `allowedKinds` is only `gps`, `altitude`, `speed` (plus time offsets); `cadence`, `power`, `strokeRate` and `temperature` stay device-only until the operator answers the open question in 12.3.

The existing full `toJson` stays as the local journal record format (section 3.4). A unit test asserts that `ActivityCloudSummary` output keys are a subset of the rules allowlist (single constant list shared by a test that parses `firestore.rules`; PROPOSED).

### 3.2 Summary document `users/{uid}/activities/{activityId}` (PROPOSED)

Document id must match `^act_[0-9a-f]{40}$` (sha1 hex, FACT from `activityIdFor`).

| Key | Type / bound | Source |
|---|---|---|
| `schema` | int, 1..1000 | `ActivitySession.schema` |
| `sport` | string, `^[a-z][A-Za-z0-9]{0,31}$` (open pattern, not a closed list, so a new sport never breaks a write; the model already degrades unknown to `other`) | `SportType.name` |
| `startUtc`, `endUtc` | timestamp; `endUtc >= startUtc` | session |
| `utcOffsetMinutes` | int, -840..840 | session |
| `movingTimeS` | number 0..604800 | session |
| `distanceM` 0..10^7; `ascentM`, `descentM` 0..10^5; `avgSpeedMps` 0..120; `avgCadence` 0..400; `avgPowerW`, `normalizedPowerW` 0..5000; `activeEnergyKcal` 0..50000; `steps` 0..10^6; `strokeCount` 0..10^5; `poolLengthM` 0..1000; `lapCount` 0..1000; `avgSwolf` 0..300 | number | `ActivitySummary` (flattened) |
| `routeTrimMeters` | number 0..2000 | `ActivityPrivacy` |
| `primarySourceId` | string <= 64; `primarySourceKind` in the 5 `SourceKind` names (FACT `source_kind.dart`) | `provenance.first` |
| `sourceCount`, `userEditCount`, `mergeNoteCount` | int 0..64 | counts of the lists |
| `hasRoute` | bool (a flag only, no coordinates) | GPS stream present locally |
| `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion` | string <= 32 | A-5 |
| `sourceTermsSnapshot` | string <= 64, a terms-version id or hash, never the terms text | A-5 |
| `updatedAt` | timestamp | client clock; a HINT only, never used for ordering or conflict resolution (PROPOSED, DQ-5). Ordering uses the server `receivedAt` (set by the commit callable on the stream index row and by `setActivityCloudSettings`) and the monotonic local counter of section 10. Rules do NOT force `updatedAt == request.time`, because queued offline writes would then fail on replay (the Body Scan consent pattern, FACT lines 570-582, is not copied here). OPEN: whether the summary document also carries a server-stamped field; without it, summary ordering relies on the local counter only |

Immutability (PROPOSED, DQ-15): `startUtc` and `sport` are immutable after creation because they feed the deterministic id (`sourceId|start:<epoch ms>`); a user correction goes into `userEdits` (device-only), never into these two fields. Rules enforce that an update leaves `startUtc` and `sport` unchanged (section 4).

Deliberately NOT in the summary (PROPOSED, decision for the operator in 12.3): `avgHrBpm`, `maxHrBpm` (heart-rate derived health data; contract GPS-PRIV-036 allows "at most non-sensitive summary fields chosen in the S02 design"), laps (list, carry HR), provenance list, `userEdits` map, `mergeNotes` list, `extras`, any start/end coordinate, bounding box, place name, friend or visibility field. A forward-compatible reader keeps unknown local keys in `extras` locally; the cloud summary drops them (extras are not uploaded because rules cannot judge them).

PROPOSED (round 1): the summary is owner-only and, in S02, is never exposed to friend or public paths. Exact `startUtc`, `utcOffsetMinutes`, `distanceM` and `sport` together can form a routine or region fingerprint; this is acceptable for owner-only data, and S09 MUST NOT derive any public or friend-visible artefact from summary fields (only from its own privacy-zone pipeline). `startUtc` is additionally range-clamped in rules (section 4) so a forged far-future or far-past date cannot stretch or collapse stream retention.

### 3.3 Provenance and schema versioning

- A-5 fields (`formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`, `sourceTermsSnapshot`) are added to `ActivitySession` as optional strings, written to the journal and summary. Values come from constants in the data layer; where the sprint models carry a model id/version the same string is reused (reconciliation line 160 says they already do; not re-verified, OPEN).
- `schema` today is only a per-document int, loosely checked in rules (FACT `schemaOk`, lines 535-537). PROPOSED: S02 sets `schema = 2` for the persisted form (adds A-5 fields); `schema = 1` records from tests are read as is.
- Tolerant migration (PROPOSED): a `migrate(Map raw) -> Map` chain in the data layer, one step per version, each pure and total; a step never throws, unknown keys are kept in `extras`, a record newer than the app's max schema is read-only with unknown keys preserved and is never rewritten by an older client (no downgrade write). The existing `tryFromJson` is the final stage. Migration is applied on read from the journal and on read from the cloud summary.

### 3.4 Local store decision

Options: (a) add a database package (sqflite/drift): new dependency, native build and review cost, not present today (FACT grep); (b) `shared_preferences`: wrong for hundreds of KB sessions with 100k-point streams; (c) file-based journal in an app-private directory: uses `path_provider` and `dart:io` (both already allowed outside the data layer), follows the existing file-store patterns `photo_store.dart` (AES-GCM) and `offline_video_cache.dart` (S02_CODE_MAP.md). PROPOSED: (c).

Layout (placeholder names, fixed in implementation; constants shared with the backup-exclusion check, GPS-PRIV-083):

| Path under the app support directory | Content |
|---|---|
| `activities/<id>/record.json` | `ActivitySession.toJson()` without streams (summary, laps, provenance, edits), written atomically (temp file, flush, rename) |
| `activities/<id>/streams.bin` | Streams, binary or gzip-JSON, encrypted at rest (key from `flutter_secure_storage`, pattern of GPS-PRIV-084 recommendation) |
| `activities/index.jsonl` | Append-only index: one line per mutation (`put`, `delete`, `synced`), last line wins; compacted at start when larger than a threshold; a torn last line is ignored |
| `sources/<sourceId>.cursor.json` | A-2 cursor state |
| `quarantine/` | Rejected raw inputs, bounded count and age (A-1) |

The repository (`ActivityRepository` interface, `FileActivityJournal`, `FirestoreActivityRepository`) lives in `mobile/lib/features/activity/repository/` (OUTSIDE `activity/data`, PROPOSED path), importing `data`, never the reverse. Android backup: the directory is excluded in `backup_rules.xml` and `data_extraction_rules.xml` in the same PR (GPS-PRIV-083, FACT that today only photos and three preference files are excluded).

PROPOSED (DQ-11): this local store is the PERMANENT device copy of finished activities. GPS-PRIV-014 ("journal deleted after a confirmed sync") applies to the crash-safe RECORDING journal of S04, not to this store; a synced entry here is kept (only `synced` is marked) and is removed only by user delete, sign-out wipe (3.5) or account deletion. The one-line clarification is added to the contract in the S02 PR (done in `GPS_LOCATION_PRIVACY_CONTRACT.md`, GPS-PRIV-014).

Crash safety, write order, locking and full-disk handling: see section 10.

### 3.5 Authority, sign-out and key loss (PROPOSED, round 1)

- Authority: with `ACTIVITY_CLOUD_STREAMS` off (the default) the DEVICE is the only authority for streams, laps, provenance, edits and heart rate. The cloud holds a partial mirror (the scalar summary only). In S02 there is no cloud-to-device hydrate of summaries or streams into an empty journal; a new device or a reinstall sees nothing until a hydrate story exists (OPEN: later sprint). With the flag on, the stream object is a restorable copy of the allowed kinds only; heart rate, `userEdits` and `mergeNotes` never leave the device.
- Sign-out: the journal is wiped on sign-out (GPS-PRIV-085) only after the app checks for entries that are unsynced or can never be uploaded (heart-rate streams, laps, provenance, any stream while the flag is off). If any exist, sign-out shows a warning and offers local export (GPX/FIT/JSON, section 7) first; wipe happens only after explicit confirmation. Account deletion wipes without that prompt (deletion intent is explicit).
- Key loss: if the `flutter_secure_storage` key is missing or decryption of `streams.bin` fails, the repository does NOT crash and does NOT wipe. It marks the record `streamLost = true` in `record.json` (a tombstone-style state: summary, laps and provenance stay readable, stream unavailable), increments a local counter and surfaces "stream unavailable on this device". If the cloud copy exists (flag on) the stream can be re-downloaded.
- Tests: sign-out with unsynced data requires confirmation and offers export; simulated key loss yields `streamLost`, no exception, no deletion of other records.

### 3.6 Ownership of the three workout models (PROPOSED, round 1)

`ActivitySession` (new `activities` collection and local journal) owns sessions that are recorded or imported with device or sensor data: the sport classes served by the recorder and device sources (running, cycling, swimming, walking, hiking and the other endurance or GPS sports in `SportType`). `WorkoutSession` (`workout_sessions`) and `WorkoutLogEntry` (`workout_logs`) keep owning their existing workout records (gym and plan-driven logging) exactly as today. Rules: no dual write in S02 (one workout is written to exactly one model, chosen by sport class); S02 adds no write into the old collections and no code path copying old records into `activities`; readers (stats, export) read each model separately and S02 does not add a cross-model aggregate, so nothing is double counted. Bridging or merging in the UI is S03. OPEN: the exact `SportType`-to-model table and the stats readers were not verified in this revision (architect review did not verify them either); S02-01 must pin the table in a constant and a test.

## 4. Firestore

New paths (PROPOSED names; the contract fixes behaviour, names are placeholders):

| Path | Writer | Client read | Client write |
|---|---|---|---|
| `users/{uid}/activities/{activityId}` scalar summary | client (offline-first) | owner | owner create/update with shape check; delete DENIED (delete goes through callable so streams cannot be orphaned) |
| `users/{uid}/activity_streams/{activityId}` stream index row: `objectPath`, `bytes`, `kinds`, `activityDateUtc`, `expiresAt` (null = never), `state` (`pending`/`stored`/`expired`/`deleted`), `contentSha256`, `schema` | server only (Admin SDK) | owner | denied |
| `users/{uid}/activity_settings/main`: `cloudStreams` consent (`version`, `acceptedAt`), `streamRetentionDays` | server only, via callable `setActivityCloudSettings` (the upload callable trusts this document, so it must not be client-forgeable) | owner | denied |

PROPOSED (round 1) additions to the table above:

| Path | Writer | Client read | Client write |
|---|---|---|---|
| `users/{uid}/activity_tombstones/{activityId}`: `deletedAt` (server time), `expireAt` (Firestore TTL field) | server only (`deleteActivity`, account-level bulk delete) | owner (devices learn which ids are deleted) | denied |

`activity_settings/main` additionally carries `settingsGeneration` (int, incremented on every setting change), `recomputeCursor`, `recomputeGeneration`, `deleteFenceAt` (section 6.1) and `cloudStreams.withdrawnAt` (section 9). The index row `activity_streams/{id}` additionally carries `uploadId`, `attempts`, `pendingSince`, `contentSha256` (client upload hash, idempotency key), `storedSha256`, `settingsGeneration`, `purgeAttempts`, `lastErrorCode`, `lastPurgeAttemptAt` (sections 5.2, 5.3). All of these are server-written; the client never writes them.

Rules edits in `firestore.rules`:
1. Add `coll != 'activities'`, `coll != 'activity_streams'`, `coll != 'activity_settings'`, `coll != 'activity_tombstones'` (round 1) to the read clause (lines 74-90) AND the write clause (lines 91-108). GPS-PRIV-071 requires both; a test that removes either exclusion in a copy of the rules must fail the owner-denied tests (AC of 071).
2. New blocks modelled on Body Scan (FACT patterns lines 532-537, 554-561, 591-607):

```
function activitySummaryOk(id, d) {
  return id.matches('^act_[0-9a-f]{40}$')
      && d.keys().hasOnly([ ...allowlist from table 3.2... ])
      && d.keys().hasAll(['schema','sport','startUtc','endUtc'])
      && schemaOk(d) && d.schema is int && numberIn(d.schema, 1, 1000)
      && d.sport is string && d.sport.matches('^[a-z][A-Za-z0-9]{0,31}$')
      && d.startUtc is timestamp && d.endUtc is timestamp && d.endUtc >= d.startUtc
      && d.startUtc >= timestamp.date(2000, 1, 1) && d.startUtc <= request.time + duration.value(1, 'd')  // round 1 clamp
      && (!('distanceM' in d) || numberIn(d.distanceM, 0, 10000000))
      && ... one line per numeric key with the bounds of table 3.2 ...;
}
match /users/{uid}/activities/{activityId} {
  allow read: if isOrdinaryUser() && request.auth.uid == uid;
  allow create, update: if isOrdinaryUser() && request.auth.uid == uid
                        && activitySummaryOk(activityId, request.resource.data)
                        // round 1: deleted ids cannot be re-created (section 6.2)
                        && !exists(/databases/$(database)/documents/users/$(uid)/activity_tombstones/$(activityId))
                        // DQ-15: startUtc and sport are immutable after creation (applies to update only;
                        // written as two separate allow clauses in the real file)
                        && (request.method == 'create'
                            || (request.resource.data.startUtc == resource.data.startUtc
                                && request.resource.data.sport == resource.data.sport));
  allow delete: if false;
}
match /users/{uid}/activity_streams/{id} { allow read: if isOrdinaryUser() && request.auth.uid == uid; allow write: if false; }
match /users/{uid}/activity_settings/{id} { allow read: if isOrdinaryUser() && request.auth.uid == uid; allow write: if false; }
match /users/{uid}/activity_tombstones/{id} { allow read: if isOrdinaryUser() && request.auth.uid == uid; allow write: if false; }  // round 1
```

What rules cannot check (FACT, contract GPS-PRIV-098 and `firestore.rules` comments lines 525-528): list elements beyond fixed indexes, document byte size, and geometry or plausibility. Therefore every summary value is a scalar with a type and range check, strings carry a regex and a length bound, and lists/maps are not allowed at all (`hasOnly` rejects any list-typed key because the allowlist contains none and each key is type-checked). A worst-case document is bounded by (number of keys) x (string bound) = well under 4 KiB (PROPOSED arithmetic: 31 keys, strings <= 64 chars).

GPS-PRIV mapping:

| Id | How S02 satisfies it | Test |
|---|---|---|
| 058 | Own blocks, none relies on the wildcard | owner and other user create/read; other user denied; server-authored paths owner write denied |
| 061 | Key allowlist, type and size bounds | unknown key, array, wrong type, out-of-range number refused |
| 071 | Exclusion in BOTH clauses + shape block | geometry key (`polyline`, `points`, `bbox`, `startLat`) write to `activities` denied while flag off; allowlisted-only write succeeds; removing an exclusion fails the test |
| 072 | Summary has no geometry key at all, in either flag state | serializer unit test + rules test |
| 070 | `isOrdinaryUser()` on every grant | canary token denied on all three paths |
| 059 | Stream objects owner-only (section 5) | existing deny-all Storage rules test plus functions-level tests (signed-URL minting, ownership, prefix building); see the note after the 5.1 bounds and DQ-12 |

Guard for the exclusion floor (PROPOSED, DQ-4): reads of owner paths cannot be negative-tested through the wildcard reliably, so the guard is two-part: (1) a rules-text lint test asserting that each of the four exclusion names appears in BOTH the read clause and the write clause of the owner wildcard in `firestore.rules`; (2) emulator negative tests on writes (owner write to `activity_streams`, `activity_settings`, `activity_tombstones` denied; geometry key write to `activities` denied). Emulator tests additionally cover immutability (DQ-15): an update changing `startUtc` or `sport` is denied, an update leaving both unchanged and altering another allowlisted field succeeds.

Rules tests go in `functions/src/__rules__/firestore_rules.test.ts` and `data_access_policy.test.ts` (FACT, contract section 10). PROPOSED (round 1): `firestore.indexes.json` declares, in the same PR, two collection-group composite indexes on `activity_streams` (query scope COLLECTION_GROUP): (1) `state` ASC + `expiresAt` ASC for the purge query; (2) `state` ASC + `settingsGeneration` ASC for the recompute backlog query. A missing index fails the query with FAILED_PRECONDITION, which the forced-failure checks in 6.3 cover. A Firestore TTL policy on `activity_tombstones.expireAt` is an infra step (runbook deliverable; OPEN owner). The current content of `firestore.indexes.json` was not read; the entries must be merged with whatever exists. Rules tests additionally cover: tombstoned id create/update denied; `startUtc` before 2000-01-01 or more than 1 day after `request.time` denied; tombstone path owner-write denied and owner-read allowed.

## 5. Streams storage

| | (a) Prefixes of the default bucket under `storage.rules` | (b) Dedicated private bucket, V4 signed URLs |
|---|---|---|
| Client access | Needs the `firebase_storage` SDK, absent from the app today (FACT `storage.rules` header); `storage.rules` must be loosened from deny-all to per-prefix grants | None; client talks only to callables and PUTs to a signed URL |
| Validation | Rules see size and content type only; cannot decompress or validate content | Server validates after upload (quarantine, section 5.2) before promotion |
| Isolation (GPS-PRIV-064) | Shares the default bucket with whatever else lands there; its production state is UNVERIFIED (contract section 11) | Own bucket, own IAM, public access prevention, own lifecycle and soft-delete settings; Body Scan bucket stays untouched |
| Deletion | `deleteFiles` prefix on the default bucket | Same call on the new bucket, mirrors `sweepBodyScanObjects` |
| Precedent in repo | None | Yes (`create.ts` lines 187-196; runbook `runbooks/body_scan_bucket.md`, cited by the contract, not re-read) |

Recommendation (PROPOSED): (b), bucket `<project>-activity-streams-private`, configured by a server setting `ACTIVITY_STREAM_BUCKET` (unset = feature off and sweep is a logged no-op, same as `BODY_SCAN_BUCKET`). Reasons: server-side content validation is the only way to enforce "heart rate never reaches the cloud" against a modified client; `storage.rules` can stay deny-all; the closest working pattern exists. GPS-PRIV-064 forbids sharing the Body Scan bucket: honoured. OPEN: bucket creation, IAM, soft-delete and versioning disabled or windowed (GPS-PRIV-078) are operator/infra steps and are not visible in the repository; a runbook `runbooks/activity_stream_bucket.md` is a deliverable.

### 5.1 Object format and bounds (PROPOSED)

- Object `streams/{uid}/{activityId}/v1.json.gz` (gzip of a JSON document: `schema`, `kinds` map of `SampleStream.toJson()` shapes, `meta`). JSON first because the existing `SampleStream.toJson/tryFromJson` is the reference and FIT/GPX export reads it; a binary delta format is a later optimisation if the size budget fails (OPEN, measured in story S02-06).
- Kinds allowed in the cloud: `gps`, `altitude`, `speed`. `heartRate` is REJECTED by the server validator. `cadence`, `power`, `strokeRate`, `temperature` are not location or health-platform data but D-16 does not name them: default device-only (they are fitness-adjacent data and D-16 named only GPS for the cloud), OPEN for the operator (12.3, DQ-2). The builder side of the same rule is in 3.1 (hard deny of `heartRate`).
- Storage rules with a dedicated bucket (PROPOSED, DQ-12): the default-bucket `storage.rules` stay deny-all. The per-prefix rules tests of GPS-PRIV-064 are replaced by (a) the existing deny-all Storage rules test (`functions/src/__rules__/storage_rules.test.ts`) and (b) functions-level tests of signed-URL minting, ownership and prefix building (5.4). Per-prefix rules tests apply only if default-bucket prefixes (option (a) of the table above) were chosen. The GPS-PRIV-064 AC wording is amended accordingly in the contract.
- Bounds: compressed <= 5 MiB (signed-URL length-range header, same mechanism as `UPLOAD_LENGTH_RANGE`, FACT); decompressed <= 32 MiB (zip-bomb guard, validator streams and aborts); <= 200 000 samples per stream (about 55 h at 1 Hz); latitude -90..90, longitude -180..180, offsets strictly increasing (FACT `SampleStream.validate`). All values are starting proposals, not measured.
- `meta` (PROPOSED, round 1): laps (closed lap schema without any HR field) and the provenance list (closed provenance schema). `userEdits` and `mergeNotes` are NOT in the object: the local `record.json` is their single source, so the object cannot go stale after an edit. The object is an immutable snapshot of streams at upload time; edits do not trigger a re-upload.

### 5.1a Server validation is a closed schema (PROPOSED, round 1)

"Heart rate never reaches the cloud" is enforced by a server-side closed schema, not by a client strip or a kind-name check alone:

- The commit callable parses the decompressed JSON into typed structures and REJECTS (does not strip) any unknown key at any depth. Closed key sets: top level (`schema`, `kinds`, `meta`), one key set per allowed stream kind (the exact names come from `SampleStream.toJson`; a test pins them), a closed lap schema, a closed provenance-record schema. Numbers must be finite; strings carry a length bound and regex; lists carry a count bound.
- The object stored in `streams/` is RE-SERIALISED canonically from the parsed structure; the uploaded bytes are never promoted. `storedSha256` is the hash of the re-serialised bytes.
- Honest limit (stated in the runbook and privacy text review): heart-rate values disguised as another numeric stream (for example sent as a series labelled `speed` or `altitude`) cannot be detected by any structural check; the server can only bound shapes and ranges (plausibility ranges per kind are a cheap partial defence, not a guarantee). ACCEPTED RESIDUAL RISK (PROPOSED, DQ-6): HR relabelled as an allowed kind, or smuggled in a counter (telemetry, 8.1), cannot be detected. Mitigations are closed schemas, small explicit counter ranges and sentinel tests; the privacy text and the contract state this limit instead of claiming a guarantee against a modified client.
- Tests: payloads carrying `avgHrBpm`, `hr`, or any unknown key in `meta`, a lap, a provenance record, a stream record or the top level are rejected; a clean payload is stored byte-equal to its canonical re-serialisation.

### 5.2 Upload path and quarantine

Writer: the client PUTs bytes to a V4 signed URL; the server validates and promotes. GPS-PRIV-080 targets photos; the same quarantine-then-promote shape is applied to streams as a hostile-input rule (PROPOSED, not demanded by the contract). Revised in round 1 as a state machine on the index row (`pending` -> `stored` -> `expired` | `deleted`); all callables follow the shared hardening of 5.4.

1. `createActivityStreamUpload(activityId, bytes, contentSha256)` (PROPOSED, round 1). In ONE Firestore transaction it reads and checks: the delete fence (`accountDeletionRetries/{uid}` absent, `users/{uid}` present, `activity_settings/main.deleteFenceAt` unset; section 6.1), the tombstone (absent), the summary document (present), the `cloudStreams` consent (current, not withdrawn) and the existing row. Any failure returns a bare code. If the row is `stored` with the same `contentSha256` it returns success `already_stored` and no URL. Otherwise it writes the row `pending` with a server-generated `uploadId`, `pendingSince`, and `attempts + 1` (cap 5 per activity per day, then bare code `too_many_attempts`); a new upload supersedes an older pending `uploadId` and deletes that quarantine object. It returns a V4 PUT URL for `quarantine/{uid}/{activityId}/{uploadId}` (TTL 10 min, content type `application/gzip`, length range).
2. `commitActivityStream(activityId, uploadId)` is idempotent (PROPOSED, round 1): (a) transaction 1 re-checks fence, tombstone, summary, consent and that `uploadId` is the row's current one (else bare `superseded`); a row already `stored` with the same `contentSha256` returns success. (b) It reads the quarantine object ONCE: metadata first, then the bytes pinned to that object generation (`ifGenerationMatch`), into memory (<= 5 MiB); a changed generation rejects the commit. The SAME in-memory bytes are hashed against `contentSha256`, decompressed, validated (5.1a) and re-serialised, so the validated bytes are exactly the promoted bytes (no overwrite window between check and promotion). Decompression is bounded by an absolute cap (32 MiB), a compression-ratio limit (decompressed/compressed <= 20) and a wall-clock budget (10 s); breaching any aborts the stream. (c) It writes `streams/{uid}/{activityId}/v1.json.gz`. (d) Transaction 2 re-checks fence, tombstone and `uploadId`, then sets `state = stored`, `bytes`, `kinds`, `storedSha256`, `expiresAt` (hint) and `settingsGeneration` read in the same transaction (5.3). If transaction 2 refuses, the callable deletes the promoted and the quarantine object (compensation) and returns a bare code; a crash between (c) and (d) is covered by the late sweep and the reconciler (6.1). Two concurrent commits with different `uploadId` yield exactly one stored row and no stray quarantine object.
3. Any validation failure deletes the quarantine object, restores the previous row state (or removes a never-stored row) and returns a bare code.
4. Client retry (PROPOSED, round 1): bounded, at most 5 attempts per run with exponential backoff and jitter and a total of at most 10 minutes; resumable from the journal: an `uploading` line carries `uploadId` and attempt count, a restart resumes at commit if the PUT completed, otherwise creates a new upload; the `synced` marker is written only after commit success; after the cap the entry stays `upload_failed` and is retried at the next app start (never a hot loop).

A scheduled late sweep for abandoned `pending` rows and quarantine objects (every 5 minutes pattern, FACT `purge.ts` line 527) is part of the reconciler (section 6.1). A bucket lifecycle rule on the `quarantine/` prefix (age 1 day) is a backstop; an age rule is valid there because quarantine data has no user-set expiry (it is NOT valid for `streams/`, 5.3).

### 5.3 Expiry mechanism

A bucket lifecycle rule is by object age, global, and cannot represent a per-user setting; with a "never" option it cannot be used even as a backstop for `streams/` (a backstop shorter than "never" would silently break the setting). PROPOSED (revised in round 1):

- Effective expiry is DERIVED at purge time: `activityDateUtc + current streamRetentionDays` (null setting = never). `activityDateUtc` is taken server-side from the summary `startUtc`, clamped to [2000-01-01, request.time], never from a client parameter. The stored `expiresAt` is only a HINT for the query; it can never extend retention because purge re-derives. This removes the commit-versus-recompute race (a commit that stamped an old retention is corrected by the derivation).
- Row bookkeeping: `expiresAt` (hint), `settingsGeneration`, `purgeAttempts`, `lastErrorCode` (bare code), `lastPurgeAttemptAt`.
- Scheduled `purgeExpiredActivityStreams` (daily, `onSchedule` like `purgeExpiredBodyScanPhotos`, FACT) queries collection group `activity_streams` where `state == stored` and `expiresAt <= now` (composite index 1, section 4), in pages with a run budget (reuse `PAGE` and `PURGE_RUN_BUDGET_MS` from `purge.ts`, FACT constants named by the reviewer). For each candidate a transaction re-reads the row and the settings, re-derives the effective expiry and, if not due, only rewrites the hint. If due: delete the object FIRST (404 = success), then set `state = expired` (row kept so the app can show "stream expired"; summary stays). Failure: `purgeAttempts + 1`, `lastErrorCode` set, next run retries.
- No give-up state: after `MAX_PURGE_ATTEMPTS` the row keeps being retried every run (GPS kept past its expiry is a privacy defect, so a cap may slow alerts but never abandon the row) and the overdue-age signal (6.3) alerts.
- Setting change (`setActivityCloudSettings`): one transaction updates `streamRetentionDays`, increments `settingsGeneration` and resets `recomputeCursor`. Recompute is resumable: pages of rows ordered by id from `recomputeCursor`, each row rewritten in a transaction (hint and `settingsGeneration`), cursor advanced per page, continuation scheduled every 5 minutes until done; a final pass queries `state == stored` and `settingsGeneration < current` (composite index 2) to catch rows committed with an older generation. Crash mid-way and rerun is consistent; a purge racing a lengthen leaves the object (re-derivation says not due).
- Shortening makes old streams due at the next purge run (once hints are rewritten); lengthening does not resurrect expired ones (stated in UI copy). Options offered (PROPOSED, contract example list; DQ-7): 90 days, 1 year, 2 years (default, shown), never. OPEN for the operator: whether "never" is offered at all ("never" means indefinite storage of GPS history; the operator chose a user-set expiry, not an unlimited one) and whether 2 years stays the default (12.3).
- Signals: oldest overdue age, count of capped rows and recompute backlog are in the table of 6.3 (counts and ages only, no uid; GPS-PRIV-048 compliant).

### 5.4 Shared hardening for every new callable (PROPOSED, round 1)

Applies to `createActivityStreamUpload`, `commitActivityStream`, `deleteActivity`, `setActivityCloudSettings`, `getActivityStreamDownloadUrls` and the telemetry callable (section 8).

- Input validation first: `activityId` must match `^act_[0-9a-f]{40}$` before any path is built (an id containing `/` is refused); `bytes` integer 1..5 MiB; `contentSha256` 64 hex chars; `activityIds[]` at most 20, deduplicated, each validated. `uploadId` is server-generated and validated against its fixed pattern.
- Object paths are built only from `request.auth.uid` and a validated id; no client-supplied path or prefix is ever used.
- Authentication follows the `createBodyScan` pattern (ordinary user only; OPEN: App Check requirement to be confirmed from that code).
- Quota: a named quota action per callable (`activity_stream_upload`, `activity_stream_commit`, `activity_delete`, `activity_download_urls`, `activity_settings_set`, `debug_telemetry_send`), each ADDED to `REDACTED_QUOTA_ACTIONS` in `functions/src/abuse_guard.ts` so logs do not name the uid. Starting limits (unmeasured): 30, 60, 100, 60, 20 and 200 calls per user per day. Over-limit calls return a bare code.
- Errors and logs: bare codes only; no message echoes a client value; logs carry codes and counts only (GPS-PRIV-094).
- Tests: id with `/` refused; each over-limit call refused; captured logs contain no uid, id or coordinate sentinel.

## 6. Retention and deletion

| Item | Design |
|---|---|
| Setting storage | `users/{uid}/activity_settings/main` (server-authored; section 4) |
| Retention clock / C2 | Activity date; derived geometry (C2) lives inside the stream object and follows the same `expiresAt` (D-16 proposal, OPEN until confirmed) |
| Activity delete | Callable `deleteActivity(activityId)` (revised, round 1): write the tombstone first (6.2), then delete stream object(s) in `streams/` and `quarantine/` for that id, then the index row, then the summary document last; idempotent, 404 = nothing to delete; error codes bare; schedules a late sweep (6.1). Client also removes the local journal entry (delete wins, 6.2) and queues a retry if offline |
| Account deletion | Extend `sweepAccountData` (FACT `index.ts` line 2376) with `sweepActivityStreamObjects(uid)` called after `sweepBodyScanObjects` (line 2383): `deleteFiles({prefix: "streams/<uid>/"})` and `quarantine/<uid>/`, with the error contract of lines 2405-2423 (unset bucket = logged no-op, all-404 = done, anything else throws a bare code so `reconcileAccountDeletions` retries). Revised in round 1: the sweep attempts BOTH prefixes, collects failures, then throws ONE bare code (so a failure on the first prefix cannot leave the second untouched while retries are capped at `RETRY_MAX_ATTEMPTS = 12`, reviewer-cited `index.ts` line 2446). Firestore rows are removed by the existing `recursiveDelete(users/{uid})`; the full ordering is in 6.1 |
| Orphan reconciler | Scheduled function: index rows without summary, objects without an index row older than the upload TTL, `pending` rows older than 1 hour (`pendingSince`); GPS-PRIV-077 pattern; failure-injection tests kill after each cascade step. Repair rule (round 1): when a valid object exists whose hash matches a `pending` row, the summary exists and the fence and tombstone are clear, the reconciler REPAIRS the row to `stored` (a crash between promotion and the `stored` write must not lose a good upload); otherwise it deletes. A `stored` row whose object is missing becomes `deleted` and raises a signal |
| Local | Journal wiped on sign-out and account deletion per GPS-PRIV-085 |
| `scripts/ci/data_lifecycle_policy.json` | New rows (round 1 adds `activity_tombstones`: BOTH, read OWNER, writes NONE; and `activity_late_sweeps`: server-only, client NONE) `activities` (BOTH; clientAccess read OWNER, create/update CONDITIONAL with `conditionalRefs` to the rules tests, delete NONE), `activity_streams` (BOTH; read OWNER, writes NONE), `activity_settings` (BOTH; read OWNER, writes NONE), mirroring the `body_scans` entry shape (FACT lines 585-603) |
| `DATA_LIFECYCLE_MATRIX.md` | Update C1/C2 (cloud: private object, user-set expiry, activity-date clock), C8 (cloud: never), section 3 sweep-map rows for `users/{uid}/activities` and Storage `streams/{uid}/`, section 4 gap rows (Storage cleanup, export) and the new-bucket row; same PR (matrix section 5, FACT) |
| Privacy text | `public/privacy.html` must state GPS upload, the expiry setting and that heart rate stays on the device before the flag is enabled (contract D-16 row); stale lines 91, 95, 100 per matrix section 4 are not changed by S02 code but by this text change (PROPOSED, DQ-10: the S02 implementation PR owns the text edit, see 12.1) |

### 6.1 Delete fence, ordering and late sweep (PROPOSED, round 1)

Problem: Body Scan reads a delete fence inside its create transaction (reviewer-cited `functions/src/body_scan/create.ts` lines 294-298) and runs a late sweep sized to the URL TTL (`shared.ts` lines 192-194); a stream upload design without both lets a still-valid 10-minute signed URL, or a commit racing a delete, recreate GPS objects after erasure.

- Fence: create and commit callables read, inside their transactions, `accountDeletionRetries/{uid}` (refuse if it exists), `users/{uid}` (refuse if gone) and `activity_settings/main.deleteFenceAt` (refuse if set). The account-deletion path sets `deleteFenceAt` as its first step, so the fence does not depend on when `accountDeletionRetries/{uid}` is written (OPEN: verify that ordering in `index.ts`). Per-activity fence = the tombstone (6.2).
- Account deletion order: (1) fence; (2) `sweepActivityStreamObjects` (both prefixes attempted, one bare code on failure); (3) existing `recursiveDelete`; (4) Auth deletion; (5) a SECOND prefix-only sweep after Auth deletion (needs no Firestore rows); (6) a deferred late sweep.
- Late sweep: a server-only top-level collection `activity_late_sweeps` (outside `users/{uid}`, so it survives `recursiveDelete`) holds one job per deletion with `uid`, scope (`activity` with id, or `account`) and `runAfter = deletion time + 10 min URL TTL + 5 min margin`. A scheduled function (every 5 minutes, pattern of `sweepLateBodyScanUploads`) deletes `quarantine/<uid>/` and `streams/<uid>/` (or the activity sub-prefix), then removes the job. The collection gets its own `data_lifecycle_policy.json` row (server-only, client NONE) and a rules deny (OPEN: confirm top-level default deny in `firestore.rules`).
- Commit after delete: commit re-checks fence and tombstone in transaction 2 and compensates (5.2), so a commit racing `deleteActivity` promotes nothing that survives the late sweep.
- Tests: seed a signed URL, delete the account, PUT afterwards: the object is gone after the late sweep; commit after `deleteActivity` promotes nothing; inject a commit between the Firestore delete and the sweep: after reconcile both prefixes are empty; prefix A fails and B succeeds: the sweep throws one bare code and B is empty.

### 6.2 Resurrection: tombstone, delete wins (PROPOSED, round 1)

Problem: the summary is client-writable and ids are deterministic (`activityIdFor`), so a queued offline `put` from another device, or a re-sync, recreates a deleted summary (and could re-upload a stream).

Choice: a server tombstone, NOT summary writes behind a callable. Reasons: a callable-only summary write path removes offline-first (the Firestore offline queue is the S02 sync mechanism), and Admin-SDK writes bypass rules so the shape checks of section 4 would have to be duplicated in TypeScript (two validators drifting). With a tombstone, rules stay the single shape gate and cost one `exists()` lookup per summary write (well under the per-request lookup limit).

- `deleteActivity` creates `users/{uid}/activity_tombstones/{activityId}` (`deletedAt` server time, `expireAt` for the TTL policy) before deleting anything. Rules deny summary create/update for a tombstoned id (section 4); all callables refuse a tombstoned id (bare code `deleted`).
- TTL: proposed 400 days, chosen to exceed any realistic offline replay window (OPEN: operator may change it; TTL policy is an infra step). Residual risk after expiry, stated: a very stale queued `put` could recreate a scalar summary (no geometry, no stream: the stream callables would still need a new upload under consent). Accepted because the summary holds no geometry.
- Cross-device rule, DELETE WINS: devices read the owner-readable tombstone ids; on sync, a local journal entry whose id is tombstoned is marked deleted in `record.json` (a tombstone line, 10) and its local data is removed; a permission-denied on a summary `put` is interpreted the same way. Consequence for users: re-importing the same external session (same `sourceId|externalId`) while its tombstone lives is refused; native recordings (new uuid) are unaffected.
- Test: replay a `put` after `deleteActivity`: no summary, no stream; the other device removes its local copy on sync.

### 6.3 Operations signals (PROPOSED, round 1)

Metrics carry counts, ages and bare codes only; never a uid, coordinate, id or path. Each has an alert threshold, an owner role (OPEN: named person) and a forced-failure check that must turn the signal on. Runbook: `runbooks/activity_stream_bucket.md` (deliverable).

| Signal | Alert | Owner role | Forced-failure check |
|---|---|---|---|
| Count and oldest age of `pending` rows | oldest > 1 h | backend on-call | seed a pending row 2 h old; signal fires, reconciler clears it |
| Quarantine object count and oldest age | oldest > 1 day (lifecycle backstop) | backend on-call | put an old object; signal fires |
| Account/late/orphan sweep failures by bare code | any failure on 2 consecutive runs; any `accountDeletionRetries` row older than 1 day | backend on-call | fake bucket failing one prefix; code counted |
| Purge failures by code, capped-row count, oldest overdue age | overdue > 2 days; any capped row | backend on-call | make delete fail for one row; row stays retried, age grows |
| Recompute backlog (rows with `settingsGeneration` < current) count and age | age > 1 h | backend on-call | stop the continuation after one page; backlog visible |
| Validator rejections by code (`hr_kind`, `unknown_key`, `bomb`, `bad_sha`, `generation_changed`) | spike vs daily baseline | security reviewer | send one payload per code |
| Fence/tombstone refusals by code | informational; spike | backend on-call | commit after fence set |
| Telemetry rejections by code, quota refusals, client-reported dropped-event counter (bounded counter) | spike vs baseline | backend on-call | oversize and over-quota batches |
| Missing composite index (FAILED_PRECONDITION on purge/recompute query) | any | backend on-call | run the queries on an emulator without the index entry |

## 7. Export

| Item | Design |
|---|---|
| Summary rows | `account_export.ts`: add `sub(uid, "activities", truncated)` and `sub(uid, "activity_streams", truncated)` (stream index rows, no bytes) and `one(users/{uid}/activity_settings/main)` using the existing helpers (FACT lines 101-130); `MAX_ROWS = 2000` cap and `truncated` reporting unchanged. Add paged continuation section for `activities` if 2000 rows is insufficient (OPEN: the paging code was not read; 100 sessions per user is far below the cap, but a heavy user may exceed it) |
| Streams | NOT in the response body (GPS-PRIV-052; budget 8 MiB, FACT line 55). New callable `getActivityStreamDownloadUrls(activityIds[])` (max 20 per call, owner only) returns V4 GET signed URLs, TTL 15 minutes, single object each, never logged (GPS-PRIV-094; log redaction test). Export response lists each stream with `state`, `bytes`, `expiresAt` and a note: "heart-rate streams are on your device only and are not part of this export" (GPS-PRIV-053) |
| No-GPS sessions (PROPOSED, DQ-3) | GPX export of a session without a GPS stream returns the typed result `no_geometry` (the UI says there is nothing to export as a route); no empty GPX file is produced. FIT and summary export of a no-GPS session is allowed. Both paths have tests |
| FIT / GPX export | Done on the device from stored data (local journal or downloaded stream), so no server conversion. Pure encoders `GpxEncoder` and `FitEncoder` take an `ActivitySession` and return a string/bytes structure; they live in `activity/data` (no `dart:io`); file writing and sharing are outside. GPX 1.1 `trk/trkseg/trkpt` with `ele`, `time`; FIT as the minimum record set (file_id, session, record) with CRC. HR is included when present locally (it is the user's own data on their own device); route trimming (`routeTrimMeters`, default 200 m, FACT `ActivityPrivacy`) applies to SHARED exports only, a full-series export for the owner is the GPS-PRIV-051 requirement. OPEN: a FIT validator is not available in the repo; acceptance is a structural round trip through a test-only decoder written for the sprint |
| Import | None (non-scope) |

### 7.1 Sizing and download results (PROPOSED, round 1)

- Worst-case export size test (S02-07): seed 2000 rows of EACH new type (`activities`, `activity_streams`) with every key at its maximum size, plus the existing sections at their caps, and assert the response stays within the 8 MiB budget through `fitToByteBudget`/paging and that `truncated` is reported correctly. Reviewer estimate, unmeasured: 2000 summaries at about 1.5 KB is about 3 MB and 2000 stream rows at about 0.4 KB is about 0.8 MB, so the existing sections could push the total over budget.
- Row cap: at 3 workouts per day the 2000-row cap is reached in about 2 years (architect estimate). The architect reviewer cites an existing paging path (`fitPaged`, `account_export.ts` lines 422 and 552; not re-read here). S02 uses that path for both collections, and the test seeds 2500 rows to prove continuation. This replaces the OPEN paging remark in the table above once S02-07 confirms it.
- `getActivityStreamDownloadUrls` result, per requested id: `stored` -> URL plus expiry; `expired` -> code `expired`; `pending` -> `not_ready`; `deleted`, tombstoned, missing or not owned -> the same code `not_found` (no existence oracle). Never a URL for a non-stored row; quota action in 5.4; max 20 ids, deduplicated. Tests cover each state.

## 8. Debug telemetry server guarantee (GPS-PRIV-050 / 098)

Facts: client writes `debug_sessions` directly (`debug_telemetry_sink.dart` line 36); rules check keys and `events.size() <= 500` only (FACT lines 367-378); the sink is documented DEBUG-builds only (matrix section 2).

| | A. Sanitising callable | B. Per-event documents |
|---|---|---|
| Closed schema enforced | Fully, per element, in TypeScript (types, enumerations, bounded counters, no free text), whole batch rejected on violation | Rules check every key/type/range per document; but each event type needs its own rules function and the number of events (500) becomes 500 writes per session |
| Rules limits | None needed; `debug_sessions` write becomes `if false` | Cannot check strings beyond regex/size; enumerations and ranges are doable |
| Cost / change | One callable + client sink change; existing collection layout and export/sweep (`owned("debug_sessions","uid")`, FACT policy row) unchanged | New subcollection, new export/sweep/policy rows, 500x writes, new rules tests |
| Fits the Phase 1 path | Yes: same document shape written by Admin SDK | No: shape changes |

Recommendation (PROPOSED): option A. Reasons: per-element validation is complete; fewer moving parts; the export and deletion wiring for `debug_sessions` stays as is. Migration: the Phase 1 sink switches from `.add` to the callable; rules change `allow create` to `false` for clients; because the sink is DEBUG-only (matrix, FACT) there is no production client population to keep compatible, but an old debug build would get permission-denied (swallowed, OPEN: confirm the sink swallows errors) and Phase 1 behaviour change is recorded in the sync log (contract 098 "must keep the current Phase 1 behaviour documented in the sync log"; OPEN: sync-log file path not located). Negative tests (modified client): coordinate pair, geohash, HR value, place name each as a top-level value, nested map, and list element; each is rejected and nothing stored; a valid event from the real client is accepted; the client schema unit test still fails if a location or HR event type is added. The client-side redaction extension (`debug_telemetry.dart`, no coordinate/HR rule today per the explorer) stays as an additional defence.

### 8.1 Telemetry callable hardening (PROPOSED, round 1)

A "bounded identifier pattern" regex or a wide counter can carry a geohash, a latitude scaled to an integer or a heart-rate value, so the closed schema is stricter than the contract minimum:

- The closed telemetry schema (event types, named counters and their explicit maximum ranges) is a story deliverable (S02-09) DEFINED BEFORE any code and reviewed by security-reviewer (PROPOSED, DQ-8); this document fixes only the principle below, and the test plan uses sentinel values. Residual risk of a counter carrying HR: 5.1a (DQ-6).
- Strings come from ENUMERATIONS only (event type, level, component names); no free text, no regex-identifier strings. Numbers are named counters with small explicit ranges per field (for example 0..255 or 0..65535; the table of fields is pinned by a test). No nesting: events are flat maps; no lists inside events. `uid` and `receivedAt` are set server-side from `request.auth`; `droppedCount` is a named bounded counter. The whole batch is rejected at the first violation with a bare code; the message never echoes a value.
- Caps: events per call (starting value 100), serialised batch bytes (starting value 16 KiB), callable timeout; per-uid daily quota action `debug_telemetry_send` (5.4) added to `REDACTED_QUOTA_ACTIONS` in `functions/src/abuse_guard.ts`, with a daily event ceiling (starting value 5 000). Limits are unmeasured starting values.
- Client sink (`debug_telemetry_sink.dart`, which per the reliability review has no try/catch and no retry at lines 35-41): catches every send error including permission-denied from an old rules state (never throws into app flow; this resolves the OPEN remark in the migration paragraph above as a requirement, DQ-9: tested with a failing callable), increments a local dropped-event counter, retries at most 3 times with backoff, keeps a bounded local buffer (at most 500 events and 64 KiB, oldest dropped), counts dropped events locally and reports the counter in the next batch. Callers are checked to ensure nothing awaits the send on a user path.
- Deploy order: (1) deploy the callable; (2) ship the client switch (DEBUG builds only); (3) only then change the `debug_sessions` rule to `create: false`. Step 3 is a separately revertible deploy; reverting it returns to the current Phase 1 behaviour and is not part of the permanent rules floor of 12.1.
- Tests: geohash string, 6-digit counter value, nested map and list element are each rejected and nothing is stored; captured logs contain none of the sentinel values; over-limit batches and over-quota days are refused; the callable failing neither throws into the app nor grows memory unboundedly; the quota-exceeded response is a bare code.

## 9. Consent matrix and native-session dedup

Consent is checked at three points: platform permission (S16), local persistence, cloud upload. PROPOSED matrix (S02 implements the cloud-upload column and the model; permission prompts belong to S04/S16):

| Source (`SourceKind`) | Datatype | Local persist | Cloud summary | Cloud stream |
|---|---|---|---|---|
| Native recording (app GPS, S04) | GPS | Yes, with GPS consent | Yes (scalars) | Only with `cloudStreams` consent + flag; user expiry |
| Native recording | HR from BLE | Yes with HR consent | No (`avgHrBpm`/`maxHrBpm` excluded, 3.2) | Never (D-16) |
| `platformHealth` | HR, steps, energy | Per-datatype consent (GPS-PRIV-036/037) | Non-HR scalars only | GPS only if present, same consent as native; HR never |
| `bleSensor` | HR, speed, cadence, power | Per datatype | Non-HR scalars | Cadence/power OPEN; HR never |
| `vendorCloud`, `companionApp` | any | Out of S02 (S17-S21); model accepts them | Same rules as above | Same rules |
| `fileImport` | any | Out of S02 (no import) | n/a | n/a |

Server enforcement: the stream validator rejects `heartRate` regardless of any consent; the summary rules reject HR keys because they are not on the allowlist. Consent records for `cloudStreams` live in `activity_settings/main` (3.2/4); the general Consent centre (`users/{uid}/consents`, GPS-PRIV-009/071) is OPEN for S03/S09 and S02 writes no `consents` document.

Native-session dedup rule (PROPOSED): a native session id is `activityIdFor(sourceId: "app", externalId: <uuid generated at recording start>)`, so a re-sync or re-upload of the same recording hits the same id and upserts (idempotent, FACT id function). The merger rule 1 (same `sourceId|externalId`, FACT line 57) is the only dedup S02 promises. The merger's time/distance/GPS clustering is kept as is for tests but S02 makes NO promise that native sessions are matched with platform-health, BLE or vendor sessions (S17); user-facing copy must not claim it. Executable guard (PROPOSED, DQ-13): a Dart copy-lint test scans the localisation resources and S02 screens for dedup or duplicate-removal promises (a small word list agreed in S02-10) and fails if one appears.

### 9.1 Consent withdrawal (PROPOSED, round 1)

When the user withdraws `cloudStreams` consent, `setActivityCloudSettings` records `cloudStreams.withdrawnAt` and increments `settingsGeneration`. From then on `createActivityStreamUpload` and `commitActivityStream` refuse with bare code `consent_withdrawn`; `pending` rows are aborted by the reconciler; the client stops any queued upload. The app OFFERS (does not force) "delete my cloud streams now", which removes stream objects and rows for all activities while keeping scalar summaries; individual activity deletion stays available. Without that choice, stored streams remain until their user-set expiry. Summaries and streams are never exposed to friend or public paths in S02, and S09 must not derive public artefacts from summary fields (3.2). Test: after withdrawal the upload callable refuses and the bulk deletion option works.

## 10. Merger performance and crash safety

Performance (PROPOSED budget, to be calibrated on the first run; not measured today):

| Item | Assumption / budget |
|---|---|
| Data volume | 100 sessions per merge call in the gate; planning ceiling 2 000 sessions per user and up to 3 candidates per real workout; streams 1 Hz, up to 4 h = 14 400 GPS points; heavy 12 h = 43 200 |
| Algorithm facts | clustering is O(sessions x clusters), echo detection O(sessions^2) (FACT, merger lines 72-85, 100-119); GPS comparison uses binary search per point (O(points log points)) |
| Budget | PROPOSED (round 1): the ONLY gate is an operation count, because CI is not run and the phone factor is a guess. For 300 candidates (100 workouts x 3 sources) the number of pairwise comparisons must stay at or below 100 000, and for 2 000 sessions without streams at or below 4 000 000 (the quadratic echo detection is n^2/2 = 2 000 000 at n = 2 000, so the ceiling is twice the analytic count); both numbers are starting values to be calibrated on the first run and then frozen. Wall-clock time (about 2 s for 300 candidates, 1 s for 2 000 sessions) is recorded as information only and is NOT a pass/fail criterion, and no wall-clock threshold is ever derived from the first run (DQ-14). The measured ceiling is recorded in S02-10 |
| Measurement | one focused test, `activity_merger_perf_test.dart`, generating the synthetic corpus (below) and asserting the operation count only (round 1). Instrumentation seam (PROPOSED): an optional named parameter `onPairCompared` (a `void Function()?`, default null) on the merge entry point, invoked once per pairwise comparison; with null the behaviour and results are identical, so there is no merger behaviour change and the test needs no private-name hook (OPEN: the exact merge signature and the comparison function name were not re-read in this revision; the parameter is added at the real comparison call site). The merge runs in an isolate (`compute`) from the repository if the count exceeds the budget. Authored and run by the test agents per workflow, not by this document |
| If over budget | pre-bucket sessions by day (sort by start, compare only neighbours within the policy window) and index echo lookup by `appPackage`; behaviour must stay order-independent (ACT-05..13 stay green) |

Crash safety of the local journal (PROPOSED, revised in round 1):

- Write order per mutation: (1) `streams.bin` (temp file, flush, fsync, rename), (2) `record.json` (same procedure), (3) directory fsync after each rename, (4) the `index.jsonl` line (append, fsync). An old file is never deleted before its replacement is durable. A record whose stream file is missing at start is recovered as `streamLost` (3.5) rather than dropped.
- `record.json` is the truth; `index.jsonl` is a rebuildable cache. Delete tombstones and the `synced` state live in `record.json`, so an index rebuild from the record files loses neither (a rebuilt index must not resurrect deleted ids or re-upload synced ones). On start the repository ignores a torn last index line and deletes orphan temp files.
- Single writer: the repository owns the journal behind an in-process mutex (an async lock); the compute isolate and the S04 recorder submit mutations through it and never touch files directly. Cross-process writers are not supported.
- Full disk and I/O errors: a `FileSystemException` (including disk full and rename failure) aborts the mutation, leaves the previous durable state intact, surfaces a typed error ("storage full") and keeps the recording in memory for retry; it never half-writes a record.
- Ordering and expiry use monotonic counters (a per-journal sequence number in index lines and `record.json`), not wall-clock timestamps, so a device clock change cannot reorder mutations; `updatedAt` stays informational only.
- `synced` markers are written only after the commit callable returned success, so a crash after upload re-uploads idempotently (`already_stored`, 5.2).
- Tests with an injectable fault-injection file system failing at each step (temp write, flush, rename, directory sync, index append) including disk full: previously committed sessions survive in every case; truncate the index at every byte offset of the last line; delete the index and rebuild with tombstones intact; two concurrent writers serialise through the mutex.

## 11. Stories, acceptance and DoD

All 100-session data is SYNTHETIC: no real user data and no fixture corpus exist (explorer FACT, `S02_CODE_MAP.md`). A deterministic generator (seeded PRNG, test-only, in `mobile/test/support/`) builds 100 "real-shaped" sessions: mix of the 12 `SportType` values, 1-3 sources per workout, 0-40% with GPS streams of 600-14 400 points, HR streams on 60%, laps on swims and runs, platform-health echoes, one split-session pair, unknown sport strings, unknown extra keys, and 5 records at `schema = 1`. Coordinates are fabricated tracks on a synthetic grid, never copied from any person.

| Story | Content | Acceptance (test type) | Ids |
|---|---|---|---|
| S02-01 Model v2 | A-5 fields, `schema = 2`, migration chain, `ActivityCloudSummary`, `ActivityStreamPayload` | Round trip of the 100 sessions through `toJson` -> migrate -> `tryFromJson` equal (unit); `schema = 1` and unknown-key records survive; summary keys subset of the rules allowlist; summary contains no list, no geometry, no HR (unit) | 072, 036 |
| S02-02 Local journal | File journal, index, crash safety, backup exclusion, wipe | Crash tests of section 10; both XML backup files exclude the constants (check); journal bytes contain no plaintext coordinates (test) | 014, 083, 084, 085 |
| S02-03 Firestore rules | Exclusions in both clauses, three blocks | Emulator rules tests of section 4 incl. exclusion-removal falsification and canary | 058, 060, 061, 070, 071 |
| S02-04 Stream upload | Bucket setting, `createActivityStreamUpload`, `commitActivityStream`, validator | HR kind rejected; oversize, zip-bomb, bad sha, non-monotonic, out-of-range lat/lon rejected; quarantine unreadable; valid upload promoted (functions tests with a fake bucket) | 013, 059, 064 |
| S02-05 Retention | Settings callable, `expiresAt`, purge, overdue metric | User sets 90 days: rows recomputed; purge deletes due objects and keeps summaries; "never" not purged; second run no-op | 015 |
| S02-06 Deletion | `deleteActivity`, `sweepActivityStreamObjects`, orphan reconciler | Delete activity removes object, row, summary; account deletion empties both prefixes, second run no-op, injected failure retried by the reconciler | 054, 055, 066, 076, 077 |
| S02-07 Export | `account_export.ts` additions, download-URL callable, FIT/GPX encoders | Seeded record appears in export or declared delivery, over-cap reported in `truncated`; signed-URL TTL and no URL in logs; GPX/FIT structural round trip on the 100 sessions | 051, 052, 053, 067, 068, 094 |
| S02-08 Lifecycle docs | Policy rows, matrix update, bucket runbook, privacy text request | `data_lifecycle_policy` checkers pass (existing checkers named in the file `_comment`, FACT); matrix rows present | 004, 065 |
| S02-09 Telemetry guarantee | Option A callable, rules `create: false`, sink migration | Negative tests of section 8 | 050, 098 |
| S02-10 Merger perf and dedup | Perf test, native-id rule, A-1..A-3 interfaces | Perf budget of section 10; same recording twice yields one id; no external dedup claim | - |

S02 gate mapping (roadmap line 80): "round trip of 100 real-shaped sessions" = S02-01 + S02-07 on the synthetic corpus; "deletion removes streams" = S02-06; "lifecycle rows" = S02-08; "no external-source dedup promise" = section 9 and S02-10. Per workflow, test-writing agents (functional-test-reviewer, e2e-runner) write and run the test sets; this document does not run any test.

Round 1 additions to acceptance (PROPOSED), assigned to the stories above: S02-01 ownership table constant and test (3.6); S02-02 sign-out warning and export, key-loss `streamLost`, fault-injection file system, mutex, tombstones surviving index rebuild (3.5, 10); S02-03 tombstone and startUtc clamp rules tests (4); S02-04 closed-schema rejection, generation-pinned commit, ratio and time limits, idempotent and concurrent commit, retry policy, id/path validation and quota (5.1a-5.4); S02-05 derived expiry, recompute resume, purge race, capped-row retry, two indexes (5.3, 4); S02-06 fence, late sweep, second sweep, both-prefix sweep, tombstone replay, consent withdrawal (6.1, 6.2, 9.1); S02-07 worst-case export size test and download-URL result states (7.1); S02-09 telemetry hardening tests and deploy order (8.1); S02-10 operation-count gate (10) and the copy-lint test for no dedup promise (9); section 14 answers DQ-1..DQ-15 add: builder HR hard-deny test (S02-01), no-GPS GPX `no_geometry` test (S02-07), rules-text lint and immutability tests (S02-03), sink error-swallow test (S02-09); S02-08 adds policy rows and the signals table of 6.3 with forced-failure checks.

DoD: all stories' tests green; rules and policy rows merged in the same PR; matrix updated; change record per commit; no GPS flag enabled by default.

## 12. Rollout, flags, risks, open questions

### 12.1 Flags and rollout (PROPOSED)

| Flag | Default | Effect |
|---|---|---|
| Client build flag `ACTIVITY_CLOUD_STREAMS` (pattern `BODY_SCAN_CLOUD`, FACT `body_scan_flags.dart` line 44) | OFF | OFF = device-only: journal and summary only, no stream upload code path is reachable (GPS-PRIV-013) |
| Server setting `ACTIVITY_STREAM_BUCKET` | unset | Unset = callables refuse, sweep is a logged no-op |

Order: ship rules, summary sync and journal first (no geometry anywhere in the cloud); enable streams only after the privacy text is updated (contract D-16) and the bucket runbook is executed. Privacy text ownership (PROPOSED, DQ-10): the S02 implementation PR owns the change to `public/privacy.html` and the in-app text (GPS upload, user-set expiry, heart rate stays on the device, the residual-risk limit of 5.1a); wording is drafted in S02 and reviewed by GPT-PM; `ACTIVITY_CLOUD_STREAMS` stays OFF until that text is merged. This replaces the OPEN "owner of the text edit" remark in section 6. The exclusion floor below is guarded by the rules-text lint and emulator write tests of section 4 (DQ-4). Phase 1 impact: the new collections are additive; the only Phase 1 behaviour change is the telemetry write path (section 8), to be recorded in the sync log. Rollback (revised, round 1): by FLAG only. Turn both flags off; summaries remain valid; stream objects remain until the purge or user delete. The rules exclusions for `activities`, `activity_streams`, `activity_settings` and `activity_tombstones`, and their deny/shape blocks, are a PERMANENT FLOOR and are never reverted: reverting the exclusions would make `activity_streams` and `activity_settings` client-writable through the wildcard with no shape check (a user could forge `cloudStreams` consent, `expiresAt` or `objectPath`). The earlier statement that rules additions can be reverted is withdrawn. The telemetry change (section 8.1) is a separate deploy step with its own order (callable first, rules tightening last) and may be reverted independently.

### 12.2 Risks

| Risk | Mitigation |
|---|---|
| Summary allowlist drifts from `ActivitySummary` | Shared-constant test parsing `firestore.rules` |
| Purge lag leaves expired GPS in the cloud | Overdue-age metric, daily run, attempt cap |
| Sports/sources added later break rules | Open regex for `sport`, `schema` bump and migration chain |
| Third workout model (`WorkoutSession`, `WorkoutLogEntry`) confuses users | Ownership contract of 3.6: no dual write, separate readers, no UI merge in S02; bridging is S03 (OPEN) |
| Deleted activity resurrected by another device or a queued put | Tombstone with TTL, delete wins (6.2) |
| Upload after deletion recreates GPS objects | Delete fence, late sweep, second sweep, quarantine lifecycle rule (6.1) |
| Rules revert reopens client writes | Permanent rules floor, rollback by flag only (12.1) |
| Silent purge or sweep failure | Signals table with forced-failure checks (6.3) |
| Plaintext journal in cloud backup | Backup exclusion + encryption (083/084) |
| Estimates in sections 5.1 and 10 are unmeasured | Marked PROPOSED; calibrate in the sprint |

### 12.3 Open questions (operator / GPT-PM)

1. Default expiry value (2 years proposed), whether "never" is offered, and whether C2 follows the stream setting (contract OPEN items). OPERATOR ANSWER NEEDED (DQ-7): the default expiry value, and whether the "never" option exists ("never" = GPS history kept indefinitely).
2. May non-HR sensor streams (cadence, power, stroke rate, temperature) go to the cloud, or only gps, altitude, speed? OPERATOR ANSWER NEEDED (DQ-2); default until answered: device-only, only gps, altitude, speed go to the cloud.
3. May `avgHrBpm`/`maxHrBpm` scalars be stored in the cloud summary (proposed: no)?
4. Option A (callable) vs B (per-event) for telemetry: confirm A.
5. Who creates the private bucket and when; soft-delete/versioning windows (GPS-PRIV-078/079 SLA still open).
6. Privacy text owner and wording before the flag is enabled.
7. Unverified here: contents of `S02_CODE_MAP.md`, the paging code and continuation sections of `account_export.ts`, `firestore.indexes.json`, the sync-log path, whether the debug sink swallows permission errors, whether sprint models already carry the A-5 version strings, `runbooks/body_scan_bucket.md`.

8. Round 1 additions: tombstone TTL value (400 days proposed) and TTL policy owner; whether `accountDeletionRetries/{uid}` is written before the sweep starts; exact `SportType`-to-model table and the stats readers (3.6); exact stream/lap/provenance key names for the closed schema; App Check requirement for new callables; quota limits and telemetry caps (all starting values); whether cloud-to-device hydrate is a later sprint (3.5); top-level `activity_late_sweeps` default-deny confirmation; named owners for the signals of 6.3.

9. Operator answers needed (summary; everything else in section 14 is a technical proposal for GPT-PM review): (a) may cadence, power, stroke rate or temperature streams go to the cloud beyond GPS (default: no); (b) is a "never expire" retention option offered (default proposal: offered but flagged); (c) the default expiry value (2 years proposed). Until answered, the defaults stated here apply and the cloud flag stays OFF.

Stale documents found, not changed: `public/privacy.html` lines 91/95/100 (no location or GPS text; contract and matrix section 4 already record this); `DATA_LIFECYCLE_MATRIX.md` retention cells still read "per D-16" (updated by S02-08, not by this document).

## 13. Review dispositions (round 1: architect, reliability, security)

Source reviews: architect (A1-A8), reliability-reviewer (R1-R10), security-reviewer (S1-S6), all at head a5f4a755, verdict NEEDS CHANGES. No finding is rejected. Overlapping findings were merged: deletion race (R1, R2, S1), resurrection (A2, R4), commit/purge state machines (R3, R5, A5, S4, S5), journal (A1, A7, R6), telemetry (R7, S3).

| Finding | Severity | Disposition | Section changed |
|---|---|---|---|
| A1 sign-out wipes only copy; key loss | MAJOR | accepted (hydrate left OPEN, later sprint) | 3.5, 10, 12.3 |
| A2 resurrection, no tombstone | MAJOR | accepted with change: tombstone chosen over callable-only writes | 4, 6.2 |
| A3 rules revert unsafe | MAJOR | accepted | 12.1, 4 |
| A4 three workout models, no owner | MAJOR | accepted (table verification OPEN) | 3.6, 12.2 |
| A5 expiresAt race with retention setting | MAJOR | accepted with change: expiry derived at purge time, hint only | 5.3 |
| A6 object/summary/row drift | MINOR | accepted: edits and notes dropped from object, reconciler repairs | 5.1, 6 table |
| A7 journal multi-writer | MINOR | accepted: mutex, record.json truth | 10 |
| A8 export and scale limits | MINOR | accepted with change: ceiling calibrated in S02-10 as operation count | 7.1, 10 |
| R1 deletion undone by in-flight upload | MAJOR | accepted | 6.1, 5.2 |
| R2 two-prefix sweep contract | MAJOR | accepted | 6 table, 6.1 |
| R3 commit not idempotent | MAJOR | accepted | 5.2 |
| R4 resurrection by sync | MAJOR | accepted (merged with A2) | 6.2 |
| R5 purge/recompute bookkeeping | MAJOR | accepted | 5.3, 4 |
| R6 journal crash safety gaps | MAJOR | accepted | 10, 3.5 |
| R7 telemetry no quota, loss unspecified | MAJOR | accepted | 8.1, 5.4 |
| R8 export budget unproven | MINOR | accepted | 7.1 |
| R9 merger perf measurement | MINOR | accepted: operation count only, seam named | 10 |
| R10 operational visibility thin | MAJOR | accepted | 6.3 |
| S1 no delete fence or late sweep | MAJOR | accepted | 6.1, 5.2 |
| S2 HR enforcement by name check | MAJOR | accepted (disguised HR stated as undetectable) | 5.1, 5.1a |
| S3 telemetry smuggling and abuse limits | MAJOR | accepted | 8.1 |
| S4 commit race and decompression bomb | MAJOR | accepted | 5.2 |
| S5 purge stall, callable input validation | MINOR | accepted | 5.3, 5.4, 4 |
| S6 consent withdrawal, summary re-identification | MINOR | accepted | 9.1, 3.2 |

## 14. Answers to the test-plan design questions (PROPOSED)

The test plan `docs/phase2/s02/S02_TEST_PLAN.md` raised 15 design questions (DQ-1..DQ-15). The answers below are the lead's proposals, PROPOSED until GPT-PM review; three need an operator answer (marked, listed in 12.3 item 9).

| DQ | Question in plain words | Proposed answer | Reflected in |
|---|---|---|---|
| DQ-1 | Can the stream builder ever emit heart rate? | No. The builder hard-denies `heartRate` even if the caller lists it in `allowedKinds`; the server rejects it too | 3.1, 5.1, 5.1a |
| DQ-2 | Which stream kinds may go to the cloud? | Only `gps`, `altitude`, `speed`; cadence, power, stroke rate, temperature stay device-only. OPERATOR ANSWER NEEDED | 3.1, 5.1, 9, 12.3 |
| DQ-3 | What does GPX export do for a session with no GPS? | Typed result `no_geometry`; FIT and summary export still allowed | 7 |
| DQ-4 | How is the "exclusion in both wildcard clauses" floor tested, given reads cannot be negative-tested? | Rules-text lint (names in read AND write clause) plus emulator write tests | 4, 12.1 |
| DQ-5 | Which clock orders updates? | Server `receivedAt` plus a monotonic local counter; client `updatedAt` is a hint; rules do not force `request.time` (offline replay) | 3.2, 10 |
| DQ-6 | What about HR relabelled as an allowed kind or smuggled in a counter? | Accepted, documented residual risk; mitigated by closed schemas, small ranges, sentinel tests | 5.1a, 8.1 |
| DQ-7 | Which retention options exist? | 90 days, 1 year, 2 years (default), never; "never" flagged. OPERATOR ANSWER NEEDED (default value and "never") | 5.3, 12.3 |
| DQ-8 | When is the telemetry schema fixed? | Closed schema (event types, counters, ranges) defined before code and reviewed by security | 8.1 |
| DQ-9 | What does the debug sink do on failure? | Swallows every error (incl. permission-denied), counts dropped events, never throws | 8, 8.1 |
| DQ-10 | Who owns the privacy text change? | The S02 implementation PR, merged before the cloud flag can be turned on | 6, 12.1 |
| DQ-11 | Does GPS-PRIV-014 (delete journal after sync) apply to the S02 store? | No: it concerns the S04 recording journal; the S02 store is the permanent device copy. Contract clarified | 3.4 |
| DQ-12 | How is Storage tested with a dedicated bucket? | Rules stay deny-all (existing test) plus functions-level tests of signed URL, ownership, prefix; per-prefix rules tests only for default-bucket prefixes. Contract AC reworded | 4 (GPS-PRIV-059 row), 5.1 |
| DQ-13 | How is "no dedup promise" made executable? | Copy lint test over localisation resources and screens | 9, 11 |
| DQ-14 | What is the performance gate? | Operation-count assertion only; wall-clock is informational, never a threshold | 10 |
| DQ-15 | Can `startUtc` and `sport` change after creation? | No: immutable (they feed the id); edits go to `userEdits`; rules enforce unchanged values | 3.2, 4 |
