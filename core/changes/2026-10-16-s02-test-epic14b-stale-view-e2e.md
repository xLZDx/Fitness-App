# S02 test epic 14b: stale view end-to-end

What: s02_stale_view_e2e_test.dart (1 journey).

Why: promise 'after I switch accounts I never see or act on the previous account's conflicts'.

Verification: flutter test --timeout 60s test/features/activity/e2e/s02_stale_view_e2e_test.dart -> 00:01 +1: All tests passed! No production change.
