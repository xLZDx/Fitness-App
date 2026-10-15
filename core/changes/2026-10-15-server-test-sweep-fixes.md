# Server test alignment with review fixes

- What: updated four stale server test expectations (purge now has four body_scans queries; reissue writes pendingExpiresAt; estimate re-checks consent; settings read failure path) and added a purge starvation case (1000 fake nested body_scans documents plus one real scan).
- Why: the server review fixes (5488425c..73e2cb01) changed behaviour that these tests pinned.
- Paths: functions/src/__tests__/{firestore_indexes_body_scan,body_scan/create,body_scan/estimate,body_scan/purge}.test.ts.
- Contracts: none changed; product code untouched.
- Verification: each of the 17 affected server test files was run alone by the test agent; all green after the fixes.
