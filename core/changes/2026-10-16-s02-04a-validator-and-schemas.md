# S02-04a change record: closed-schema stream validator, canonical serialiser, SHA-256 helpers

Date: 2026-10-16. Story: S02-04a "Upload: validator and schemas" (design sections 5.1, 5.1a, 5.2 step 2b, 5.4; GPS-PRIV-013, 059, 064; test ids F01-F06, F12, F49-F53, F91).

## What changed

New directory `functions/src/activity_streams/` (pure production code, no callables):

- `schema.ts`: constants only. Closed key sets (top level, `meta`, stream record, lap, provenance), allowed kinds (`gps`, `altitude`, `speed`; no heart-rate kind or key anywhere), canonical units, bounds from design 5.1 (5 MiB compressed, 32 MiB decompressed, ratio 20, 10 s, 200 000 samples), per-kind plausibility ranges, lap and provenance numeric ranges, and the per-string-field rules (length bound AND regex each). Every PROPOSED value is marked as such and the string rules are marked SECURITY REVIEW REQUIRED.
- `validate.ts`: `validateStreamPayload(parsed)`, a pure closed-schema validator. Unknown keys at any depth are rejected (never stripped); heart-rate-looking keys return the distinct code `forbidden_kind`; strict monotonic offsets; inclusive lat/lon bounds; equal lengths; finite numbers only; the output is a new object built key by key in canonical order. Bare codes only.
- `canonical.ts`: `canonicalJson`, `canonicalJsonBytes`, `deterministicGzip` (level 9, gzip header OS byte pinned to 255 so the same JSON gives the same bytes on every platform), `canonicalStoredBytes`.
- `hash.ts`: `isSha256Hex`, `sha256Hex`, `sha256Equal` (constant time). `contentSha256` (hash of the uploaded bytes) and `storedSha256` (hash of the re-serialised bytes) are separate values everywhere.
- `upload_validate.ts`: `validateUploadedStream(compressed, expectedContentSha256, opts)` and `inflateBounded`. Order: size, sha, gzip magic, bounded streaming decompression (absolute cap, ratio, injectable wall clock, injectable chunk source), UTF-8 and JSON parse, closed schema, canonical re-serialisation, stored size. Returns the exact bytes to promote plus `storedSha256` and the kinds, or a bare code. Never throws.

## Why

Design 5.1a: "heart rate never reaches the cloud" is enforced by a server-side closed schema and canonical re-serialisation, not by a client strip or a kind-name check. The commit callable (S02-04b) will call `validateUploadedStream` with the single in-memory read of the quarantine object, so the validated bytes are exactly the promoted bytes.

## Affected contracts and paths

`functions/src/activity_streams/*.ts` (new). Key sets mirror `mobile/lib/features/activity/data/activity_stream_payload.dart` and `SampleStream.toJson`; the shared fixture `stream_schema_keys.json` (tests F53, U37, F91) is a test artefact and is not part of this commit.

## Deviations and notes

- Server string rules add a shared coordinate-like denial (`COORDINATE_LIKE`: a number with two or more decimals, or two numbers joined by a comma) on top of the Dart regexes, because the Dart regexes alone accept `173.25` and `51.5007` (test F91 demands rejection). Consequence: a legitimate `deviceModel` such as `Watch 4.10` would now be rejected server-side; the Dart builder (S02-01, already committed) does not apply this extra rule. Follow-up: align the Dart builder, or decide in the security review. A geohash cannot be detected (documented limit).
- `fieldsContributed` entries are field NAMES; names such as `avgHrBpm` are accepted as labels (no value is carried). Security review to confirm.
- A payload with no stream kind at all is rejected (`empty`).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify with F01-F06, F49-F53, F91.
