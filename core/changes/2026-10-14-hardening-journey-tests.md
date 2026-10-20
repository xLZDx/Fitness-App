# Change record: journey tests for the hardening sprint, live-router flag seam, scan lifecycle fix

## What changed
### Production (two small changes found by the tests)
- `mobile/lib/core/config/demo_features.dart`: new `demoFeaturesEnabledProvider` (defaults to `kDemoFeaturesEnabled`); `mobile/lib/core/router/app_router.dart` reads it in the redirect. Under `flutter test` the compile-time flag is always true, so a release build's denial of gated paths could not be driven through the live router; a test can now override the provider with false.
- `mobile/lib/features/progress_photos/scan/ui/scan_capture_screen.dart`: the screen observes the app lifecycle. Anything but `resumed` resets the auto-shutter machine, stops the speaker and clears the countdown digit, so a countdown never survives the app leaving the foreground (found by `scan_capture_lifecycle_test.dart`).

### Tests (written and run by the e2e-runner agents, reviewed by the functional-test-reviewer)
- Release deny-by-default: `mobile/test/router/app_router_gating_test.dart` (live `GoRouter` with the flag off: every gated path, with `?x=1` and trailing-slash variants, a restored cold-start location and notification-tap style navigation land on `/home`; the same paths are reachable with the flag on; `/coaches/x` is not gated), `mobile/test/features/marketplace/marketplace_release_guard_test.dart` (every booking operation refuses with the flag off and makes no repository call), `mobile/test/features/progress_photos/progress_photos_release_unavailable_test.dart` (store failure in release: every write throws, no demo data on screen).
- Account switch and deletion: `mobile/test/features/training_context/account_switch_journey_test.dart` (A to B to A: chooser, suggestions, reminder, key isolation), `mobile/test/features/account_deletion/account_deletion_journey_test.dart` and additions to `local_data_wipe_test.dart` (real wipe with two accounts on fake storage), `mobile/test/core/notifications/reminder_id_test.dart` (literal ids).
- Recommendations: `mobile/test/features/safety/age_policy_journey_test.dart` (real plan, suggestion and programme builders for ages 15, 17, 18, 64, 65, 70 and unknown, literal caps), additions to `age_policy_test.dart` (rollover on 1 January, senior beginner caps), `mobile/test/features/training_context/training_context_generation_journey_test.dart` (each context through providers, planner and home).
- Body scan: `mobile/test/features/progress_photos/scan/ui/scan_journey_disk_test.dart` (real encrypted stores on disk: capture, save, gate refusals, delete my scans, compare modes), `scan_capture_lifecycle_test.dart` (permission denied, pause cancels the countdown, partial set never saved), additions to `scan_access_test.dart` (exhaustive priority table).
- Coach: `mobile/test/features/form_check/coach_engine_journey_test.dart` (good, faulty and low-visibility synthetic sequences for the registry exercises), additions to `coach_registry_content_test.dart` (registry structure, advisory rows, controller level).
- Functions: new blocks in `delete_account.test.ts` (failure combinations, call order including the shared-record sweep) and `stripe_webhook_events.test.ts` (replay and out-of-order events, deleted users, coach-booking confirmation).

## Why
The documentation gate asked for falsifiable proof of the release gate, the account-switch isolation, the age policy and the deletion fence; the test review listed what the existing tests did not prove.

## Affected contracts and paths
Plan `core/plans/PRODUCT_HARDENING_SPRINT_2026-10-13.md`: access priority of the body scan corrected to the pinned code order (signed out, under 18 or unknown age, Supporter, consent); exception register extended (year-precision age, authored coach rows, plank dead zone).

## Verification state
Focused runs by the agents on this tree: 649 Flutter tests (17 explicit paths) and 119 Jest tests (5 files) pass. Findings kept as product decisions, not defects: age is stored as a birth year, so the age bands switch on 1 January; the plank sag cue has a dead zone between its threshold and the hold band edge. Not verified: device camera, pose model, speech, Keystore, Firestore emulator.
