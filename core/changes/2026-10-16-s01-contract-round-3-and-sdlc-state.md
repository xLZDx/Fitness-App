# S01: contract round 3 fixes and the SDLC state file

Date: 2026-10-16. Branch: `phase2/s01-contracts`.

## What changed
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` and `DATA_LIFECYCLE_MATRIX.md`: round 3 fixes after the security verification round (1 MAJOR, 5 MINOR). Binding default E1 for adult-to-minor friend edges until the operator decides (the server refuses a friends edge between a known adult and a known minor, or involving unknown age; D-17 stays open with E1, E2, E3 and their consequences); acceptance criterion of GPS-PRIV-098 narrowed to what Firestore rules can express (list size bound and top-level key allowlist; per-element checks move to a client schema test or a sanitising callable); 073 governed by 095 and class C11; C11 row in the section 3 class table; 086 list and query denied to everyone, owner list through the callable of 097; cross-reference fixes; the server-held age field lives in a server-only path outside the client-writable profile document (placeholder `userAge/{uid}`). 98 requirements, unchanged count.
- `docs/sdlc/STATE.md` (new): SDLC phase state for the Phase 2 program (S00 done, S01 in phase 5 doc review).
- `docs/DOCUMENT_REGISTRY.md` regenerated; `core/DECISION_LOG.md`: one entry.

## Why
Operator-approved sprint S01 (documentation only); the exit needs GPT-PM review and operator approval of the contract. The security verification round must close first.

## Affected contracts and paths
Documentation only. No code, rules or flags changed.

## Verification state
No tests or checks run. The `userAge/{uid}` name and all numeric parameters are proposals, not researched values. Not verifiable from the repository: cloud backup, soft-delete, CDN and log retention settings, whether a server age field exists today, store requirements for background location.
