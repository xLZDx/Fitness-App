# S02 design and test plan revision 7 (GPT-PM round 4 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `21f67941`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 7: new section 3.2a defines the field dependency matrix for summary overrides: ten input classes, the authoritative field-to-class matrix, digest-based detection of input changes (no hand-listed call sites), the rule that the matrix is a superset and only grows, and five completeness rules whose expectations live in a golden fixture. The wrong reference to section 3.6 is corrected. Section 11 test-id cells synced.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 7: 242 planned tests (45 Dart unit, 56 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 237). New golden fixture (section 1.16), new U42-U45 and I56, rewritten U41 and I52 that read only the golden fixture.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 4 closed the uncommitted-first-generation finding and left one major item: the per-field input revision rested on an undefined field-to-input mapping and its tests would have derived their expectations from the same production constant, so an omitted dependency could go unnoticed.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. NOT_RUN: everything that needs code. The exact top-level keys of `record.json` in the golden fixture stay OPEN until S02-01. GPT-PM round 5 is the next step.
