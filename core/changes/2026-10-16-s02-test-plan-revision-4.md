# S02 test plan revision 4 and design story-map sync (GPT-PM round 1 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Design head before this commit: `daf19c93`.

## What changed
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 4: 223 planned tests (40 Dart unit, 42 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 212). New or rewritten tests for: the account-deletion fence in the rules (queued offline put after the late sweep refused, batches of 8, creation and removal order); the three-way merge and the sync-conflict choice; journal generation directories with fault injection at every step; the corpus split into 100 valid sessions (each of 12 sports at least 6 times) and a separate hostile and future-schema set; F78 as a positive invariant; the story-map completeness lint (S02-11). Section 8 holds the dispositions.
- `docs/phase2/s02/S02_DESIGN.md`: the test-id column of section 11 now equals the plan's section 7 map (added U39, U40, I30, I38-I42, R36, R37, F95, F96 where missing); the old placeholder token no longer appears in section 11. A read-only cross-check (a throwaway script outside the repository, not a test) found 220 defined ids of the non-Storage series all mapped to a story and no unknown id; the 3 Storage rules tests make 223.
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
Remediation of GPT-PM round 1 (1 BLOCKER and 5 MAJOR); the verification round follows on this head.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`.

## Verification state
No tests were run. NOT_RUN: real Firestore access-call limit (8 chosen, 20 reported; the emulator discovers its own), fence propagation in production rules evaluation, real Auth token lifetime, power-loss durability of the `CURRENT` switch, conflict screen layout. Open: wording of the "keep this device / keep cloud" choice and the age bound for removing orphan generation directories.
