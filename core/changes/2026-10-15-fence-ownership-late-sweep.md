# Fence ownership and late-upload sweep (GPT-PM MAJOR-02A / MAJOR-02B)

- What: (A) the bulk-delete fence now has one entry per operation and each operation clears only its own; (B) a completed bulk delete schedules a late sweep for objects that arrive through upload URLs issued before it.
- Why: (A) two overlapping delete-all operations of one user shared one fence document; the first to finish deleted it and the other lost protection while still walking. (B) V4 PUT URLs issued before the fence stay valid for 10 minutes and cannot be revoked, so an object could reappear after "done".

## Design A: owned fence
- Document `body_scan_purge_state/delete_fence_<hash(uid)>` is now `{ runs: { <opToken>: { action, startedAtMs, activeUntilMs } } }`. `opToken` = 128 random bits (hex), created on the first page and returned as `fenceToken` with `nextCursor`; the client echoes it with the cursor (mobile `body_scan_manage_api.dart` updated; server validates it as 32 hex chars, else `invalid-cursor`).
- Every registration, refresh and clear is a Firestore transaction (read-modify-write), so concurrent operations cannot clobber each other (a racing write forces a retry). Each page refreshes only its own entry (`activeUntilMs = now + 15 min`); the final page removes only its own entry; the document is deleted when no entry is left. Expired entries are pruned on every write.
- `createBodyScan` refuses while ANY entry has `activeUntilMs > now` (`deleteFenceActive`); expiry bound unchanged (15 min after the last refresh of an abandoned run).
- A continuation whose token is missing, unknown, of another action or lapsed registers a new entry and re-checks every scan (window 0). The original entry is never touched and simply lapses (worst case it over-blocks create for up to 15 min; no under-protection). Legacy-shaped or junk fence documents never block.

## Design B: late sweep
- On the final page, in the SAME transaction that clears the run, `body_scan_purge_state/late_sweep_<hash(uid)>` is written with `{ uid, action, dueAtMs = completion + UPLOAD_URL_TTL_MS (10 min) + 2 min margin }` (max with an existing record). It is a separate document, never read by create, so it does not block create.
- New scheduled function `sweepLateBodyScanUploads` (`purge.ts`, every 5 minutes, `fn-bodyscan`, maxInstances 1, concurrency 1, 120 s timeout, 90 s start budget) runs `runLateSweep`: pages of 200 records with `dueAtMs <= now` (single-field index, no index change), per record lists `users/{uid}/scans/` (500 per page, max 20 pages per run; an unfinished record is kept for the next run), deletes objects whose scan is missing, `cancelled` or `photosState` in `{none, deleted}` (the pass-4 verdict, no age floor), then deletes the record. Live scans (for example created after the delete) are never touched. A malformed record (uid not a single path segment) is dropped. Failures keep the record and log a closed slug only.
- Documented guarantee (also runbooks/body_scan_bucket.md section 9): completion guarantees removal of everything uploaded before the call; an object arriving through an already-issued URL is removed at most 17 minutes after completion (12 min due time + one 5 min schedule interval).
- Verified, not changed: `estimateBodyScan` needs `status == pending && photosState == awaiting_upload` in both the lease and the final transaction and refuses `cancelled`, so a late object cannot be turned back into a stored photo (existing tests: scan-not-ready for `photosState deleted`, scan-cancelled for tombstones). Hence no "re-mark photosState" step exists or is needed.

## Caveats and items for others
- The late-sweep record carries the uid (the sweep must list `users/{uid}/scans/`), for at most about 17 minutes. `scripts/ci/data_lifecycle_policy.json` reason text for `body_scan_purge_state` was updated to say so (classification and access cells unchanged). The comment in `firestore.rules` (line ~863, "Neither carries a uid") and `core/DATA_INVENTORY_2026-08-11.md` row 197 are now slightly inaccurate; not edited here (rules file untouched on purpose). Operator/privacy owner should accept or re-design this trade-off.
- `public/privacy.html` line 79 says users can "delete all cloud photos or all scans at once"; it makes no instantaneous-removal promise, but the exact late-upload window (up to 17 minutes) is not stated. Q-10 is operator-owned; NOT edited.
- Deploy: `sweepLateBodyScanUploads` is a new function and needs deploying by name with the other body-scan functions.

## Paths
`functions/src/body_scan/{shared,manage,purge}.ts`, `functions/src/index.ts`, `functions/src/__tests__/body_scan/{manage,create,purge}.test.ts`, `functions/src/__tests__/scaling.test.ts`, `mobile/lib/features/body_scan/state/body_scan_manage_api.dart`, `runbooks/body_scan_bucket.md`, `scripts/ci/data_lifecycle_policy.json`. No firestore.rules or index change, so the rules emulator test was not run.

## Verification (jest, one file at a time)
See the commit message and the final report for exact counts. Not verified: real Firestore transactions and real GCS signed-URL behaviour (the fake models optimistic retry), Dart test for the token echo, deployment of the new schedule.
