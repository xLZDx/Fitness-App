# Mobile review fixes 2: owed deletes in scan history actions, runner regression tests (SF-F1, SF-F4, SF-F5)

## What
- `ScanHistoryActions.deletePhotos`: when a cloud copy may exist but cannot be deleted now (offline, call failed, or the cloud flag is off) the delete is owed: the runner is told to forget the scan, the record is saved with `pendingRemoteDelete` + `pendingPhotosOnly` (full delete stays full), an unfinished scan becomes terminal `cancelled`, the phone copy stays and the outcome is `queuedOffline` (or `failed` without a local record). It never reports `deleted` while the cloud copy remains.
- Tests: runner regression cases (owed delete non-resumable, no overwrite of a landed cancel, photos-only flush + local removal, not-ready inputs, busy rerun, retry timer survives, errors never escape) and updated/added actions cases.

## Why
SF-F1, SF-F4, SF-F5.

## Paths
mobile/lib/features/body_scan/state/scan_history_actions.dart, mobile/test/features/body_scan/state/scan_history_actions_test.dart, mobile/test/features/body_scan/state/body_scan_job_runner_test.dart

## Contracts
`DeletePhotosOutcome.queuedOffline` now also covers the cloud-flag-off case with a server copy.

## Verification
Not run (operator rules); test agents run the suites.
