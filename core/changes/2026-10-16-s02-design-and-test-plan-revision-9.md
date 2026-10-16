# S02 design and test plan revision 9 (GPT-PM round 6 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `caa35356`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 9: summary overrides now separate three kinds of change. A passive change is judged by the value rule; an explicit user edit names its target fields and drops the override of those fields in the same generation, even when the edited value equals the locally derived one; an automatic recalculation after a calculation-version change keeps the adopted cloud value, moves `atComputed` and `atVersions`, and records a `recalcCandidate` that the user resolves in the sync-conflict screen. The override now stores `atVersions`. Three open points of the plan were answered (value-unchanged version change, server change in the same sync, explicit edit of a field with a candidate).
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 9: 239 planned tests (41 Dart unit, 57 Dart integration, 37 Firestore rules emulator, 3 Storage rules, 96 functions unit with fakes, 5 fake-backed E2E; previously 237). New I56 and I57; scenario fixture extended to G1-G29; U41, I42-I45, I50-I52, I31, I39, E04 adjusted.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 6 found that an explicit edit to the locally held value was invisible to the value rule, and that a calculation upgrade could silently replace an adopted server value.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. NOT_RUN: everything that needs code. GPT-PM round 7 is the next step.
