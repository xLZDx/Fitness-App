# S02 design corrections after the test, review and architecture rounds

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `docs/phase2/s02/S02_DESIGN.md` section 5.2 item 4: the client retry wording is corrected to match test plan row I27 and the built uploader (deterministic exponential backoff without jitter, every attempt is a fresh create, PUT and commit, a restart never resumes a PUT or a commit; the stream marker is separate from the summary `synced` state).
- Section 12.1: states what the built client flag gates (one define for the whole cloud path) and introduces the additional `ACTIVITY_LOCAL_JOURNAL` define (device-only journal, no network path), found necessary by the architecture review for S03 and S04.
- Section 17 items 19 and 20: client upload known limits, the release gate for off-UI-isolate work, the accepted `rev` cap behaviour, the fence timing pointer for 12.2, and the account-bound uploader.

## Why
Two approved documents disagreed (design 5.2 item 4 vs test plan I27), and the architecture review found the single client flag contradicts the staged rollout wording of 12.1. The implementation and the tests follow the plan; the design is corrected, not the code.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/S02_DESIGN.md`. The code change for `ACTIVITY_LOCAL_JOURNAL` is a separate later commit.

## Verification state
No tests apply to documentation. GPT-PM sees these corrections in the final gate review.
