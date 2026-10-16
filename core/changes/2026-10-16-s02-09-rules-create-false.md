# S02-09 change record: debug_sessions rules `create: false`

Date: 2026-10-16. Story: S02-09 (design 8, 8.1; GPS-PRIV-050 / 098; test id R22).

## What changed

- `firestore.rules`: `match /debug_sessions/{sessionId}` now has `allow create: if false` (read, update, delete were already `false`). The Phase 1 shape check (key allowlist, `events.size() <= 500`) is removed because no client can create the document any more; the only writer is the `sendDebugTelemetry` callable (Admin SDK).
- `scripts/ci/data_lifecycle_policy.json`: the `debug_sessions` client access cell `create` is `NONE` (was `CONDITIONAL`) and its `conditionalRefs` entry is removed; the reason text names the callable as the writer.

## Contracts and notes

- Design 8.1 deploy order: (1) callable, (2) client switch, (3) this rule. This commit is step 3 and is a separately revertible deploy; it is not part of the permanent activity rules floor (design 12.1). The design assigns no other permanent exclusion to S02-09.
- The existing test `functions/src/__rules__/data_access_policy.test.ts` (describe `debug_sessions`, the CONDITIONAL create test) and `firestore_rules.test.ts` expect the old accepted create; test agents rewrite them to R22 (client create denied, old valid-shape document denied).

## Verification state

No tests, builds or checks were run (operator rule v4).
