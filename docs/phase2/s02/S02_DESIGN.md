# S02 design: Unified activity (E1)

Status: DRAFT for GPT-PM review. Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. No code is changed by this document.
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
| `updatedAt` | timestamp | client clock; not trusted for ordering (OPEN: use `request.time` as Body Scan consent does, FACT lines 570-582) |

Deliberately NOT in the summary (PROPOSED, decision for the operator in 12.3): `avgHrBpm`, `maxHrBpm` (heart-rate derived health data; contract GPS-PRIV-036 allows "at most non-sensitive summary fields chosen in the S02 design"), laps (list, carry HR), provenance list, `userEdits` map, `mergeNotes` list, `extras`, any start/end coordinate, bounding box, place name, friend or visibility field. A forward-compatible reader keeps unknown local keys in `extras` locally; the cloud summary drops them (extras are not uploaded because rules cannot judge them).

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

Crash safety: see section 10.

## 4. Firestore

New paths (PROPOSED names; the contract fixes behaviour, names are placeholders):

| Path | Writer | Client read | Client write |
|---|---|---|---|
| `users/{uid}/activities/{activityId}` scalar summary | client (offline-first) | owner | owner create/update with shape check; delete DENIED (delete goes through callable so streams cannot be orphaned) |
| `users/{uid}/activity_streams/{activityId}` stream index row: `objectPath`, `bytes`, `kinds`, `activityDateUtc`, `expiresAt` (null = never), `state` (`pending`/`stored`/`expired`/`deleted`), `contentSha256`, `schema` | server only (Admin SDK) | owner | denied |
| `users/{uid}/activity_settings/main`: `cloudStreams` consent (`version`, `acceptedAt`), `streamRetentionDays` | server only, via callable `setActivityCloudSettings` (the upload callable trusts this document, so it must not be client-forgeable) | owner | denied |

Rules edits in `firestore.rules`:
1. Add `coll != 'activities'`, `coll != 'activity_streams'`, `coll != 'activity_settings'` to the read clause (lines 74-90) AND the write clause (lines 91-108). GPS-PRIV-071 requires both; a test that removes either exclusion in a copy of the rules must fail the owner-denied tests (AC of 071).
2. New blocks modelled on Body Scan (FACT patterns lines 532-537, 554-561, 591-607):

```
function activitySummaryOk(id, d) {
  return id.matches('^act_[0-9a-f]{40}$')
      && d.keys().hasOnly([ ...allowlist from table 3.2... ])
      && d.keys().hasAll(['schema','sport','startUtc','endUtc'])
      && schemaOk(d) && d.schema is int && numberIn(d.schema, 1, 1000)
      && d.sport is string && d.sport.matches('^[a-z][A-Za-z0-9]{0,31}$')
      && d.startUtc is timestamp && d.endUtc is timestamp && d.endUtc >= d.startUtc
      && (!('distanceM' in d) || numberIn(d.distanceM, 0, 10000000))
      && ... one line per numeric key with the bounds of table 3.2 ...;
}
match /users/{uid}/activities/{activityId} {
  allow read: if isOrdinaryUser() && request.auth.uid == uid;
  allow create, update: if isOrdinaryUser() && request.auth.uid == uid
                        && activitySummaryOk(activityId, request.resource.data);
  allow delete: if false;
}
match /users/{uid}/activity_streams/{id} { allow read: if isOrdinaryUser() && request.auth.uid == uid; allow write: if false; }
match /users/{uid}/activity_settings/{id} { allow read: if isOrdinaryUser() && request.auth.uid == uid; allow write: if false; }
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
| 059 | Stream objects owner-only (section 5) | storage-side tests |

Rules tests go in `functions/src/__rules__/firestore_rules.test.ts` and `data_access_policy.test.ts` (FACT, contract section 10). `firestore.indexes.json` entry for the collection-group query used by the purge job (`activity_streams` by `expiresAt`) is OPEN (file not read).

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
- Kinds allowed in the cloud: `gps`, `altitude`, `speed`. `heartRate` is REJECTED by the server validator. `cadence`, `power`, `strokeRate`, `temperature` are not location or health-platform data but D-16 does not name them: default device-only, OPEN for the operator (12.3).
- Bounds: compressed <= 5 MiB (signed-URL length-range header, same mechanism as `UPLOAD_LENGTH_RANGE`, FACT); decompressed <= 32 MiB (zip-bomb guard, validator streams and aborts); <= 200 000 samples per stream (about 55 h at 1 Hz); latitude -90..90, longitude -180..180, offsets strictly increasing (FACT `SampleStream.validate`). All values are starting proposals, not measured.
- `meta`: laps with `avgHrBpm` removed, provenance list, `mergeNotes`, `userEdits`. No HR value anywhere.

### 5.2 Upload path and quarantine

Writer: the client PUTs bytes to a V4 signed URL; the server promotes. Callables (new, pattern of `createBodyScan`): `createActivityStreamUpload(activityId, bytes, sha256)` checks auth, the flag, the `cloudStreams` consent and that the summary document exists; creates the index row `state = pending`, returns a signed PUT URL for `quarantine/{uid}/{activityId}/{uploadId}` (TTL 10 min, content type `application/gzip`, length range) . `commitActivityStream(activityId, uploadId)` downloads, checks sha256, decompresses within bounds, validates schema and ranges and absence of `heartRate`, writes the validated copy to `streams/...`, deletes the quarantine object, sets `state = stored` and `expiresAt`. Any failure deletes the quarantine object and returns a bare code. GPS-PRIV-080 targets photos; the same quarantine-then-promote shape is applied to streams as a hostile-input rule (PROPOSED, not demanded by the contract). A scheduled late sweep for abandoned `pending` rows and quarantine objects (every 5 minutes pattern, FACT `purge.ts` line 527) is part of the reconciler (section 6).

### 5.3 Expiry mechanism

A bucket lifecycle rule is by object age, global, and cannot represent a per-user setting; with a "never" option it cannot be used even as a backstop (a backstop shorter than "never" would silently break the setting). PROPOSED: scheduled purge function `purgeExpiredActivityStreams` (daily, `onSchedule` like `purgeExpiredBodyScanPhotos`, FACT) that queries the collection group `activity_streams` where `expiresAt <= now` and `state == stored`, deletes the object, sets `state = expired` (row kept so the app can show "stream expired"; summary stays), with a run budget and attempt cap like `MAX_PURGE_ATTEMPTS` and `PURGE_RUN_BUDGET_MS` (FACT). `expiresAt = activityDateUtc + retention` (clock = activity date, D-16 proposal). Changing the setting calls `setActivityCloudSettings`, which updates `streamRetentionDays` and recomputes `expiresAt` for the user's rows in pages (idempotent, resumable). Shortening makes old streams due at the next purge run; lengthening does not resurrect expired ones (stated in UI copy). Options offered (PROPOSED, contract example list): 90 days, 1 year, 2 years (default, shown), never. OPEN: whether "never" is offered. A monitor metric "oldest overdue row age" (count and age only, no uid) is added so a failing purge is visible (GPS-PRIV-048 compliant).

## 6. Retention and deletion

| Item | Design |
|---|---|
| Setting storage | `users/{uid}/activity_settings/main` (server-authored; section 4) |
| Retention clock / C2 | Activity date; derived geometry (C2) lives inside the stream object and follows the same `expiresAt` (D-16 proposal, OPEN until confirmed) |
| Activity delete | Callable `deleteActivity(activityId)`: delete stream object(s) first, then index row, then summary document last; idempotent, 404 = nothing to delete; error codes bare. Client also removes the local journal entry and queues a retry if offline |
| Account deletion | Extend `sweepAccountData` (FACT `index.ts` line 2376) with `sweepActivityStreamObjects(uid)` called after `sweepBodyScanObjects` (line 2383): `deleteFiles({prefix: "streams/<uid>/"})` and `quarantine/<uid>/`, with exactly the error contract of lines 2405-2423 (unset bucket = logged no-op, all-404 = done, anything else throws a bare code so `reconcileAccountDeletions` retries). Firestore rows are removed by the existing `recursiveDelete(users/{uid})` |
| Orphan reconciler | Scheduled function: index rows without summary, objects without an index row older than the upload TTL, `pending` rows older than 1 hour; deletes or repairs (GPS-PRIV-077 pattern); failure-injection tests kill after each cascade step |
| Local | Journal wiped on sign-out and account deletion per GPS-PRIV-085 |
| `scripts/ci/data_lifecycle_policy.json` | New rows `activities` (BOTH; clientAccess read OWNER, create/update CONDITIONAL with `conditionalRefs` to the rules tests, delete NONE), `activity_streams` (BOTH; read OWNER, writes NONE), `activity_settings` (BOTH; read OWNER, writes NONE), mirroring the `body_scans` entry shape (FACT lines 585-603) |
| `DATA_LIFECYCLE_MATRIX.md` | Update C1/C2 (cloud: private object, user-set expiry, activity-date clock), C8 (cloud: never), section 3 sweep-map rows for `users/{uid}/activities` and Storage `streams/{uid}/`, section 4 gap rows (Storage cleanup, export) and the new-bucket row; same PR (matrix section 5, FACT) |
| Privacy text | `public/privacy.html` must state GPS upload, the expiry setting and that heart rate stays on the device before the flag is enabled (contract D-16 row); stale lines 91, 95, 100 per matrix section 4 are not changed by S02 code but by this text change (OPEN: owner of the text edit) |

## 7. Export

| Item | Design |
|---|---|
| Summary rows | `account_export.ts`: add `sub(uid, "activities", truncated)` and `sub(uid, "activity_streams", truncated)` (stream index rows, no bytes) and `one(users/{uid}/activity_settings/main)` using the existing helpers (FACT lines 101-130); `MAX_ROWS = 2000` cap and `truncated` reporting unchanged. Add paged continuation section for `activities` if 2000 rows is insufficient (OPEN: the paging code was not read; 100 sessions per user is far below the cap, but a heavy user may exceed it) |
| Streams | NOT in the response body (GPS-PRIV-052; budget 8 MiB, FACT line 55). New callable `getActivityStreamDownloadUrls(activityIds[])` (max 20 per call, owner only) returns V4 GET signed URLs, TTL 15 minutes, single object each, never logged (GPS-PRIV-094; log redaction test). Export response lists each stream with `state`, `bytes`, `expiresAt` and a note: "heart-rate streams are on your device only and are not part of this export" (GPS-PRIV-053) |
| FIT / GPX export | Done on the device from stored data (local journal or downloaded stream), so no server conversion. Pure encoders `GpxEncoder` and `FitEncoder` take an `ActivitySession` and return a string/bytes structure; they live in `activity/data` (no `dart:io`); file writing and sharing are outside. GPX 1.1 `trk/trkseg/trkpt` with `ele`, `time`; FIT as the minimum record set (file_id, session, record) with CRC. HR is included when present locally (it is the user's own data on their own device); route trimming (`routeTrimMeters`, default 200 m, FACT `ActivityPrivacy`) applies to SHARED exports only, a full-series export for the owner is the GPS-PRIV-051 requirement. OPEN: a FIT validator is not available in the repo; acceptance is a structural round trip through a test-only decoder written for the sprint |
| Import | None (non-scope) |

## 8. Debug telemetry server guarantee (GPS-PRIV-050 / 098)

Facts: client writes `debug_sessions` directly (`debug_telemetry_sink.dart` line 36); rules check keys and `events.size() <= 500` only (FACT lines 367-378); the sink is documented DEBUG-builds only (matrix section 2).

| | A. Sanitising callable | B. Per-event documents |
|---|---|---|
| Closed schema enforced | Fully, per element, in TypeScript (types, enumerations, bounded counters, no free text), whole batch rejected on violation | Rules check every key/type/range per document; but each event type needs its own rules function and the number of events (500) becomes 500 writes per session |
| Rules limits | None needed; `debug_sessions` write becomes `if false` | Cannot check strings beyond regex/size; enumerations and ranges are doable |
| Cost / change | One callable + client sink change; existing collection layout and export/sweep (`owned("debug_sessions","uid")`, FACT policy row) unchanged | New subcollection, new export/sweep/policy rows, 500x writes, new rules tests |
| Fits the Phase 1 path | Yes: same document shape written by Admin SDK | No: shape changes |

Recommendation (PROPOSED): option A. Reasons: per-element validation is complete; fewer moving parts; the export and deletion wiring for `debug_sessions` stays as is. Migration: the Phase 1 sink switches from `.add` to the callable; rules change `allow create` to `false` for clients; because the sink is DEBUG-only (matrix, FACT) there is no production client population to keep compatible, but an old debug build would get permission-denied (swallowed, OPEN: confirm the sink swallows errors) and Phase 1 behaviour change is recorded in the sync log (contract 098 "must keep the current Phase 1 behaviour documented in the sync log"; OPEN: sync-log file path not located). Negative tests (modified client): coordinate pair, geohash, HR value, place name each as a top-level value, nested map, and list element; each is rejected and nothing stored; a valid event from the real client is accepted; the client schema unit test still fails if a location or HR event type is added. The client-side redaction extension (`debug_telemetry.dart`, no coordinate/HR rule today per the explorer) stays as an additional defence.

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

Native-session dedup rule (PROPOSED): a native session id is `activityIdFor(sourceId: "app", externalId: <uuid generated at recording start>)`, so a re-sync or re-upload of the same recording hits the same id and upserts (idempotent, FACT id function). The merger rule 1 (same `sourceId|externalId`, FACT line 57) is the only dedup S02 promises. The merger's time/distance/GPS clustering is kept as is for tests but S02 makes NO promise that native sessions are matched with platform-health, BLE or vendor sessions (S17); user-facing copy must not claim it.

## 10. Merger performance and crash safety

Performance (PROPOSED budget, to be calibrated on the first run; not measured today):

| Item | Assumption / budget |
|---|---|
| Data volume | 100 sessions per merge call in the gate; planning ceiling 2 000 sessions per user and up to 3 candidates per real workout; streams 1 Hz, up to 4 h = 14 400 GPS points; heavy 12 h = 43 200 |
| Algorithm facts | clustering is O(sessions x clusters), echo detection O(sessions^2) (FACT, merger lines 72-85, 100-119); GPS comparison uses binary search per point (O(points log points)) |
| Budget | merge of 300 candidates (100 workouts x 3 sources) with 3 600 GPS points each completes in under 2 s on the CI VM and under 5 s extrapolated to a mid phone (OPEN: the phone factor is a guess); merge of 2 000 sessions without streams under 1 s |
| Measurement | one focused test, `activity_merger_perf_test.dart`, generating the synthetic corpus (below) and asserting a generous wall-clock ceiling plus an operation-count proxy (counting `_sameWorkout` calls) so the check does not flake on a slow runner. The merge runs in an isolate (`compute`) from the repository if the proxy exceeds the budget; no change to merger behaviour is planned. Authored and run by the test agents per workflow, not by this document |
| If over budget | pre-bucket sessions by day (sort by start, compare only neighbours within the policy window) and index echo lookup by `appPackage`; behaviour must stay order-independent (ACT-05..13 stay green) |

Crash safety of the local journal (PROPOSED): record files written to a temp name in the same directory, flushed, then renamed (atomic on one filesystem); `index.jsonl` appended with one self-contained line per mutation and fsync on each commit point; on start the repository ignores a torn last line, deletes orphan temp files, and rebuilds the index from `record.json` files if the index is missing or unreadable; `synced` markers are written only after the callable returned success, so a crash after upload re-uploads idempotently (same activity id, same object path version). Tests: truncate the index at every byte offset of the last line, kill between temp write and rename (simulated by an injectable file system), assert no loss of previously committed sessions.

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

DoD: all stories' tests green; rules and policy rows merged in the same PR; matrix updated; change record per commit; no GPS flag enabled by default.

## 12. Rollout, flags, risks, open questions

### 12.1 Flags and rollout (PROPOSED)

| Flag | Default | Effect |
|---|---|---|
| Client build flag `ACTIVITY_CLOUD_STREAMS` (pattern `BODY_SCAN_CLOUD`, FACT `body_scan_flags.dart` line 44) | OFF | OFF = device-only: journal and summary only, no stream upload code path is reachable (GPS-PRIV-013) |
| Server setting `ACTIVITY_STREAM_BUCKET` | unset | Unset = callables refuse, sweep is a logged no-op |

Order: ship rules, summary sync and journal first (no geometry anywhere in the cloud); enable streams only after the privacy text is updated (contract D-16) and the bucket runbook is executed. Phase 1 impact: the new collections are additive; the only Phase 1 behaviour change is the telemetry write path (section 8), to be recorded in the sync log. Rollback: turn both flags off; summaries remain valid; stream objects remain until the purge or user delete; rules additions can be reverted without data migration because no existing document changes shape.

### 12.2 Risks

| Risk | Mitigation |
|---|---|
| Summary allowlist drifts from `ActivitySummary` | Shared-constant test parsing `firestore.rules` |
| Purge lag leaves expired GPS in the cloud | Overdue-age metric, daily run, attempt cap |
| Sports/sources added later break rules | Open regex for `sport`, `schema` bump and migration chain |
| Third workout model (`WorkoutSession`, `WorkoutLogEntry`) confuses users | No UI merge in S02; bridging is S03 (OPEN) |
| Plaintext journal in cloud backup | Backup exclusion + encryption (083/084) |
| Estimates in sections 5.1 and 10 are unmeasured | Marked PROPOSED; calibrate in the sprint |

### 12.3 Open questions (operator / GPT-PM)

1. Default expiry value (2 years proposed), whether "never" is offered, and whether C2 follows the stream setting (contract OPEN items).
2. May non-HR sensor streams (cadence, power, stroke rate, temperature) go to the cloud, or only gps, altitude, speed?
3. May `avgHrBpm`/`maxHrBpm` scalars be stored in the cloud summary (proposed: no)?
4. Option A (callable) vs B (per-event) for telemetry: confirm A.
5. Who creates the private bucket and when; soft-delete/versioning windows (GPS-PRIV-078/079 SLA still open).
6. Privacy text owner and wording before the flag is enabled.
7. Unverified here: contents of `S02_CODE_MAP.md`, the paging code and continuation sections of `account_export.ts`, `firestore.indexes.json`, the sync-log path, whether the debug sink swallows permission errors, whether sprint models already carry the A-5 version strings, `runbooks/body_scan_bucket.md`.

Stale documents found, not changed: `public/privacy.html` lines 91/95/100 (no location or GPS text; contract and matrix section 4 already record this); `DATA_LIFECYCLE_MATRIX.md` retention cells still read "per D-16" (updated by S02-08, not by this document).
