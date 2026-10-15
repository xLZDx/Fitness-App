# Cancel vs unresolved createBodyScan: regression tests

## What changed
- `mobile/test/features/body_scan/state/body_scan_job_runner_test.dart`: new group
  `cancel while createBodyScan is unresolved` with 5 tests. A `Completer` holds the
  fake `createBodyScan` open while `cancel()` runs.
- No production code changed.

## Why
GPT-PM asked for a deterministic test of the race. The server writes a 48h
cancellation tombstone on `deleteBodyScan` even if the scan doc does not exist yet
and then refuses `createBodyScan` for that id (`scan-cancelled`). The client only has
to guarantee the delete is sent or durably owed.

## Contract proved
- (a) create succeeds after cancel: `deleteBodyScan(remoteId)` was sent while create was
  in flight, the scan stays `cancelled`, no estimate, no photo read/PUT, no second
  create, no repeated delete on a later resume.
- (b) delete throws: `pendingRemoteDelete=true` persisted with the remote id; the late
  create does not clear it; a new runner over the same stores (restart) flushes the
  delete and the scan stays `cancelled`.
- (c) create response lost (error after cancel): delete sent, scan not requeued
  (attempt 0), nothing restarted. (c2) lost create plus failing delete: delete stays
  owed and flushes after a restart.
- (d) delete lands first, a fake server models the tombstone and the late create throws
  `scan-cancelled`: the scan stays `cancelled`, remote id is not rotated, no re-create,
  no upload.

The tests fail if `cancel()` stops sending or owing the delete: (a)/(d) assert
`api.deletes`, (b)/(c2) assert the persisted flag and the post-restart flush.
Verified by reading assertions; no mutation run (operator rule).

## Verification state
`flutter test test/features/body_scan/state/body_scan_job_runner_test.dart --no-pub`:
68 passed (63 existing + 5 new), 0 failed. Nothing else was run.
