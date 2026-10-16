# S02 design and test plan revision 11 (GPT-PM round 8 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `ac6f6e2a`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 11: explicit user edits live in a canonical `explicitValues` map (one entry per summary field, with the raw derived value at edit time) that alone feeds the summary projection; the `userEdits` list becomes a bounded device-only history ring of 64 that the projection never reads; `userEditCount` is a saturating counter capped at 64, so the cloud summary always satisfies its range. An explicit value stays authoritative, and when newer source data or a calculation upgrade changes the raw derivation a `sourceCandidate` is recorded for the user to resolve; nothing is discarded silently.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 11: still 239 planned tests (no id added or removed). Scenario fixture extended to G1-G40 (G33-G40 new); U38, U41, I45, I51, I56, I57, E04 extended; wording aligned in U01, U05, U08, U32, I30, I39, I55, F51.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 8 found that an old explicit value could hide newer passive source data, and that an unbounded edit history could push the cloud edit counter over its allowed range and make the summary unwritable.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. NOT_RUN: everything that needs code. GPT-PM round 9 is the next step.
