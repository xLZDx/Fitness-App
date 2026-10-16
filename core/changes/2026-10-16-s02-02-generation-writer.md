# S02-02 change record: generation writer

Date: 2026-10-16. Story: S02-02 "Local journal" (design 10 write order; test ids I19, I20, I40, I48).

## What changed

- New `mobile/lib/features/activity/repository/journal_generation_writer.dart`: `JournalPaths` (layout paths, `g<seq>` parsing) and `JournalGenerationWriter`. One mutation writes a new directory `g<seq>`: `streams.bin`, then `record.json` (temp, write, flush, fsync, close, rename), read-back with `streamHash` verified against the bytes on disk, then the COMMIT marker (`seq`, SHA-256 of `record.json`, SHA-256 of `streams.bin`) by atomic rename, which is the commit point. `CURRENT` and the `index.jsonl` append are separate calls made after the commit; the old generation is never deleted by the writer.
- A failure before the COMMIT rename raises `GenerationAborted`; if the COMMIT rename reported an error but a valid marker is on disk, the write counts as committed.

## Why

Design 10: nothing confirmed is overwritten in place; the COMMIT rename is the only commit point; Dart has no directory fsync so none is attempted.

## Affected contracts and paths

`mobile/lib/features/activity/repository/journal_generation_writer.dart`.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
