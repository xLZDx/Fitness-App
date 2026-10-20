# S02 design and test plan revision 8 (GPT-PM round 5 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `462f2f86`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 8: summary overrides are now value-based. An override stores `{value, atComputed, atRev}` and is dropped only when the locally recomputed value equals the override value or differs from `atComputed`; it stays through metadata-only mutations and through input changes that leave the field value unchanged. The input-class matrix, digest comparison and golden dependency fixture of revisions 6 and 7 are withdrawn (section 3.2a now explains why). Section 11 test-id cells synced, section 16 has the round 5 rows.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 8: 237 planned tests (41 Dart unit, 55 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 242). Removed U42-U45, I56 and the dependency fixture; added a short literal scenario fixture (G1-G19); rewrote U41 and I50-I53, adjusted I31, I39, I43, I44, I45, I55, E04.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 5 found two defects of the input-class design: over-listing a dependency could silently roll back an adopted server value, and a top-level key classification cannot describe mixed nested inputs. Removing the field-to-input mapping removes both causes.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. NOT_RUN: everything that needs code. GPT-PM round 6 is the next step.
