# S02-08 change record: design corrections and implementation notes

Date: 2026-10-16. Story: S02-08.

## What changed

`docs/phase2/s02/S02_DESIGN.md`: section 6.1 fence bullet, step 1 and step 3 of the account deletion order now match the code (fence after the Stripe cancel and token revoke, immediately before the first sweep; `authDeletedAt` at Step 3b). New section 17 "Implementation notes" lists the deviations recorded in the S02 change records (validator, row fields, quotas, settings, purge, policy, export, telemetry buffer, model, sync).

## Why

The design must match the code (operator request for S02-08). Sources: `core/changes/2026-10-16-s02-*.md`, `functions/src/index.ts` Steps 1c and 3b.

## Deviations

Only the three sentences above were edited in place; everything else settled stays as written. Section 17 is a summary: it was built from the change records and the code comments, not by re-reading every source file.

## Verification state

Documentation only; no checks were run.
