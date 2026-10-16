# S02 test epic 6a: shared fakes and the F94 self-test

## What
`functions/src/__tests__/activity/support/fakes.ts` (fake bucket with generation pinning, promotion by save, 404, signed URL, failure injection and hooks; fake Auth; Date-only fake clock; deadlock-guarded Gate; payload and seed builders; reuse of the body_scan in-memory Firestore with optimistic transactions) and `functions/src/__tests__/activity/fake_firestore_conflict.test.ts` (F94).

## Why
Every race test of epic 6a is meaningful only if the fakes can produce conflicting writes, transaction retries, generation changes and paused actors.

## Affected paths
Test files only; no production change.

## Verification state
Command: `npx jest src/__tests__/activity/fake_firestore_conflict.test.ts` (cwd functions). Result: 1 suite, 11 tests passed.
Not modelled: Firestore rules gate (stale `rev`, covered by the emulator tests of epic 5); the named hook betweenFirestoreDeleteAndSweep (belongs to the deleteAccount flow tests of epic 6b).
