# S02 remediation D: independent ACTIVITY_LOCAL_JOURNAL flag

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/core/config/activity_flags.dart`: new `localJournal` field (default false), read at compile time from `ACTIVITY_LOCAL_JOURNAL`; getter `journalEnabled => localJournal || cloudSync`; `==`, `hashCode`, `toString` and the doc comment cover both flags. `cloudSync` and `ACTIVITY_CLOUD_STREAMS` are unchanged.
- `mobile/lib/core/wiring/activity_wiring.dart`: `openActivityJournal` and `activityRootOverrides` use `journalEnabled`; the sync repository override (Firestore backend, tombstone pusher) is added only with `cloudSync`. The uploader, consent withdrawal, start-up sync, owner claim and conflict entry point stay gated by `cloudSync`. The device wipe is wrapped whenever a journal exists. `main.dart` needed no change (it decides by journal presence).
- `docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md`: test assertions.

## Why
Architecture review: one flag gated the journal and the whole cloud path, so later sprints (dashboard, GPS recording) could not use the device journal without enabling the cloud (design 12.1, section 17 item 19).

## Affected contracts and paths
Both flags off: identical to before. localJournal only: journal opens, no network object is constructed. cloudSync: journal opens as before.

## Verification state
Not run in this commit by design; the test agents write and run the tests in the test notes.
