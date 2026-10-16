# S02 design document (draft for review)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
Added `docs/phase2/s02/S02_DESIGN.md` (12 sections: scope, current state, data model, Firestore, streams storage, retention and deletion, export, debug telemetry guarantee, consent and dedup, merger performance, stories, rollout and open questions). Authored by a `technical-writer` agent (Sonnet 5.5); each statement is labelled FACT, PROPOSED or OPEN. Recommendations in the draft: dedicated private bucket with signed URLs and a scheduled purge for the user-set expiry; sanitising callable for debug telemetry; file journal as the local store.

## Why
Phase 3 (Design) of S02. The draft goes to architecture and security review, then to a test plan and GPT-PM.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/`. No code, rules or configuration changed.

## Verification state
No tests or checks were run. Items the author did not verify are marked OPEN in the file: paging code in `account_export.ts`, `firestore.indexes.json`, the sync-log path, whether the debug sink swallows permission errors, whether the A-5 version strings exist in the models, `runbooks/body_scan_bucket.md`. Performance budgets and size bounds are proposals and are not measured.
