# S02 design and test plan revision 5 (GPT-PM round 2 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `2e299fd7`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 5: (1) the merged summary is now durable: `record.json` carries a per-field `summaryOverrides` map, the written summary is `recompute(record)` overlaid with the overrides, an override is dropped when the recomputed value equals it or the local record changed after the merge, a field the device cannot recompute stays a resolvable `sync_conflict`; (2) every journal generation directory has a `COMMIT` marker written last by atomic rename (two separate checksums, `record.json` and `streams.bin`), which is the commit point; `CURRENT` is only a fast pointer; recovery activates the highest generation with a valid marker and deletes uncommitted ones; four crash cases are defined; a `streams.bin`-only checksum mismatch is recovered as `streamLost` instead of rolling back acknowledged edits. Section 11 test-id cells synced with the plan.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 5: 231 planned tests (41 Dart unit, 49 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 223). New U41, I43-I49; rewritten I19, I20, I35, I36, I40, I41; extended I31, I39, I42, E04. Two plan questions answered by the lead (DQ-29, DQ-30).
- `docs/sdlc/STATE.md`: S02 phase and next role refreshed.
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
GPT-PM round 2 closed the deletion-fence blocker and three majors and left two partial majors: the three-way merge did not guarantee durable convergence, and recovery could activate a generation that was never committed.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. A read-only cross-check outside the repository found all 228 defined non-Storage ids mapped to a story, no unknown id and no placeholder token in design section 11. NOT_RUN: everything that needs code. Round 3 of GPT-PM is the next step.
