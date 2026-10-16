# S02 test findings, epic 8: remediation batch A

## Epic 8a (jest, `functions/src/__tests__/activity/`)

Items covered: A1, A2, A3, A4, A5, A7, A8 (validator bound), A10, A11, A13, A14, A15, A16. The scaling-profile pin, rules tests, TTL checker, privacy text and access-policy checker belong to epic 8b.

### Final run (head after the last 8a test commit)

Command (cwd `functions`, every test file of the activity directory, which includes all files written or changed in 8a):
`npx jest src/__tests__/activity`
Summary lines:
`Test Suites: 26 passed, 26 total`
`Tests:       744 passed, 744 total`
Before the 8a changes the same directory gave 4 failing tests in 2 suites (670 passed of 674).

### Files

| File | Items | Tests |
|---|---|---|
| `remediation_a_fence.test.ts` (new) | A1 (heartbeat, 24 h boundary, retries record, retry race, fail closed, fenceAt fallback), A5, A10 late sweep | 15 |
| `remediation_a_reconcile.test.ts` (new) | A2, A3, A4, A14, A15 | 21 |
| `remediation_a_expiry.test.ts` (new) | A7 (commit transaction 2, reconciler repair, download URLs, classifyRow) | 12 |
| `remediation_a_validate_bound.test.ts` (new) | A8 validator bound with JSON.parse spy | 6 |
| `remediation_a_settings.test.ts` (new) | A11, A13, A16 | 15 |
| `sweeps_jobs.test.ts` (updated) | skipped-live cases now respect the 24 h window and the retries record | |
| `delete_fence.test.ts` (updated) | fence write refreshes `touchedAt`; A10 unset-bucket delete with and without a stream row | |

### Tests that pinned old behaviour (updated)

- `sweeps_jobs.test.ts` (c2) and the REGRESSION skipped-live run: the third run at +3 days now clears the abandoned fence, so the runs stay inside 24 h and the "never removed" case uses an `accountDeletionRetries` record.
- `delete_fence.test.ts` unset-bucket delete: now `delete_failed` when a stream row exists.
- `ACTIVITY_USER_COLLECTIONS` was not pinned by any earlier test; the new test pins five entries.

### Defects and discrepancies

- No production defect found in the A1..A16 server code covered here.
- Notes versus code: the notes name the scan-cycle fields `streamsCycleStartedAt` / `quarantineCycleStartedAt`; the code stores `streamsCursorCycleStartedAt` / `quarantineCursorCycleStartedAt` (field is `<cursor field>CycleStartedAt`). The tests assert the code names; the notes are shorthand.
- Notes A8 example (2 MB gzip of `1,` to 32 MiB) cannot pass the production compression ratio cap (20): such filler would be rejected as `bomb` first. The tests lift `maxRatio` to reach the separator bound; the production ratio check is covered by `decompression_limits.test.ts`.

### Not covered by 8a

- A6, A9, A12 and the scaling-profile pin (epic 8b).
- A14's log assertion checks the word `unrecognised` in the warn entry, not the exact field set.
- Mutation runs were not performed (operator decision); each assertion was chosen from the notes so that the named behaviour breaking would fail it.
