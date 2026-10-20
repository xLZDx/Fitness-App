# S02 remediation G docs: accepted backlog and test notes

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: documentation only.

## What changed

- `docs/phase2/s02/S02_DESIGN.md` section 17 item 23, ACCEPTED / BACKLOG: (e) the cloud sync start
  sequence is not re-run after a failed bind that the binding provider's retry later fixes, and the
  journal stays unbound after the five retries until the next auth event or restart (fails closed,
  no leak, no loss, secondary mechanism that already had its one fix round); (f) the conflict
  presenter retry only resubscribes and cannot force a bind.
- `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` section G: exact tests for G2 to G5 (G1 was
  added with its commit) and the list of stale fakes and tests.

## Why

Record honestly what remediation G accepts without changing, and give the test agent the oracles.

## Affected contracts / paths

None (documents only).

## Verification state

No code or test changed. Nothing compiled or run.
