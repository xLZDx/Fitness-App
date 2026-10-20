# S02 glue: consent withdrawal can start the bulk stream-delete job

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `functions/src/activity_streams/settings.ts`: the strict closed request parse now accepts `cloudStreams.deleteExisting` (boolean). `true` is refused (`invalid_consent`) together with `granted: true`; a non-boolean value is refused; unknown keys are still refused. `SettingsRequest.deleteExistingStreams` and `SettingsPlan.startStreamDelete` carry the option (true only when consent is not granted after the call). A pure withdrawal stays quota-free.
- `functions/src/activity_streams/set_settings.ts`: when `startStreamDelete` is set and no job is active (`hasActiveDeleteJob`), the same transaction writes `streamDeleteJobId` (server-generated), `streamDeletePending: true` and clears `streamDeleteCursor`, exactly the fields `deleteAllActivityStreams` reads. A running job is never replaced. The result gains `streamDeleteStarted`. `SettingsDeps` gains an optional `newJobId` (default: the delete-all generator).

## Why
Design 9.1: "consent withdrawal itself starts the job when the user chose the offer". The job and its callable existed; nothing started it from the withdrawal.

## Affected contracts and paths
Callable request: one new optional key inside `cloudStreams`; callable result: one new field. Old clients are unaffected. The option also works for a user who withdrew earlier and takes the offer later (no consent change, no generation bump, only the job fields are written).

## Verification state
No tests, tsc or build were run. Existing tests that compare the result object with exact equality may need the new `streamDeleteStarted` field (test agents). Not verified: the transaction against the emulator.
