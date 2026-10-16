# S02 remediation C: uploader account safety and wiring guard (FL5, FL6)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/activity_stream_uploader.dart`: new optional `currentUid` supplier. `runPending` is single-flight (a second call returns the in-flight future); `uploadEntry` is single-flight per id and takes an optional `boundUid`. Each run is bound to the uid it started with and re-checks it before every create, PUT, commit, before `markStreamUploaded` and before marking `upload_failed`; on a change or null it returns `cancelled` without any further call or journal mark.
- `mobile/lib/core/wiring/activity_wiring.dart`: the uploader provider passes the supplier (null for no user, empty uid or guest). The auth listener calls `cancelQueued()` when the signed-in uid changes or goes away, re-checks the uid after the journal claim, and calls `resume()` only after the new claim succeeded. The unawaited closure now has a top-level try/catch with `debugPrint` (FL6).
- `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md`: test assertions for FL5 and FL6.

## Why
Flutter review FL5 (an in-flight run could create, PUT or commit with the next account's credentials, and overlapping runs uploaded twice) and FL6 (unawaited closure without an outer guard).

## Affected contracts and paths
Without a supplier the uploader behaves as before. Flag off: nothing here runs. Note: `resume()` also lifts an earlier consent-withdrawal cancel on a new sign-in; uploads still need consent known granted.

## Verification state
Not run in this commit by design; the test agents write and run the tests in the test notes.
