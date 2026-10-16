# S02 remediation C: test notes (client findings)

One line per item: what a test must assert. FL3, FL4 and FL7 are decided and not implemented.

- FL1: with a fake backend whose `readSummary` throws a generic error (for example a `FirebaseException` permission-denied) for one conflict entry, `watch()` still emits a state in which that conflict has `cloudKnown: false` and no fields; no zone error escapes. With a fake journal whose `list()` throws, `watch()` delivers a stream error (not an uncaught async error), and the presenter ends with `loadFailed: true`, `loaded: false`.
- FL2: before the first emission the sheet shows `activitySync.loading` (a progress indicator) and never `activitySync.empty`; after the first emission with no items it shows `activitySync.empty`; after a stream error it shows `activitySync.error` and `activitySync.retry`; tapping retry re-subscribes (`watch()` called again), clears the error, and a following emission shows the items.
