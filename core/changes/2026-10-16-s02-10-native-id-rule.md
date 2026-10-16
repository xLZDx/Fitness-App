# S02-10 change record: native-session id rule

Date: 2026-10-16. Story: S02-10 (design 9; test ids U10, U11, I06).

## What changed

- New `mobile/lib/features/activity/data/native_session_id.dart` (pure Dart):
  - `kNativeSourceId = 'app'`.
  - `nativeActivityId(recordingUuid)` = `activityIdFor(sourceId: 'app', externalId: recordingUuid, ...)`; an empty uuid is rejected with `ArgumentError` because all empty recordings would collapse into one session. The uuid is generated once at recording start (S04), so a re-sync, re-upload or replay yields the same `act_<sha1>` id.
  - `nativeSourceRecord(...)` builds the provenance record with the same `sourceId|externalId` key, so merger rule 1 recognises a replay as well as the merger rule 0 (same id) added in the previous S02-10 commit.
- Idempotent persistence needed no change: `FileActivityJournal.put` already upserts by id and treats an identical re-put as a no-op (S02-02); this commit relies on that and does not touch the journal.

## Why

Design 9: the native-session dedup rule is the only dedup S02 promises. There is deliberately no matching of native sessions against platform-health, BLE or vendor sessions.

## Decision for review

- The native provenance record uses `SourceKind.companionApp` because the design 9 matrix has no native `SourceKind` and `fileImport` is "n/a" for cloud upload. If S04 adds a dedicated kind, only `nativeSourceRecord` changes.

## Verification state

No tests, builds or checks were run (operator rule v4). Test agents own U10, U11, I06.
