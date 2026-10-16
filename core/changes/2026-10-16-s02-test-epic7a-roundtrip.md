# S02 test epic 7a: E01 100-session round trip (gate)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- Added `mobile/test/features/activity/e2e/s02_roundtrip_e2e_test.dart` (plan E01): 155 raw corpus records are merged into 100 sessions, written to an on-disk journal, read back before and after restarts, synced through the sync repository to a rules-enforcing fake Firestore, and exported as GPX and FIT.
- Asserts: the plan sport quotas; every session unaltered in the journal (JSON and streams, sample by sample); 100 summaries accepted, none refused; every summary passes the allowlist and bounds parsed from `firestore.rules`; no list or map value, no geometry or heart-rate key, no numeric summary value equal to a GPS sample; a second sync and a restart write nothing; GPX point counts and FIT record counts and start times against the stored streams; non-GPS sessions give `no_geometry`.

## Why
Plan E01 is the cross-story gate for the round trip.

## Affected contracts and paths
Test only. No production file changed.

## Plan and code notes
- The merged sessions are not equal to `corpus.valid` (14 of 100 differ in key or provenance), so the oracle for the merge is the count and the plan quotas, and the oracle for the journal is the merged objects themselves.
- The cloud `distanceM` is the effective projection, not the stored summary value; it is compared with a 10 percent tolerance. Exact preservation is asserted on the journal.
- After the first sync the repository stamps the three calculation-version keys on the record; the post-sync comparison neutralises exactly those three keys.

## Verification state
`flutter test test/features/activity/e2e/s02_roundtrip_e2e_test.dart` from `mobile/`: 3 tests passed (about 2 minutes). Not covered: the Firestore adapter itself and the real rules (emulator epic 5).
