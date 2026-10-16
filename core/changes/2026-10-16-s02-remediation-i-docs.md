# S02 remediation I, item I3: design accepted list and test notes

Date: 2026-10-16. Documentation only. No code changed; nothing was compiled or run.

## What changed

- `docs/phase2/s02/S02_DESIGN.md`, section 17 item 24, ACCEPTED / BACKLOG list: the bind-gap sentence now reflects I1
  (`refreshState` no longer emits a new state of the previous account in the gap) and I2 (early consent bind, refusal on
  an unbound store); four honest limits added: (a) a server-side account deletion in flight is closed by the server
  (`firestore.rules` `activityNotTombstonedOrFenced`, callables refuse `account_deleting` / `account_deleted`), the
  client flag is defense in depth; (b) a tap during an account transition returns pending and does nothing;
  (c) `exportAll` does not detect an A to B to A switch inside one read; (d) `onSignOut` uses `wipeForUid`, whose
  no-rebind latch leaves the journal unbound if sign-out fails after the wipe (fail closed).
- `docs/phase2/s02/S02_REMEDIATION_H_TEST_NOTES.md`: new heading I with the exact tests for I1 and I2 (each fails if its
  guard is removed) and the list of stale fakes and older assertions.

## Why

Operator remediation I brief: the review rounds found the limits above; they must be recorded honestly, and the test
agent needs oracles for the two code items.
