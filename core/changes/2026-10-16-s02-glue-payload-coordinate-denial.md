# S02 glue: coordinate-like string denial in the Dart payload builder

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
`mobile/lib/features/activity/data/activity_stream_payload.dart`:
- New `kCoordinateLike`, byte for byte the server `COORDINATE_LIKE` (`functions/src/activity_streams/schema.ts`).
- Provenance: optional strings (`deviceModel`, `appPackage`, `externalId`) and every `fieldsContributed` element are dropped when they fail their pattern OR match the denial; a record whose `sourceId`, `sourceKind` or `importedAt` cannot be made valid is dropped whole.
- `importedAt` is normalised to whole seconds (`2026-10-16T12:00:00Z`). Reason found while reading the validator: Dart `toIso8601String()` always emits a fraction (`...00.000Z`, `...00.123Z`), and `0.000` / `0.123` match the server denial, so every provenance record would have been rejected and with it the whole upload.
- Laps: `kind` falls back to `auto` and `strokeType` is dropped when not an enum name (cannot happen with the current model, defensive).
- A stream whose `sourceId` would be rejected is left out of the payload (device-only), since the server requires it.

## Why
The client must never send a payload the server validator rejects (design 5.1a).

## Affected contracts and paths
Only the cloud payload form; the local journal record format is unchanged. The server regexes are untouched (the server rule is unchanged, the client conforms to it).

## Verification state
No tests were run. Not verified: compilation; a golden/parity test that every builder output passes the TypeScript validator (suggested for the test agents, including a provenance record with a fractional-second `importedAt`).
