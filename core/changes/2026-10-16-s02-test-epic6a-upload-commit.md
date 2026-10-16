# S02 test epic 6a: S02-04b create/commit state machine and shared callable hardening

## What
Tests F07-F12 (`upload.test.ts`), bucket helpers (`bucket_paths.test.ts`), F44/F87/F45 (`upload_fence.test.ts`), F46-F49 (`commit_state.test.ts`), F84-F86 (`commit_overlap.test.ts`), F41/F60/F61/F62 over the table of the SEVEN callables (`callable_hardening.test.ts`), support `flow.ts` and `seven.ts`. One production fix in `functions/src/activity_streams/commit_stream.ts`: `writeIntendedHash` now returns `false` when a concurrent commit of the SAME upload id has already stored the object, and the caller returns `already_stored` instead of failing with `superseded` (F47: the second of two concurrent identical commits must not get an error).

## Why
The create/commit state machine, compensation, generation pin and overlap behaviour had no test. The plan text for F45 ("creates a pending row" over a stored row) and F61 ("the log contains the uid") contradict design 5.2/5.4 and are followed as the design says.

## Affected paths
Test files above; `functions/src/activity_streams/commit_stream.ts`.

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/`. Result: 12 suites, 374 tests passed.
