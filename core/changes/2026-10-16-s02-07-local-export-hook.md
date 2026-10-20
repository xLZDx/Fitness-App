# S02-07 change record: local export hook over the activity journal

Date: 2026-10-16. Story: S02-07 (design 7, 3.5; test ids U17-U20 via the encoders, E01).

## What changed

- New `mobile/lib/features/activity/repository/activity_local_export.dart`:
  - `ActivityLocalExport` interface (`exportActivity(id, format)`, `exportAll(format)`) and `JournalActivityLocalExport`, which reads `ActivityJournal.read`/`list` and encodes with the pure `GpxEncoder`, `FitEncoder` or canonical session JSON.
  - Typed results: `ActivityExportFile` (format, safe suggested file name, bytes), `ActivityExportNoGeometry` (GPX of a session without GPS, DQ-3), `ActivityExportNotFound` (unknown, deleted or unreadable id), `ActivityExportStreamLost` (GPX/FIT refused for a `streamLost` entry instead of a silently empty file; JSON still works). Per-activity problems never throw in `exportAll`.
  - `encodeEntry` and `fileNameFor` are static and pure, so tests need no journal for the encoding branches; the journal is the only injected dependency (fake journal in tests).
- Owner export on the device: full series, heart rate included when present locally, no route trimming (GPS-PRIV-051). No network, no file writing, no UI: the UI story saves or shares the bytes and the sign-out flow (`ActivitySignOutHooks.offerExport`) can call `exportAll`.

## Verification state

No tests, builds or checks were run (operator rule v4).
