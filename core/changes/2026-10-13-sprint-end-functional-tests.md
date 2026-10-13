# Change record: sprint-end focused functional tests for the tail-closure code

Tests only; no product code changed. Written and run by four test agents after all sprint coding was committed (f7afd1f, 14ae2ea, 0dceafd, e439624, 7a2e563, 191759b).

| Area | Files | Result when run |
|---|---|---|
| Server deletion paging and export size guard | `functions/src/__tests__/delete_account.test.ts`, `account_export.test.ts` (+8 tests) | 44 of 44 pass across those two files and `booking_export_parity.test.ts` |
| Backup iteration ceiling, account binding, undo, Wear bridge | `mobile/test/features/data_export/backup_envelope_test.dart`, `backup_transfer_test.dart`, `backup_page_test.dart` (new), `mobile/test/core/wear/wear_sync_service_test.dart` | 43 pass |
| Interrupted-deletion wipe marker | `mobile/test/features/account_deletion/interrupted_wipe_test.dart` (new, 15 tests) | 31 pass with `local_data_wipe_test.dart` |
| Health read errors, offline completion, prefetch sharing | `mobile/test/core/health/today_health_read_errors_test.dart` (new), `mobile/test/features/workouts/state/log_session_action_test.dart` (new), `mobile/test/features/workouts/offline/file_offline_video_cache_test.dart` (+6) | 27 pass in the touched files; 404 pass across `test/features/workouts` and `test/core/health` |

**What the tests prove.** Boundary behaviour of the paged sweep (empty, exactly one page, exactly two pages, 1000 rows); an oversized export names every trimmed section; out-of-range PBKDF2 iterations are refused without key derivation; a backup from another account is refused unless explicitly accepted and can be undone; the deletion marker is written after server confirmation, kept when the wipe fails, never written when the server call fails, and a launch-time sweep wipes it once; overlapping "Mark complete" calls produce one write and the streak write is cut at 4 s; concurrent downloads of one url share one fetch; a failed health read is an error, not "no data".

**Not covered, by agent report.** The 4-second timeout inside `FirestoreWorkoutSessionRepository.save` and the rethrow in `PlatformHealthService.readSnapshots` have no test seam (no Firestore fake, no health plugin on the host). Self-booking rows split across sweep pages are read as correct but untested. Undo under a different account is untested. Real Firestore, real Stripe, Kotlin compilation and on-device behaviour were not exercised. `flutter analyze` and the full suites were not run, by the operator's rule.

**Environment note.** The page test needed `flutter gen-l10n` once because the generated localisation in `.dart_tool` was stale; only a build cache was regenerated.
