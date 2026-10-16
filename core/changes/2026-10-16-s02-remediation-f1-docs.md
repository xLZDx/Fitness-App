# S02 remediation F1 (4/4): design item 23 and F1 test notes

## What changed

- `docs/phase2/s02/S02_DESIGN.md` section 17: new item 23 (pass identity and pinning, unbound visibility, retry reset and fallback timer, `requestTombstoneSync`, S03 handoff) with an honest ACCEPTED / BACKLOG list.
- `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`: heading F1 with the exact tests per item and the list of stale fakes and tests.

## Why

The remediation changed contracts the design described; the test agent needs oracles that fail when the guarded behaviour breaks.

## Verification state

Documentation only; nothing compiled or run.
