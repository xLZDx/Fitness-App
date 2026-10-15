# C12 server tests: create (first batch)

Date: 2026-10-15. Scope: functional tests for the body-scan Cloud Functions (C12 = 5d2c356).

## What changed

- `functions/src/__tests__/body_scan/fakes.ts`: shared stateful Firestore + Storage + Secret Manager + logger doubles (same model as the stateful fake in `account_deletion_reconcile.test.ts`, extended with collectionGroup, orderBy/startAfter, FieldValue delete/increment sentinels, tx.create, Timestamp class, a bucket with paged listing and failure injection). Not a test suite (no `.test.ts` suffix).
- `functions/src/__tests__/body_scan/create.test.ts`: 102 tests for `createBodyScan`.
- C12 code defects found by the type-checking test run (ts-jest) and fixed minimally:
  - `functions/src/body_scan/create.ts:209` `Object.fromEntries(...) as Uploads` raised TS2352; now `as unknown as Uploads`.
  - `functions/src/body_scan/manage.ts:95` `pagedAction` was passed the full action union (TS2345); now cast to `Exclude<Action, "exportLinks">`.

## Verification state

Command: `npx jest src/__tests__/body_scan/create.test.ts` in `functions/`. Result: 102 passed, 0 failed (head 166ae42 plus these working-tree changes). Other files of this task are added in later commits.
