# Current state: Body Scan + Nutrition Coach sprint

Branch `feature/body-scan-nutrition-coach`, base `42d1b84`. Written 2026-10-15 by C27 from the change records in `core/changes/2026-10-15-*.md`. Numbers below are copied from those records, not re-measured. `core/CURRENT_STATE.md` is a different document (a generated gate ledger) and is not edited here.

Status: the sprint is NOT closed. Final GPT approval, push and PR have not happened.

## What the product does today

- Body check-in uses a PROVISIONAL estimator: Deurenberg formula (BMI, age, sex), reported with a plus or minus 5.0 percentage point range. It runs on the device and IGNORES the photos. The photos are captured and, with the cloud flag, stored and sent, but they do not change the number. No real photo provider exists; the server registry holds only `licensed-api` (reserved, not implemented) and `test-fake` (tests only).
- Nutrition plan, weekly review, weight log and food diary (search, quick log, saved foods) work on the device with bundled data.

## Flags (all default off)

| Flag | Where | Default | Effect when on |
|---|---|---|---|
| `BODY_SCAN_CLOUD` | client `--dart-define`; server `BODY_SCAN_BUCKET` | off | cloud photo path (upload, server estimate) |
| `FOOD_AI` | client; server `FOOD_AI_ENABLED` | off | meal photo, label photo and describe text go to Vertex AI |
| `FOOD_LOOKUP` | client; server lookup flag | off | barcode and server food search (Open Food Facts, USDA) |

Go-live gates are in `runbooks/body_scan_bucket.md`, `runbooks/food_lookup.md` and sprint plan SD-15. Turning a flag on without them is not supported.

## Tests that ran green (as recorded)

| Epic / story | Evidence record | Result |
|---|---|---|
| E0 functions (jest, 7 suites) | `e0-test-evidence` | 409 passed |
| E0 Firestore rules + data access policy (emulator) | `e0-test-evidence` | 547 passed (339 + 208) |
| E0 storage rules (emulator) | `e0-test-evidence` | 82 passed |
| E0 Dart (flags, gates, data notice) | `e0-test-evidence` | 49 passed (flag test also 14 passed with each of the three defines) |
| C12 server (10 suites) | `body-scan-server-tests-final-run` | 477 passed, 0 failed |
| E1 Dart (27 files) | `e1-tests-final-profile-safety-programmes-guards` | 1075 passed, 0 failed |
| E2 onboarding / nutrition profile (6 files) | `e2-tests-onboarding-step`, `e2-tests-onboarding-flow` | 158 passed; `nutrition_profile_route_test` NOT_RUN at that head |
| C13/C14 | `c13-c14-tests` | per-file results recorded, green (e.g. job runner 53, setup panel 21, blur 11) |
| C15 flow, result, wiring | `c15-tests` | per-file results recorded, green (e.g. result view 38, flow driver 28, wiring 9) |
| C16 history, privacy, routes | `c16-tests` | green; `scan_gate_delete_test` 5/5 |
| C17 reminder, entry cards | `c17-tests` | green (settings 14, weekly reminder 33, home card 6) |
| C18 plan state | `c18-tests` | green (e.g. review transaction 57, stored plan 41, in-memory repositories 50) |
| C19 plan UI | `c19-tests` | green (e.g. plan page 25, weight log 20, review card 20, ARB parity 14, routes 5) |
| C20 food functions | `c20-tests` | per-file results recorded in the record |
| C21 generic foods | `c21-tests` | generic foods 68, suggestions 77 |
| C22 diary data | `c22-tests` | 246 tests across 7 files |
| C23 diary UI | `c23-tests` | green (e.g. food API 33, diary providers 34, search 25, routes 8) |
| C24 capture | `c24-tests` | green (e.g. image prep 27, barcode 38, label draft 31, meal scan 24, routes 18, attributions 14, ARB parity 11) |
| C25 export and wipe | `c25-tests` | account export 19, export paging 16, plus the wipe and policy tests recorded there |

Defects found by these runs and fixed are listed in each record (examples: `food_entries` rule expression budget, EXIF kept in blurred and prepared JPEGs, Delete on the failed scan card did nothing, cancel of a local-only scan emitted a delete effect, a file-level import cycle in `activity/data`).

## Reviews and fixes (2026-10-15)

Four read-only reviews ran on head aae03deb: database, flutter, silent-failure, security. All 7 confirmed MAJOR findings and most MINOR findings were fixed in commits 5488425c to 9865066e, each with a change record in `core/changes/`:

- Purge trusted any `body_scans` path (P-1): every pass now requires `users/{uid}/body_scans/{id}`.
- Rollback and the AI kill switch disabled every erase path (P-2): erase now depends on the bucket only; a separate `BODY_SCAN_ACCEPT_UPLOADS` switch gates intake; `runbooks/body_scan_bucket.md` section 7 rewritten.
- Failed scans were never purged (DB-F1): a new purge pass covers them.
- Offline delete of an unfinished scan did not stop it (SF-F1), a loading profile failed a scan permanently (SF-F2), a retry timer was lost while the runner was busy (SF-F3), `deletePhotos` reported deleted while the cloud copy remained (SF-F4): all fixed in the runner and history actions.
- Also fixed: consent recheck before estimate, per-scan attempt and reissue caps, export cursor ties, export page quota 150, redacted gateway and export logs, barcode and search error handling, diary day after midnight, degraded diary entries, unreadable plan state.
- Skipped: SF-F13 (the cache write already swallows errors, the finding was wrong), FL-F7 (optional). Open MINOR: FL-F4, FL-F5, P-6.

Defects found by the re-runs and fixed: the diary day follower never fired after midnight (lazy field), the result card confidence row overflowed at 2x text scale and in Russian, a deleted unfinished scan stayed `queued` after the owed delete flushed (regression of SF-F1).

## Final complete re-run (head 9865066e, agent-written test sets, one file at a time)

| Group | Result |
|---|---|
| Server (31 jest files, 3 emulator rules files) | 34 files, 2,119 tests, 0 failures |
| Mobile group 1 (body_scan, progress_photos scan, home, core, router) | 59 files, 1,398 tests, 0 failures (one first run of `face_region_test` hit a build-cache collision with a concurrent runner and passed alone, +23) |
| Mobile group 2 (nutrition_plan, food_diary, onboarding, activity, accessibility, data_export, account_deletion, l10n, profile, programmes) | 85 files, 2,320 tests, 0 failures |
| Total | 178 files, 5,837 tests, 0 failures, on code head 9865066e (later commits changed only reports and change records) |

Not run in the final re-run: the full suite, analyze, lint, build, CI (operator rule), and the NOT_RUN list below.

## NOT_RUN

- Device-only and emulator-only items beyond the rules and storage groups above: camera, TalkBack and real keyboard behaviour, the `mobile_scanner` barcode path on a device, notification delivery, `integration_test`.
- Real Vertex AI, Open Food Facts and USDA calls; the real bucket IAM canary; any real photo provider.
- Daylight saving time behaviour of the weekly reminder.
- The contrast test written in C26 (`contrast_tokens_test.dart`) now ran in the final re-run: 65 passed.
- `CallableFoodApi` and the signed-in Firestore binding in `body_scan_wiring` (need Firebase or a callable fake).
- No full test suite, analyze, lint, build or CI was run (operator rule).

## Known limits and open items

- `UnavailableFaceCheck` fails closed: with no real post-blur face-check adapter the cloud path cannot pass the face check (D-69). Required before `BODY_SCAN_CLOUD`.
- `/body-scan?scanId=` is ignored by the flow page; only `/body-scan/result/:scanId` opens a given scan.
- Cancelling from `queued` with attempt greater than 0 emits no delete effect although an earlier attempt may have uploaded an object: a possible orphaned upload (E1 record; the purge sweep is the backstop).
- `nutrition_plan` imports `body_scan` in two non-data files (`nutrition_plan_page.dart`, `scan_plan_context_source.dart`). `import_graph_guard_test` pins exactly these two edges; a third fails the test. The data layers are acyclic.
- D-67 redaction gap: the quota log in `accountExportPage` and the export failure log still carry values that are not redacted; the eight new quota actions follow D-67.
- `public/privacy.html` is a draft pending Q-10 (legal text review).
- A reminder notification tap only opens the app; it does not deep link.
- `mobile_scanner` 6.x API usage is not verified on a device.
- The meal thumbnail is stored (encrypted) but not displayed anywhere.
- The Firestore repositories (body scan, plan, weight, diary) are not covered by emulator tests; only the rules are.
- Stray untracked `mobile/test/_probe/probe_test.dart` exists in the worktree and is left for the operator to delete. An uncommitted `mobile/pubspec.lock` change (`mobile_scanner`) is also present and was not committed by this work.
