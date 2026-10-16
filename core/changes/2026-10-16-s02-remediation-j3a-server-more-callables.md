# S02 remediation J3a: bind the remaining activity callables to the initiating account

Date: 2026-10-16. Branch: phase2/s02-unified-activity. Base head: fe57aa9e.

## What changed

- `functions/src/activity_streams/download_urls.ts`: `handleGetActivityStreamDownloadUrls` calls `verifyExpectedUid(uid, data)` right after the anonymous gate, before the strict parse, the bucket check, the quota charge and any read. Mismatch is `failed-precondition` / `account_changed` (logged as `account_changed`, no uid); a missing or malformed key is `invalid-argument` / `invalid_request`.
- `functions/src/activity_streams/delete_all_streams.ts`: `handleDeleteAllActivityStreams` gains a required `data: unknown` parameter (4th, before `limits`) and the same verification before the settings read and the quota charge. The body is no longer ignored: after the key is stripped it must be an empty plain object, otherwise `invalid-argument` / `invalid_request` (new `invalid_request` entry in the refusal map). The `onCall` wrapper passes `request.data`.
- `docs/phase2/s02/S02_DESIGN.md` item 25: paragraph (d) J3 with the structural rule and the accepted limits and backlog of the class sweep.
- `docs/phase2/s02/S02_REMEDIATION_J_TEST_NOTES.md`: new section J3 (server part) for the test agents.

`sendDebugTelemetry` is unchanged (debug builds only, closed schema, no identifiers).

## Why

The J1 fix bound four callables because its brief named four. Three independent class-sweep reviews found two more callables with the same ambient-identity defect. No client calls them today; the change keeps the class from reappearing.

## Affected contracts and paths

Both callables now require `expectedUid` in the request (old clients get `invalid_request`; clients ship with the server, flags off). `handleDeleteAllActivityStreams` signature change breaks existing test call sites (listed in the test notes).

## Verification state

NOT RUN. No test, analysis or build was executed. Existing jest support (`support/seven.ts` and direct call sites) must change and new tests are required; see the J3 section of the test notes. Review by an independent agent is pending.
