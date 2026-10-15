# Mobile review fixes 1: job runner (SF-F1 runner side, SF-F2, SF-F3, SF-F6 runner part)

## What
- `BodyScanJobRunner`: a scan with `pendingRemoteDelete` is never resumable; every runner save re-reads the record and stops (never overwrites) when the record was cancelled, deleted or has an owed delete; owed deletes honour the new `pendingPhotosOnly` kind, re-read before clearing the flag, and call `onRemoteDeleteFlushed` (phone copy removal) for photos-only deletes.
- Not-ready inputs: new `subjectPending` callback; while the profile or weight is loading a null subject leaves the scan queued instead of `failed:subject-missing`.
- Retry timer: `resume()` called while busy sets a rerun flag; the timer is re-armed from the stored queue after every pass (no overwrite, no loss when a scan fails during the pass).
- `resume`, `retry`, `cancel` never throw; errors become scrubbed `onError` reports; a stopped scan no longer aborts the pass for the others; `cancel` re-reads before saving.
- `ScanRecord.pendingPhotosOnly` (persisted only with `pendingRemoteDelete`).
- Providers bind `subjectPending` and `onRemoteDeleteFlushed`.

## Why
Review findings SF-F1, SF-F2, SF-F3, SF-F6 (silent-failure-hunter).

## Paths
mobile/lib/features/body_scan/state/body_scan_job_runner.dart, mobile/lib/features/body_scan/state/body_scan_providers.dart, mobile/lib/features/progress_photos/scan/scan_models.dart

## Contracts
ScanRecord JSON gains optional `pendingPhotosOnly: true`; old records read as false. Runner constructor gains two optional parameters.

## Verification
Not run (operator rules); regression tests follow in a later commit.
