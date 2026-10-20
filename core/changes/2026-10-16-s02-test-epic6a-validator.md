# S02 test epic 6a: S02-04a validator, schema pin, canonical serialiser, decompression limits

## What
Tests F01-F06 (`stream_validator.test.ts`), F51/F53 (`closed_schema.test.ts`), F91 (`closed_schema_strings.test.ts`), F52 and hash helpers (`canonical_reserialisation.test.ts`), F50 (`decompression_limits.test.ts`) under `functions/src/__tests__/activity/`. One production fix in `functions/src/activity_streams/upload_validate.ts`: invalid UTF-8 is classified by the error `name` as well as `instanceof TypeError`, because the TextDecoder TypeError comes from another realm under jest and was reported as `bad_json` instead of `bad_encoding`.

## Why
Closed-schema, canonical-form and zip-bomb behaviour of S02-04a had no test; the plan rows F03 (exactly +/-90 rejected) and F50 (ratio 20 rejected) contradict the design and are followed as the design says (inclusive; ratio 20 accepted).

## Affected paths
The five test files above; `functions/src/activity_streams/upload_validate.ts` (one line).

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/stream_validator src/__tests__/activity/closed_schema src/__tests__/activity/canonical_reserialisation src/__tests__/activity/decompression_limits src/__tests__/activity/fake_firestore`. Result: 6 suites, 180 tests passed.
