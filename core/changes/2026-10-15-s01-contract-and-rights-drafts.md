# S01: GPS privacy contract, data lifecycle matrix and rights study (drafts)

Date: 2026-10-15. Branch: `phase2/s01-contracts` (based on `phase2/s00-split-docs` at `6616d2f8`; must be rebased onto `phase2/main` after the S00 PR merges).

## What changed
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md`: draft contract with 70 numbered requirements (GPS-PRIV-001..070), all PROPOSED, open decisions D-16 (retention of GPS and heart-rate streams) and D-17 (minors, sharing, public routes) written as options with a recommended default; nothing is decided.
- `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`: lifecycle matrix (collected, local, cloud, shared, retained, exported, deleted, logged) for new location data classes and for existing data classes taken from the code.
- `docs/phase2/s01/RIGHTS_STUDY_TILES_ROUTES_POI.md`: rights study for map tiles, routing, POI, elevation and user-route licences from official sources (grade A/B), with one recommendation per decision D-6 (tiles) and D-7 (route data and region); both decisions stay open for the operator.
- `core/DECISION_LOG.md`: one entry.

## Why
Sprint S01 of the approved plan (`docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`): contracts and rights options before any GPS code. Exit: contract and matrix reviewed by GPT-PM and approved by the operator, UI-0 baseline report, rights options with recommendation, no code.

## Facts the drafts surfaced (FACT, see the documents for paths)
- `firestore.rules` has a wildcard owner read/write over `users/{uid}/*`; a new location collection would be client-writable without its own rule block.
- No `storage.rules`; `deleteAccount` does not clean Storage; `exportAccountData` is capped near 8 MiB.
- `ageBandFor(null)` returns adult, so it must not gate sharing; `public/privacy.html` does not mention location.

## Affected contracts and paths
Documentation only; no code, rules or flags changed.

## Verification state
No tests or checks run. The documents were drafted by agents from repository files; statements are labelled FACT (with path), PROPOSED or UNVERIFIED. The rights study was read through a fetch-and-summarise tool and needs a legal re-read of the original pages. The UI-0 audit (S01 part c) is not in this commit. GPT-PM review and operator approval are pending.
