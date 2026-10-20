# S01: fixes for GPT-PM verification round 2 (MODIFY, MAJOR-01A)

Date: 2026-10-16. Branch: `phase2/s01-contracts`. Reviewed head: `ae6b6dbb`.

## What changed
Round 2 closed MAJOR-02 (telemetry guarantee) and returned MAJOR-01A: stale statements about the pre-PR #5 tree remained. Fixed and checked against the current tree (`functions/src/index.ts`, `functions/src/body_scan`, `mobile/lib/features/`, `firebase.json`, `storage.rules`):
- Contract section 2: account deletion row (the sweep already deletes the user's prefix in the private Body Scan bucket through `sweepBodyScanObjects`; the default bucket and licensed video bucket are not swept) and Body Scan code row (code is present since PR #5).
- Contract section 11: retention-settings line no longer says `firebase.json` has no storage section.
- GPS-PRIV-055: cites the real sweep line and the Body Scan pattern to follow.
- Matrix: Body Scan, nutrition, account-deletion and deletion-sweep rows corrected.
- Contract section 13: MAJOR-01A disposition row.

## Why
GPT-PM round 2 asked for one documentation-only remediation of the remaining stale Storage and Body Scan statements, with the next round limited to MAJOR-01A and its direct regressions.

## Affected contracts and paths
Documentation only: `docs/phase2/s01/`, `docs/DOCUMENT_REGISTRY.md`, `core/DECISION_LOG.md`.

## Verification state
No tests or checks were run (documentation-only sprint). A final grep over `docs/phase2/s01` for the old phrases found no remaining occurrence. GPT-PM round 3 on the new head is pending.
