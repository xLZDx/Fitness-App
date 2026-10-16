# S02 design and test plan revision 12 (GPT-PM round 9 remediation)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Head before this commit: `b3415370`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` revision 12: resolving a source candidate is one atomic journal generation covering the explicit value, the cloud override and the candidate. When an override exists the user has three choices (use the new computed value, keep my value, use the cloud value); the chosen value is merged three-way against the current last-synced base and the current server revision, a server that moved again leaves the chosen value in the conflict state, and a removed override never reappears after a restart or a replayed acknowledgement.
- `docs/phase2/s02/S02_TEST_PLAN.md` revision 12: still 239 planned tests (no id added or removed). Scenario fixture extended to G1-G46 (G41-G46 new); U41, I57, E04 and the conflict-screen test I42 extended.
- `docs/sdlc/STATE.md` and `docs/DOCUMENT_REGISTRY.md` refreshed.

## Why
GPT-PM round 9 closed the bounded-history finding and left one gap: the resolution of a source candidate did not say how to handle an already adopted cloud override, which has higher precedence than the explicit value.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`, `docs/sdlc/STATE.md`.

## Verification state
No tests were run. NOT_RUN: everything that needs code. GPT-PM round 10 is the next step.
