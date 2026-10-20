# S02-03 change record: owner wildcard exclusions

Date: 2026-10-16. Story: S02-03 "Firestore rules" (design section 4, rules edit 1; GPS-PRIV-058, 071; test ids R02, R04, R15-R18, R31).

## What changed

- `firestore.rules`: `coll != 'activities'`, `coll != 'activity_streams'`, `coll != 'activity_settings'` and `coll != 'activity_tombstones'` are added to BOTH the read clause and the write clause of the `users/{uid}/{coll}/{document=**}` owner wildcard. A header comment documents the permanent floor.

## Why

Firestore allows a request if any matching rule permits it. Without the exclusions the wildcard's blanket owner grant would make the dedicated activity blocks (next commit) dead and let a client write geometry keys, forge stream index rows or consent, or erase tombstones.

## Affected contracts and paths

`firestore.rules` only. Until the next commit adds the dedicated blocks, the four paths are denied to clients (default deny), which is the safe state.

## Verification state

No tests, emulator runs or checks were run (operator rule v4). Test agents verify with R17, R18 and R31.
