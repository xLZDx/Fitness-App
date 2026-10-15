# S01: fixes for GPT-PM verification round 3 (MODIFY, MAJOR-01A residue) and a full citation re-verification

Date: 2026-10-16. Branch: `phase2/s01-contracts`. Reviewed head: `3f696cd2`.

## What changed
- The three locations named by round 3: contract section 11 (Body Scan code described as absent), contract section 2 consequence paragraph and matrix section 3 (deletion sweep described as having no Storage step). Now: the sweep already deletes the private Body Scan bucket prefix (`sweepBodyScanObjects`), and covers no GPS objects and not the default bucket.
- Root cause of the repeated findings: the S01 documents were drafted against the tree before PR #5, which grew `firestore.rules` by 440 lines and changed `functions/src/index.ts`, `public/privacy.html`, `firebase.json` and added `storage.rules`. A technical-writer agent (Sonnet 5.5) re-verified every file and line citation and stale "absent" claim in the contract and the matrix against the current tree; the lead spot-checked `firestore.rules` 70-72, 321-324, 367-378, 434-437, `privacy.html` 95 and 103 and `index.ts` 2301, 2376, 2383.
- Corrected: `firestore.rules` line numbers (wildcard 73-109, `isOrdinaryUser` 70-72, `donor_wall` 321-324, health stripping 191-232, profile block 263-283, `debug_sessions` 367-378, `recognised_models` 434-437); `index.ts` line numbers; `privacy.html` citations (Body Scan photos have their own retention, 48 h default and a 400-day backstop, so "no separate retention timer" was reworded); export facts and the no-uid logging fact (`account_export.ts`, `abuse_guard.ts`); `firebase.json` description; the existing Storage rules test added to section 10 and GPS-PRIV-064; the server-side read of the client-writable birth year (`body_scan/access.ts`) recorded as a fact without changing GPS-PRIV-044.
- No requirement number, decision or acceptance meaning changed.

## Why
GPT-PM round 3 asked for one documentation-only commit that corrects the remaining stale baseline statements and verifies the cross-references. A full sweep was done instead of fixing three lines to avoid further one-at-a-time findings.

## Affected contracts and paths
Documentation only: `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`, `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`, `docs/DOCUMENT_REGISTRY.md`, `core/DECISION_LOG.md`.

## Verification state
No tests or checks were run (documentation-only sprint). Not verified by the agent or the lead: citations into `docs/phase2/plan/04_UI_UX_DIRECTION` and the roadmap, line citations into `debug_telemetry.dart`, the `data_lifecycle_policy.json` comment and TTL, `WorkoutSession` heart-rate fields, and anything about deployed Firebase or Google Cloud state. GPT-PM round 4 on the new head is pending.
