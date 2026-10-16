# S02 remediation F2 (5/5): test notes

## What changed

Created `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md` with the F2 section: the exact tests the test agent must write for the no-rebind rule, the wipe failing on a key-delete error, the bind retry with a fake timer, the skip of the account being deleted, the uploader after an account switch, and the list of stale fakes to update. Remediation F1 appends its own section.

## Why

Nothing in F2 was compiled by its author; the test agent needs oracles that fail when the guarded behaviour is broken.

## Verification state

Documentation only.
