# S02 remediation A: settings, rules, TTL, privacy and docs

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/activity_streams/set_settings.ts`: a consent grant cancels an active bulk delete job (A13); a no-op withdrawal-only call returns from one read, without transaction or Auth lookup (A11).
- `firestore.rules`: `primarySourceId` must match the stream `sourceId` pattern and must not look like a coordinate (A12).
- `firestore.indexes.json`: TTL `fieldOverrides` entry for `activity_tombstones.expireAt` (A6).
- `public/privacy.html`: draft summary-sync paragraph and an exception in the Health Connect paragraph (A9); wording PENDING operator approval.
- `scripts/ci/data_lifecycle_policy.json`, `runbooks/activity_stream_bucket.md`, `docs/phase2/s02/S02_PRIVACY_TEXT_REQUEST.md`, `docs/phase2/s02/S02_DESIGN.md` (section 17 items 16 and 17), `docs/phase2/s02/S02_REMEDIATION_A_TEST_NOTES.md`.
- A16 checked: the recompute final pass stamps every row state; no code change.

## Why
Review findings A6, A9, A11, A12, A13, A16 and the accepted-risk list.

## Affected contracts and paths
Summary rules (`primarySourceId`), settings document job fields, deployed TTL policy, public privacy page.

## Verification state
No tests, build, lint or typecheck were run; see the test notes file. The Russian section of the privacy page is not updated.
