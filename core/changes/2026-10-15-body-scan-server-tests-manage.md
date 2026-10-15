# C12 server tests: manageBodyScanData

Date: 2026-10-15. Test file only: `functions/src/__tests__/body_scan/manage.test.ts` (41 tests).

Covers: action/retention/cursor validation, own `bodyScanManage` quota (limit 30) independent of the per-scan delete quota, applyRetention (due photos deleted, longer expiries shortened, never extended, non-stored and takenAt-less scans untouched, boundary, retention 0, other users untouched), deleteAllPhotos (document marked before objects, whole-user prefix sweep of document-less objects on the last page only), deleteAllScans (scrubbed tombstones, existing tombstones re-swept not rewritten), paging with a cursor (250 scans, exactly 200 scans, 201 for applyRetention), exportLinks (1 h V4 read options, stored only, newest first, <= 60 links, cursor by takenAt, no object reads), failure handling and log content.

Verification: `npx jest src/__tests__/body_scan/manage.test.ts` in `functions/`: 41 passed, 0 failed. No production code changed.
