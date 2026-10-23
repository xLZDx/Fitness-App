# Change record: account export for V0 collections (2026-10-23)

Base: 631279b2. Updated after gate rounds 1 and 2.

## What changed
Server (functions/src/account_export.ts):
- workoutTypedSessions (writerTokenHash withheld on every page), workoutCommandOutcomes (the replay fence by shard: rows {id, status, entries:[{operationKey, code, sessionDigest}]}, payload-hash prefix withheld) and workoutCommandReceipts (allow-listed owner fields: id, status, reasonCode, effect, sessionId, exerciseId, operation, logicalSetId, seq, originDeviceInstallId, revisionBefore, revisionAfter, serverTimeMs, performedAtClientMs, clockSuspect, expireAt; payloadHash and any proof withheld), 2000 rows per page.
- boundedRead for typed sessions and outcomes: batches of 20 documents, stop at the row limit or MAX_EXPORT_BYTES, cursor = last included id, the first row is always taken.
- A shard whose stored entry map is not an object is exported as status CORRUPT_ENTRY_MAP, and every response carries warnings [{section, id, code}], so an invalid map never yields a falsely complete export.

Client (mobile/lib/features/data_export): the collector follows the server's per-section cursors until every section is done (no fixed page cap), saves the first response and each page as numbered part files plus a cursor manifest (written after the part), resumes a later run for the same user, discards progress after 7 days or on a rejected cursor, stops with ServerExportStalledException after 3 pages without cursor movement, and writes one file with exportManifest (pages, row counts, incomplete sections). Sections named in response warnings are reported incomplete with a note that re-running will not fix a damaged record; the resume wording is used only for paging stops. New export_progress_store.dart.

Policy and checkers: scripts/ci/data_lifecycle_policy.json: typed sessions, fence and receipts are BOTH and exported; policy and counters are DELETE. Audited pins for account_export.ts in check_data_access_policy.js and its test: 107, 131, 460, 463, 548.

## Why
Gate round 1: a receipts-only export would be silently incomplete at 180,000 rows against the 50-page client cap; the fence keeps a permanent outcome; 501 documents were read before the byte budget. Gate round 2: the fence does not replace receipts (reason codes, rejected attempts), 256 large shards plus large sessions can exceed 50 pages, and a malformed fence map looked like an empty shard.

## Affected contracts and paths
Account export output (three workout sections, warnings, exportManifest), the mobile export collector and its progress files. No rules, callable or queue change.

## Verification state (test agents)
Server: jest 5/5 suites, 99/99 tests including an unscaled full-population run (256 shards x 12,000 entries, 600 typed sessions of about 400 KB, 5,000 receipts) that completes in 63 pages, the largest 8,342,794 bytes under MAX_EXPORT_BYTES 8,388,608, every row exactly once; check_data_lifecycle_coverage.js OK; test_check_data_access_policy.js passes; check_data_access_policy.js reports only the 5 known unresolved calls in body_scan/manage.ts and nutrition_cache.ts (identical on master). Mobile: 122/122 tests in mobile/test/features/data_export (44 new resume tests). Not run: analyze, full suites, CI. Not tested: assembling a roughly 60 MB export file in memory on a low-memory device.

## Round 3 update: mobile collector hardening (operator ended the review rounds)
The operator stopped further GPT-PM review rounds after round 3 and asked for the PR; the remaining findings were fixed without a fourth review.
- Streaming: rows of each page are written to per-section ndjson files under <support>/server_export_progress/u_<sha256(uid)[:32]>/ (manifest.json, base.json, part_NNNNN.<section>.ndjson, part_NNNNN.done); crash order is part files, then the .done record, then the manifest; the final file is streamed row by row through DataExportSink.deliverStreamed; memory holds one page plus cursors, counts and warnings.
- Account binding: every page's uid must equal the starting uid (a missing uid counts as a mismatch, ExportAccountChangedException); the auth uid is re-checked before and at the end of file writing and the user's progress is deleted on mismatch.
- Privacy: progress is purged at app start and before each export (7 days, orphan users), removed by the account-deletion wipe (reported as export_progress when it fails) and cleared at sign-out.
- Storage faults throw ExportStorageException before more server quota is used; a delivered manifest is marked terminal before the clear, so a failed clear can never be reused as a snapshot.
Verification (test agent): 101 tests in the three data_export files, all passing, including 41 new hardening tests and a memory test (RSS grew 86 MB over a 300 MB export, limit 150 MB). Not run: the rest of the mobile suite, analyze, CI, a device measurement.
Known gaps: a failed clear after delivery is only logged and exposed as cleanupIncomplete; if both the delivered-marking and the clear fail a stale snapshot is possible until the next purge; Android backup exclusion of the support directory is not handled; local repository lists are still held in memory; the purge-failure and wipe-failure tests run only on Windows.
