# S02-01 change record: stream payload and sport-to-model table

Date: 2026-10-16. Story: S02-01 "Model v2" (design 3.1, 3.6, 5.1, 5.1a).

## What changed

- New `mobile/lib/features/activity/data/activity_stream_payload.dart`: `ActivityStreamPayload.fromSession(s, allowedKinds)`, a closed-schema builder. Heart rate is hard-denied, kinds are intersected with gps/altitude/speed, laps carry no HR key, provenance is copied through a closed key set with per-string regexes, `meta` holds only laps and provenance (no `userEdits`, `explicitValues`, `mergeNotes`).
- New `workout_model_ownership.dart`: the pinned `kSportModel` table (strength -> workout model, all other sports and the unknown fallback -> activity model) and `modelForSport`.
- New `docs/phase2/s02/S02_01_SPORT_MODEL_NOTE.md`: how the table was verified against the code.

## Why

Design 3.1 and 5.1a (HR never reaches the cloud payload) and the open dependency of 3.6 (table must be pinned before S02-01 closes).

## Affected contracts and paths

`mobile/lib/features/activity/data/` and one note file. The per-string regexes are proposals; the design requires security review before the server validator is written.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
