# S04 code review fixes

Date: 2026-10-17. Kind: code and tests.

## What changed
- journal and state: abandonActive, unavailable status, cooperative pre-unbind hook with FALLBACK first, all-scopes expiry sweep, owner-atomic hand-off (putForOwner), DECISION published by temp rename, uid-change reset, fallback notice.
- adapter, pages, shell, consent: serialized stream stop and setInterval, finished and save-failed screens, revoked strip row, single announcer, consent withdraw failure shown.
- docs: S04_REVIEW_FINDINGS_CODE_ROUND1.md, S04_TEST_FINDINGS_FINAL.md round 2.

## Why
Four independent reviews of the tested code.

## Affected contracts and paths
RecordingJournalPort gains abandonActive; UnfinishedRecording gains distance and moving time; UidScopedActivityJournal gains putForOwner.

## Verification state
flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout: 1119 passed. NOT_RUN: device rows, analyze, build, CI.
