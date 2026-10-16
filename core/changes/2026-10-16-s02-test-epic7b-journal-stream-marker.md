# S02 test epic 7b: dedicated stream-upload marker in the journal

## What
`JournalState` gets `streamUploadedHash` and `streamUploadPending`; `ActivityJournal.markStreamUploaded` (implemented in `FileActivityJournal`) records that the cloud holds the current streams. The uploader picks entries whose summary is `synced` or whose last run failed and whose streams are not marked, writes only the stream marker on success, never overwrites `sync_conflict` on the cap, and the Firebase clients resolve the functions handle at first call.

## Why
Defect found by the epic 7b real-sequence test: the summary sync writes `synced`, so the uploader (which reused that state) never picked the entry, and its own `synced` write would hide an unsynced summary.

## Affected paths
- `mobile/lib/features/activity/repository/journal_models.dart`, `activity_journal.dart`, `file_activity_journal.dart`, `activity_stream_uploader.dart`, `activity_cloud_settings_client.dart`
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md` (defect record, written in the last commit of this epic)

## Verification state
Covered by the epic 7b tests (next commits) and the existing journal and sync tests: see the findings file for the exact command and result.
