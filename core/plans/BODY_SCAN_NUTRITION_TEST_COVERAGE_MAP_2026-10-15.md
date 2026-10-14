# Body Scan + Nutrition Coach - requirements-to-test coverage map

**Status:** MAP v1, authored by the functional-test-reviewer role (design only). Date 2026-10-15. Branch `feature/body-scan-nutrition-coach`, base `master` `42d1b84`. Nothing here was executed: no test, analyzer, build, emulator or CI run. Every test file below is to be CREATED (`N`) or EXTENDED (`X`) in the test phase by `e2e-runner`, using the assertions in this map as the specification.

**Inputs (read, not re-derived):** operator brief 2026-10-15 (scratchpad `body_scan_brief.md`), `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` (sections 6, 7, 12-17, 20, 28-31, decisions D-1..D-36), `core/plans/BODY_SCAN_NUTRITION_SPRINT_PLAN_2026-10-15.md` (section 6.2 file names are reused where they exist), and the existing test layout (`mobile/test/...`, `functions/src/__tests__`, `functions/src/__rules__`, `functions/src/__e2e__`, `functions/scripts/run_emulator_tests.js`).

## 0. Operating policy for the test phase (operator update 2026-10-15)

1. The test-authoring agents (`functional-test-reviewer` designs, `e2e-runner` writes and runs; `adk-test-engineer` only if available) write DETAILED functional tests for every change in this map, not smoke tests.
2. After EACH epic (E0..E7) the authoring agents run the COMPLETE set of agent-written tests authored so far (every file of every epic up to and including that one, listed explicitly in section 9, not a sample). After the last epic they run the complete final set again (section 10). Fixes re-run the complete set so far, not only the failing file.
3. The coordinator never runs tests. It reads the agents' recorded results.
4. The repository's legacy full suite, lint, analyze, build, CI and CI-mimicking jobs stay PROHIBITED: no bare `flutter test`, no `npm test`, no bare `jest`, no `flutter analyze`, no `scripts/ci/*.js` checkers. Every command in this map names files explicitly.
5. A test counts as evidence only if it would FAIL when the guarded behaviour is broken. Every assertion row below states the failing condition. Expected numeric vectors in this map are hand-computed (2026-10-15) and MUST be re-derived independently by the test author, never copied from the implementation's output.
6. Failures are classified product bug / test defect / flake / environment with evidence (output, trace, request). Flake is proven by repeating the single file at least 5 times on the same head before use of the word; quarantine needs marker + issue link + date and is reported separately (none planned). Assertions are never weakened to get green.

## 1. Levels, owners, commands

| Level code | Meaning | Where |
|---|---|---|
| U | pure-Dart unit (host, `flutter_test`, fakes for ports; no widget pump) | `mobile/test/...` |
| W | widget test (pumped widgets, fakes for ports, RU and EN locale) | `mobile/test/...` |
| J | Jest for Cloud Functions (firebase-admin mocked, no emulator) | `functions/src/__tests__`, `functions/src/monitoring/__tests__` |
| R | Firestore rules emulator | `functions/src/__rules__` |
| S | Storage rules emulator | `functions/src/__rules__` |
| Y | journey (multi-step flow through real providers with fakes, or emulator e2e) | `mobile/test/...`, `functions/src/__e2e__` |

**Owner column.** `F>E` = scenario and assertions designed by `functional-test-reviewer`, file written and run by `e2e-runner`. Rules and policy tests (R, S) are additionally reviewed by `security-reviewer` and `database-reviewer` in the later specialist-review phase (not authoring).

**Commands (single named files only).** Replace `<rel>` with the path in the index (section 8).

| Cmd | Command |
|---|---|
| FT | `Set-Location D:\Repo\Fitness_App_bodyscan\mobile` then `flutter test <rel under mobile/, e.g. test/features/nutrition_plan/data/energy_math_test.dart>` (several files may be listed on one line) |
| JT | `Set-Location D:\Repo\Fitness_App_bodyscan\functions` then `npx --no-install jest <rel under functions/, e.g. src/__tests__/body_scan_create.test.ts>` (config `jest.config.js`, which loads `jest.setup.js`) |
| RE | `Set-Location D:\Repo\Fitness_App_bodyscan\functions` then `node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules <rel>` - needs test-infra change TI-1 |
| RS | same with emulators `firestore,storage`: `node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/storage_rules.test.ts` - needs TI-1 and TI-2 |
| EE | `node scripts/run_emulator_tests.js jest.e2e.config.js firestore,auth demo-fitness-e2e src/__e2e__/account_deletion.e2e.test.ts` - needs TI-1 |

**Test-infrastructure items (done by `e2e-runner` at the start of the test phase, each recorded in a change record):**

- **TI-1.** `functions/scripts/run_emulator_tests.js` currently runs `npx jest --config <config>` with NO file argument, so `npm run test:rules` runs every rules file. Make it append `process.argv.slice(5)` to the inner jest command (file paths and `-t` filters). Behaviour with no extra arguments stays identical.
- **TI-2.** `firebase.json` gets the `storage` rules entry and a `storage` emulator entry, and `storage.rules` exists (design 6.3), otherwise the RS command cannot start. The test uses `firebase/storage` (`ref`, `uploadBytes`, `getBytes`) against `env.authenticatedContext(uid).storage()`.
- **TI-3.** The jest mock of `firebase-admin/storage` used by `delete_account.test.ts` / `account_deletion_reconcile.test.ts` / body-scan tests gets `bucket().file().getSignedUrl`, `getMetadata`, `download`, `delete`, `deleteFiles`, with call recording.
- **TI-4.** Instrument pre-flight (read-only, one existing untouched file per level, before the first epic): `mobile/test/core/frame_brightness_test.dart` (FT), `functions/src/__tests__/video_urls.test.ts` (JT), `functions/src/__rules__/firestore_rules.test.ts` (RE). If a pre-flight fails the instrument is broken; fix the environment before trusting any new result.

## 2. Requirement id scheme

`SCAN-` capture, state machine, upload, result math, trend, history, reminder, estimator and callables. `PLAN-` nutrition maths, plan, review, ownership, UI. `ONB-` onboarding and nutrition profile. `SAFE-` exclusions and every clamp. `PRIV-` blur, consent, retention, deletion, export, logging, device-only data. `FOOD-` food scanning, diary, nutrition data. `ACT-` activity model and merge. `PROG-` nutrition-aware programme level. `RULES-` Firestore/Storage rules, indexes, callable wiring. `I18N-` localisation. `A11Y-` accessibility.

## 3. Hand-computed reference vectors (author re-derives independently)

Calendar facts: 2026-10-15 is a Thursday; 2026-01-01 is a Thursday, so ISO year 2026 has 53 weeks (2026-12-31 and 2027-01-01 are both `2026-W53`; 2027-01-04 is `2027-W01`). `PersonalInfo.lowestAgeAt(year) = year - birthYear - 1`, so with clock year 2026 birth year 2007 gives 18 (adult) and 2008 gives 17 (minor), for clocks 2026-01-01, 2026-06-15 and 2026-12-31 alike.

| Vector | Inputs | Expected |
|---|---|---|
| V-BMR-M | male, 80 kg, 180 cm, 30 y | BMR 1780.0 |
| V-BMR-F | female, 60 kg, 165 cm, 30 y | BMR 1320.25 |
| V-BMR-U | unspecified, 80 kg, 180 cm, 30 y | BMR 1697.0 (constant -78) |
| V-DEU-M / F / U | 80/180/30 male; 60/165/30 female; 80/180/30 unspecified | 20.33 / 27.95 / 25.73 percent body fat (Deurenberg), half-width 5.0, range 15.33-25.33 for male |
| V-FLOOR-F | female, 50 kg, 155 cm, 40 y, sedentary | BMR 1107.75, TDEE 1329.3, floor 1200 (absolute floor wins), deficit capped by TDEE-floor = 129.3, range low >= 1200, high <= 1329.3 |
| V-FLOOR-M | male, 100 kg, 190 cm, 25 y | BMR 2067.5, floor 2068 (relative floor beats absolute 1500) |
| V-LOSE-M | V-BMR-M inputs, moderately active (1.375), lose, BMI 24.69 (row < 25: 0.50 %/wk) | TDEE 2447.5, kgPerWeek 0.40, dailyDelta 440, cap 0.25*TDEE = 611.9 not binding, target 2007.5, range 1860-2160 |
| V-LOSE-CAP | same person but BMI row 25-30 (0.75 %/wk, 0.60 kg/wk, 660 kcal/day) | the 25 % TDEE cap (611.9) binds, deficit 611.9, target 1835.6, range 1690-1990 |
| V-PROT-80 | 80 kg, BMI <= 30, lose | protein min 128 g, target 160 g, max 176 g |
| V-PROT-OB | 110 kg, 170 cm (BMI 38.06), lose, kcalMid 1800 | Wref 86.7 kg, min 139, target 173, raw max 191 but 40 % of kcalMid cap = 180 so max 180 |
| V-PROT-220 | 110 kg, 195 cm (BMI 28.9), kcalMid >= 2200 | 2.2 g/kg = 242 but absolute cap 220 |
| V-FAT | kcalMid 1800, Wref 80 | fatMin max(48, 40) = 48, fatMax 70 |
| V-EWMA | S0 25.0, next reading 27.0 after 7 d, tau 21 | alpha 0.28347, S 25.5669; after 0.2 d alpha uses 0.5 d: 0.02353; after 40 d alpha uses 28 d: 0.7364; winsorised 35.0 reading: x' = 29.0, S 26.1339 |
| V-EWMA-W | tau 7 d, daily readings | alpha 0.13312 |
| V-THEIL | weights 80.0 d0, 79.8 d3, 79.6 d7 | slope -0.4 kg/week (median of -0.0667, -0.0571, -0.05 times 7) |
| V-NOISE | provisional hw 5 and 5 | noisePts 7.07; hw 0.5 and 0.5 gives 0.71 so floor 1.0 applies; change of exactly 1.0 reads "no meaningful change", 1.01 reads up/down |
| V-ATWATER | kcal 100 | macros summing (4P+4C+9F) to 125 accepted (25 %), 126 flagged `dataInconsistent`; 75 accepted, 74 flagged |
| V-OFF | barcode 3017620422003 | per 100 g kcal 539, kJ 2252, protein 6.3, carbs 57.5, fat 30.9; kcal field present so 539 is used, not 2252/4.184 = 538.2; `serving_size` absent handled; GTIN check digit valid |
| V-GTIN | 4006381333931 (EAN-13), 96385074 (EAN-8), 036000291452 (UPC-A), 10012345678902 (ITF-14), 3017620422003 | all valid; changing the last digit of each makes it invalid |
| V-REM | weekday 7, 08:00 local | scan Thu 2026-10-15 10:00: anchor = scan + 5 d = Tue 2026-10-20 10:00, next fire Sun 2026-10-25 08:00 (not 10-18); scan Sun 2026-10-11 07:00: next fire Sun 2026-10-18 08:00; anchor exactly Sun 2026-10-18 08:00: strictly after, so 2026-10-25 08:00; anchor Sun 07:59: same day 08:00 |
| V-STEPS | sedentary base 6000 / very active 10000 / bucket 12500 / bucket 2500 | goals 7000 / 11000 / 12000 (clamped) / 6000 (clamped) |
| V-REVIEW | intended -0.40 kg/wk | tol max(0.15, 0.10) = 0.15; intended -0.80: tol 0.20; |e| = tol is onTrack, tol + 0.01 is behind/ahead; tooFast when loss faster than maxRateKg * 1.25 (max 0.60 gives threshold 0.75: -0.75 not, -0.76 yes) |
| V-TRAIN | deficitPct | 0.0999 -> 1.0; 0.10 -> 0.95; 0.1999 -> 0.95; 0.20 -> 0.85 |

## 4. Requirement coverage tables

Reading the tables: `Lvl` is the primary level (U/W/J/R/S/Y, section 1). The command for a row is fixed by its level: U, W and Y under `mobile/` use `FT`, J uses `JT`, R uses `RE`, S uses `RS`, and the emulator Y file uses `EE`; the exact file path is in the index (section 8) under the Tnn id. Owner is `F>E` on every row. "Fails if" is the broken behaviour that turns the assertion red.

### 4.1 SCAN - weekly body scan

| ID | Behaviour | Lvl | Test (Tnn file) | Key assertions (fail if broken) |
|---|---|---|---|---|
| SCAN-01 | Readiness shows four live checks; luminance window 0.25-0.92 is a real check | U | T52 readiness_evaluator_test | luminance 0.24 -> Lighting "improve", 0.25 -> good, 0.92 -> good, 0.93 -> "too bright"; distance move back / closer / good at its thresholds; position centred vs off-centre; pose orientation front/side/back mismatch gives its own hint. Fails if the old fixed 0.1/0.5 values are still used |
| SCAN-02 | Auto capture needs all four checks green for holdMs 1000, then 3-2-1, and any lost readiness cancels | U | T53 auto_shutter_machine_test | readiness green 999 ms -> no countdown, 1000 ms -> countdown starts; countdown 3,2,1 ticks then shutter; readiness lost at count 2 -> back to idle and no shutter; 3000 ms cooldown after a shot; one failing check (each of four in turn) blocks capture |
| SCAN-03 | Manual shutter while not ready records `manualOverride[pose]=true` and adds `manualCapture` | W | T68 scan_capture_screen_test | manual tap with Distance red -> record has `manualOverride.front == true`; manual tap while ready -> false; `manualCapture` appears in check items and the displayed confidence drops one level; capture screen pops with the scan id (`onSaved`) |
| SCAN-04 | Setup status panel rows Distance / Lighting / Position / Pose with icon + text + state | W | T59 setup_status_panel_test | each of 4 rows renders text for every state in both EN and RU; state is never colour-only (icon + text found); skeleton overlay mounted without changing semantics tree (T60) |
| SCAN-05 | Skeleton overlay draws joints/bones from the latest pose frame and is decorative | W | T60 skeleton_overlay_smoke_test | painter builds with full, partial and empty landmark lists without throwing; wrapped in `ExcludeSemantics`; low-likelihood landmarks skipped |
| SCAN-06 | `ScanRecord` v2 (analysis block, weightKg, capture flags, pendingRemoteDelete) is tolerant and v1 still reads | U | T48 scan_models_v2_test | v1 JSON parses with `analysis == null` (legacy local-only); v2 round trip is equal; unknown `analysis.status` string degrades to a safe value; missing optional fields default; atomic save leaves no partial file (T49) |
| SCAN-07 | Flow machine: every transition of the design table | U | T26 body_scan_flow_machine_test | idle->intro on open; intro->weightPrompt when latest weight entry is 3 days old, 2 days 23 h -> straight to capturing(front), no entry -> weightPrompt; weightLogged/skipWeight -> capturing(front); captured(front)->capturing(side)->capturing(back)->reviewing; retake(p) -> capturing(p); confirm->savingLocal->queued; online->uploading(front) when provider needs photos, ->analysing when not; uploaded(p) chain; estimated->verifying->done; each illegal event leaves the state unchanged and returns no effect |
| SCAN-08 | Cancel from every active state | U | T26 body_scan_flow_machine_test | cancel from each of intro, weightPrompt, capturing x3, reviewing, savingLocal, queued, uploading x3, analysing, verifying -> `cancelled`; effect list contains `deleteBodyScan` only when something may be uploaded (uploading/analysing/verifying) and marks `pendingRemoteDelete` when offline |
| SCAN-09 | Error -> queued with attempt+1, backoff `min(2^attempt, 300)` s, max 5, then failed(retriable) | U | T27 body_scan_job_test | delays for attempts 0..5 are 1,2,4,8,16,32 s capped (no value above 300); after 5 failed attempts state is `failed(retriable: true)`; `retry` resets attempt to 0 and goes to queued; non-retriable error never auto-retries |
| SCAN-10 | Job runner resumes after app kill; queue = non-terminal records; one scan at a time; idempotent | U | T55 body_scan_job_runner_test | persisted record `uploading` with attempt 2 is picked up on start and resumes from the correct stage; runner called twice makes `createBodyScan` with the same scanId (no duplicate); offline -> nothing sent, `online` event -> sent; second queued scan waits behind the first; v1 record (no analysis) is NEVER selected (D-6); terminal states never re-run; account-deletion fence aborts the runner |
| SCAN-11 | Upload: sequential PUT per pose with headers from the callable; 1/2/4 s retry; 403 triggers fresh URLs | U | T56 upload_flow_test | request carries returned `Content-Type` and `x-goog-content-length-range` headers; transient 500 retried at 1, 2, 4 s then surfaces error (4th attempt not made); 403 -> one idempotent `createBodyScan` then retry succeeds; poses uploaded in order front, side, back, never in parallel; cancel aborts the in-flight request |
| SCAN-12 | Stage UI: Photos secured -> Body composition -> Plausibility -> Trend -> Result saved, elapsed time, Cancel | W | T63 analysis_progress_view_test | each machine state highlights exactly its stage; provider without photos shows "kept on this device" for the first stage; elapsed counter increments from an injected clock; Cancel present and first in focus order |
| SCAN-13 | Result: value with likely range, never a bare number, plain-language limit, provisional banner | W | T64 result_view_test | value, low and high rendered with one decimal in EN (30.8) and RU decimal comma (30,8); text "can vary by about 1-2 points" present; provisional result shows the banner; non-provisional hides it; fat mass and lean mass ranges shown; unknown/closed-set violation code is not rendered (I18N-07) |
| SCAN-14 | Fat/lean mass ranges and edit-weight recompute | U | T22 scan_result_math_test | W=80, v=25, range 22-28: FM 20.0 (17.6-22.4), LM 60.0 (57.6-62.4); editing weight to 82 recomputes FM/LM and leaves estimate untouched; weight 0 or null -> no mass shown, no divide-by-zero |
| SCAN-15 | Points to goal and start value | U | T22 scan_result_math_test | pointsToGoal = smoothed - target; null when no body-fat target (falls back to weight progress); start value is the baseline's RAW value, not smoothed |
| SCAN-16 | Noise threshold and change label | U | T20 scan_trend_test | `noisePts = max(1.0, sqrt(hw_t^2 + hw_p^2))`; V-NOISE: provisional 5/5 -> 7.07 so a 7.0-point change is `noMeaningfulChange`, 7.2 is up/down; hw 0.5/0.5 floor 1.0 with |change| 1.0 -> none, 1.01 -> up/down; sign gives down vs up |
| SCAN-17 | 4-week trend label | U | T20 scan_trend_test | needs >= 3 readings in the window else no label; meaningful iff `abs(S_t - S_t-28d) > max(1.0, 0.8*mean(hw))` (boundary equal -> not meaningful) |
| SCAN-18 | EWMA smoothing parameters | U | T20 scan_trend_test | V-EWMA values within 1e-4: tau 21 d gives S 25.5669; dDays clamped to [0.5, 28] (0.2 d and 40 d cases); winsorise +-4: 35.0 reading acts as 29.0 giving 26.1339, raw dot kept and flagged; tau 7 d weight alpha 0.13312; first reading S0 = x0; irregular spacing differs from fixed-alpha result |
| SCAN-19 | Weight slope (Theil-Sen) | U | T21 weight_slope_test | V-THEIL -0.4 kg/wk; < 3 entries -> null; 3 entries spanning 6 days -> null, 7 days -> value; pairs with dDays < 2 skipped; entries older than 21 days ignored; single +2 kg outlier moves slope by < 0.15 where a least-squares fit would move > 0.3 (fixture verified by author) |
| SCAN-20 | Plausibility and trend verification codes | U | T23 plausibility_test | value 2.9 / 60.1 -> `estimateOutOfRange` (reject), 3.0 / 60.0 accepted; |v - deurenberg| 12.0 -> no chip, 12.1 -> `estimateFarFromProfile` and confidence one level lower; weight jump 3.0 kg in 7 d no chip, 3.1 -> `weightJump`; hw 4.0 no chip, 4.1 -> `wideRange` and confidence low; |v - S| = max(4, 2.5*hw) boundary -> `largeJumpVsTrend` only above it |
| SCAN-21 | Closed check codes map to l10n key and action | U | T24 check_items_test | all 13 codes present, each has an action and a key name; unknown string from a provider is dropped; list order stable; `weightStale` triggers at > 7 days |
| SCAN-22 | Trend chart: dots = raw readings with whiskers, line = smoothed, last 12 scans, legend | W | T65 trend_chart_test | 13 scans -> 12 plotted (oldest dropped); legend text says dots are single noisy readings; outlier dot marked; data table rows equal plotted points; one-sentence summary present |
| SCAN-23 | History list with baseline marker and compare entry points | W | T66 scan_history_list_test | exactly one row marked baseline (the first `done` scan); rows show date, weight, body fat, trend label; only baseline -> compare action asks for a second scan; two or more -> baseline-vs-latest and previous-vs-latest entries |
| SCAN-24 | Compare accepts initial mode | W | T69 scan_compare_screen_test | `mode=baseline` preselects first and latest, `mode=previous` the last two; side-by-side and slider still work; single scan shows the "need a second scan" state |
| SCAN-25 | Delete this scan's photos / delete all scans also call the server | W | T70 scan_gate_delete_test | confirm dialog first; confirm -> `deleteBodyScan(photosOnly: true)` then local delete; cancel makes no call; offline -> `pendingRemoteDelete` stored and retried; delete-all calls the callable per scan with cloud copies |
| SCAN-26 | Weight prompt before scan | W | T62 weight_prompt_sheet_test | "log weight first" writes `weight_entries/<local day>` with source `scan`; "scan without updating" writes nothing; kg outside 30-300 refused in the field |
| SCAN-27 | Weekly reminder: weekday/time rule, defaults, gap, v1 fallback | U | T50 scan_reminder_weekly_test, T51 scan_reminder_test | defaults weekday 7 and 480 min; V-REM four cases exact to the minute; disabled -> `cancelReminder` and no schedule; v1 per-uid bool is honoured as `enabled` fallback; notification title/body non-empty in EN and RU; resync after save, delete, settings change and app start; same `kScanReminderId` |
| SCAN-28 | Settings document defaults and shape | U | T58 body_scan_settings_test | absent doc = retention 0, reminder Sunday 08:00 enabled per rule, no consent; retention outside {0,30,90,365} rejected client-side; consent version bump invalidates older consent; round trip |
| SCAN-29 | History merges Firestore entries and local records by scanId | U | T57 body_scan_history_merge_test | same scanId merged (server estimate + local photos); server-only and local-only both shown; local-only v1 shown as "stays on this device"; ordering by takenAt desc; limit 120 |
| SCAN-30 | Provisional estimator | J | T78 provisional_estimator.test | V-DEU vectors within 0.01; result clamped to [5, 55] (BMI extremes); half-width exactly 5.0; confidence `low`; `checkCodes` contains `provisionalEstimator`; `requiresPhotos == false`; `provisional == true`; modelId `provisional-anthropometric`, version `deurenberg-1991-v0`; sex unspecified uses s = 0.5; photos ignored (same output with and without) |
| SCAN-31 | Estimator registry | J | T80 estimator_registry.test | default is provisional; `licensed-api` throws `failed-precondition: provider-not-configured`; `test-fake` only under emulator/jest flag, otherwise refused; unknown id refused |
| SCAN-32 | `createBodyScan` validation, idempotency, consent, quota, signing | J | T74 body_scan_create.test | scanId regex: 7 chars, 65 chars, `a b` rejected, 8 and 64 chars accepted; takenAt exactly now-7d accepted, -7d-1 ms rejected, now+5 min accepted, +5 min+1 ms rejected; subject age 17/18/100/101, height 119/120/230/231, weight 29/30/250/251, bad sex enum; order auth -> App Check note -> non-anonymous (anonymous gets refusal) -> validate -> quota; states: done returns stored entry unchanged, pending re-issues URLs, failed resets to pending, cancelled -> `scan-cancelled`; `requiresPhotos` with consent version 0 -> `consent-required`; URL options v4, write, 10 min, contentType image/jpeg, header `x-goog-content-length-range: 1024,3145728`; provisional provider -> no `uploads`, `photosState none`; quota 31st call -> `resource-exhausted`; pendingExpiresAt = createdAt + 48 h; signing error -> `internal` |
| SCAN-33 | `estimateBodyScan` | J | T75 body_scan_estimate.test | non-pending doc refused; missing object -> `missing-upload:<poses>`; size 1023 / 3145729 B refused, 1024 and 3145728 accepted; non-JPEG signature refused; provider throws -> quota refunded and doc stays pending; quota 15th call refused; success writes estimate + `done` + removes `pendingExpiresAt` in ONE transaction; first done scan gets `isBaseline`, second does not; retention 0 deletes objects inline, 30 sets `photosExpireAt = now+30d`; timeout 25 s -> retriable `internal`; log event has no uid and no body numbers |
| SCAN-34 | `validateEstimate` | J | T79 validate_estimate.test | low 2.9 / 3.0, high 60.0 / 60.1, width 20.0 / 20.1, value outside [low, high], NaN, Infinity, string numbers, confidence outside enum, unknown check code, modelId empty and 65 chars -> invalid -> `provider-output-invalid`, doc stays pending (no silent clamp) |
| SCAN-35 | `deleteBodyScan` | J | T76 body_scan_delete.test | deletes all objects under `users/{uid}/scans/{scanId}/` and only that prefix (other uid / other scan untouched); photosOnly sets `photosState=deleted` + `photosDeletedAt` and keeps the doc; otherwise deletes doc; second call idempotent; another user's scanId refused; quota 61st refused |
| SCAN-36 | Scheduled purge | J | T77 body_scan_purge.test | `stored` + expired -> objects deleted, state `deleted`; pending past `pendingExpiresAt` -> `cancelled` and objects deleted; not-yet-expired untouched; 201 docs -> two pages; stops starting work after 240 s (injected clock); one failing scan logged by id only and the rest continue; re-run is a no-op |
| SCAN-37 | Whole scan journey with fakes (intro -> weight -> capture x3 -> save -> analyse -> result -> plan decision) | Y | T71 body_scan_journey_test | each stage reached in order; result shows range and banner; plan decision visible only for eligible users; back button and cancel at each step safe |
| SCAN-38 | Kill and resume journey | Y | T72 body_scan_kill_resume_journey_test | process "killed" at uploading(side), analysing and verifying -> fresh container resumes to done with exactly one `createBodyScan` and one `estimateBodyScan` effective call (idempotent ids); offline start -> queued, online -> done; cancel mid-upload deletes uploaded objects |
| SCAN-39 | Entry points and gate unchanged | W | T87 progress_page_test, T88 home_dashboard_test | Progress shows both new cards; Home card shows next scan due or kcal remaining; hidden for `referProfessional`; `scanAccessProvider` unchanged: minor, anonymous, free tier, missing local consent still blocked |
| SCAN-40 | Flags default OFF and flagged paths degrade | U, J | T01 body_scan_flags_test, T02 feature_flags.test | all three flags false by default; flag off -> no cloud consent sheet, no upload path; server callables behind a flag throw `failed-precondition: feature-disabled`; client maps it to a non-retrying calm state |

### 4.2 PRIV - privacy, retention, deletion, export

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| PRIV-01 | Face region geometry | U | T25 face_region_test | head landmark likelihood 0.29 ignored, 0.30 used; box contains every head landmark plus the 15 % margin; radius = max(1.35*maxDist, 0.40*shoulderWidth); no head landmarks -> crown estimate (centre shoulderMid.y - 0.10H, half-side 0.14H, H = shoulder-to-ankle / 0.78); one shoulder hidden uses 0.45*torso; box clamped to image bounds |
| PRIV-02 | Blur changes the face region, nothing else, irreversibly | U | T54 blur_service_test | synthetic high-frequency image: pixel variance inside the box drops below a fixed fraction, pixels outside equal a re-encoded unblurred control within tolerance; block size max(8 px, side/10); output long edge <= 1280 |
| PRIV-03 | Fail closed | U | T54 blur_service_test, T56 upload_flow_test | no head AND no shoulders, or missing landmarks on a manual shutter -> `blurUnavailable`, NO PUT issued for that pose, scan stays local; blur exception -> same; never uploads the unblurred bytes |
| PRIV-04 | Re-encode strips metadata, size cap | U | T54 blur_service_test | input JPEG with EXIF GPS + ICC -> output has no APP1 Exif or GPS bytes; output <= 3 MiB (3145728 B) else refused; JPEG quality 85 re-encode |
| PRIV-05 | Cloud consent only when the provider needs photos; versioned | W | T61 cloud_consent_sheet_test | provisional provider -> sheet never shown; `requiresPhotos` -> shown before first upload only; text lists what is sent, retention default, one-tap delete, no analytics; accept writes `{version, acceptedAt}`; decline keeps capture local; version bump re-prompts |
| PRIV-06 | Server consent gate | J | T74 body_scan_create.test | `requiresPhotos` with missing or older consent -> `consent-required`, no URLs minted, no doc moved to `awaiting_upload` |
| PRIV-07 | Provisional provider uploads no photo | J, U | T74 body_scan_create.test, T56 upload_flow_test | provisional create returns no `uploads`; client skips the upload stage and makes zero PUT calls |
| PRIV-08 | Retention default 0 and options | W, J | T67 retention_settings_view_test, T75 body_scan_estimate.test | UI offers exactly 0/30/90/365 with default 0 selected; estimate with retention 0 deletes inline, 365 sets expiry now+365 d; purge (SCAN-36) covers the rest |
| PRIV-09 | Privacy and retention view actions | W | T67 retention_settings_view_test | delete all cloud photos, delete all scans (confirm first), cloud analysis switch, link to data sources; each action calls the right port once |
| PRIV-10 | Account deletion removes Storage prefix and retries on failure | J | T112 delete_account.test, T113 account_deletion_reconcile.test | `deleteFiles({prefix: "users/<uid>/", force: true})` called with that exact prefix; unconfigured bucket -> logged no-op; configured + failure -> throws so `accountDeletionRetries` retries; idempotent; no other uid prefix touched |
| PRIV-11 | Account deletion covers new Firestore data and local data | Y, U | T115 account_deletion.e2e.test, T116 local_data_wipe_test | e2e seeds all 7 new collections for the uid and another uid; after delete none remain for the uid, other uid intact; local wipe removes `scans/*.scan`, `meals/*.jpg.enc` and every new SharedPreferences key |
| PRIV-12 | Export includes every new collection and capped signed links | J | T114 account_export.test | export contains body_scans, body_scan_settings, weight_entries, nutrition_plan, nutrition_plan_reviews, food_entries, saved_foods; each bounded by `MAX_ROWS + 1` (truncation flag when exceeded); stored photos give 24 h signed read URLs, 61 stored objects -> exactly 60 links and a truncation note; no photo bytes embedded; `nutrition_cache` absent |
| PRIV-13 | Profile export carries `nutrition`; device merge | U | T117 data_export_test, T118 server_export_merge_test | `UserProfile.toJson` includes `nutrition` map; server merge keeps new collections; legacy export without them still parses |
| PRIV-14 | Account deletion in progress aborts in-flight writes | U | T55 body_scan_job_runner_test, T81 plan_repository_test | with the deletion fence set no Firestore/callable write happens from the runner, plan repository or diary writer |
| PRIV-15 | Logs carry no uid, body metrics, meal text or images | J | T75 body_scan_estimate.test, T110 analyze_meal_photo.test | spy on logger: event has only operation, outcome, latencyMs, provider id/version; serialised log contains none of the fixture uid, weight, height, meal text, note |
| PRIV-16 | New health answers are device-only | U, R | T31 health_flags_json_test, T33 health_rules_parity_test, T34 f014_persistence_merge_test, T03 firestore_rules.test | `stripSensitive` blanks `nutritionGuidance` and `foodAllergens`; rules key allowlist (`flagsAreStripped`) equals the keys `HealthFlags.toJson` emits (T33 fails if a field is added to one side only, the F014 failure class); local persistence merge keeps both new answers across a profile save (T34); rules refuse them on the server (RULES-08); field coverage lists both keys (T32) |
| PRIV-17 | No analytics SDK, no Storage SDK, HealthService seam intact, no photo-bearing logging | U | T73 body_scan_static_guard_test | `pubspec.yaml` has no `firebase_storage`, analytics or crash package newly added; no new feature file imports the Health plugin directly (only `HealthService`); no `print`/`debugPrint` of scan or diary models |
| PRIV-18 | Legacy v1 local scans never auto-uploaded | U | T55 body_scan_job_runner_test | covered by SCAN-10; additionally explicit user "analyse this scan" is the only path and requires consent |
| PRIV-19 | Meal and label photos never stored server-side | J | T110 analyze_meal_photo.test, T111 parse_nutrition_label.test | storage mock records zero writes; image passed inline only; local thumbnail deleted with its entry (T103) |
| PRIV-20 | Privacy page text matches behaviour | U | T119 privacy_copy_test | `public/privacy.html` mentions on-device blur, default retention "deleted after analysis", one-tap deletion, meal photos not stored; no longer claims "photos never leave the device" unconditionally |
| PRIV-21 | Lifecycle governance rows | R | T05 data_access_policy.test | every new collection has a policy row whose `clientAccess` matches the rules outcome (read/write/create/update/delete per path); `nutrition_cache` EXEMPT; a collection missing from the policy fails the test |

### 4.3 PLAN - nutrition maths, plan, review, ownership

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| PLAN-01 | Mifflin-St Jeor with sex constant | U | T12 energy_math_test | V-BMR-M 1780.0, V-BMR-F 1320.25, V-BMR-U 1697.0; sex basis falls back: `sexAtBirth` first, then gender male/female, else unspecified (non-binary/prefer-not -> -78) |
| PLAN-02 | Activity factors and steps cross-check use the LOWER factor | U | T12 energy_math_test | 1.2 / 1.375 / 1.55 / 1.725 (1.9 never produced); steps 4999 -> 1.2, 5000 -> 1.375, 7499 -> 1.375, 7500 -> 1.55, 9999 -> 1.55, 10000 -> 1.725; questionnaire `active` + steps 4000 -> 1.2; questionnaire sedentary + steps 12000 -> 1.2 |
| PLAN-03 | TDEE and no exercise credit | U | T12 energy_math_test, T14 plan_calculator_test | TDEE = BMR*f exactly; adding logged workout calories to input does not change the range (D-29) |
| PLAN-04 | Weekly pace rows and absolute caps | U | T14 plan_calculator_test | BMI 24.99 -> 0.50 %/wk; 25.00 -> 0.75; 29.99 -> 0.75; 30.00 -> 1.00; gain 0.25 default; maintain 0; absolute kg caps 0.5 / 1.0 / 1.0 / 0.5 applied (e.g. 120 kg, BMI >= 30: 1.0 %/wk = 1.2 kg is clamped to 1.0 kg); 7700 kcal/kg |
| PLAN-05 | Goal energy and range construction | U | T14 plan_calculator_test | V-LOSE-M target 2007.5, range 1860-2160; V-LOSE-CAP range 1690-1990; gain: surplus clamp [100, min(500, 0.15*TDEE)] and `low >= TDEE`; maintain target = TDEE; lose `high <= TDEE`; values rounded to 10; |
| PLAN-06 | Slider bounds and re-validation | U | T14 plan_calculator_test | lose `[max(floor, TDEE - maxDeficit), TDEE]`, maintain +-300, gain `[TDEE, TDEE + min(500, 0.15 TDEE)]`; interval never empty for sampled grid (weights 40-200 kg, heights 140-210, ages 18-80, all 3 sex bases, 4 activity levels); width clamped to [100, 400]; stored range outside bounds is pulled inside on load and before write |
| PLAN-07 | Protein targets | U | T14 plan_calculator_test | V-PROT-80 128/160/176; maintain 1.4/1.6, gain 1.6/1.8; V-PROT-OB shows Wref 86.7 and max 180; V-PROT-220 caps at 220; the "protein minimum" shown is the minimum |
| PLAN-08 | Fat and carbohydrate ranges | U | T14 plan_calculator_test | V-FAT 48/70; fat never below 20 % or above 35 % of kcalMid; carbMin never below 100 g; if remainder < 100 g fat moves toward `fatMin`, then protein toward min, plan flagged `lowCarbBySafety`; carbMin <= carbMax always |
| PLAN-09 | Steps goal | U | T14 plan_calculator_test | V-STEPS 7000 / 11000 / 12000 / 6000; roundTo500; Health Connect 14-day median used when connected, else self-report bucket midpoint (2500 / 4000 / 6500 / 9500 / 12500) |
| PLAN-10 | Inputs resolution | U | T19 nutrition_inputs_test | latest weight entry within 14 days wins, 15 days -> profile weight and `weightStale`; BMI computed from resolved weight; any required input missing -> `needsProfile` listing exactly the missing names |
| PLAN-11 | Realistic-pace message | U | T14 plan_calculator_test | target weight with BMI < 18.5 -> `targetBelowHealthyRange` and no pace; otherwise weeks = ceil(delta / (rate*W)); gain/maintain wording differs |
| PLAN-12 | Weekly review decision | U | T16 weekly_review_test | < 3 points or span < 7 d -> `needMoreData` (3 points over 6 days still needs more); V-REVIEW deadband boundaries; single `behind` -> keep; two consecutive `behind` AND cooldown >= 14 d (13 d -> keep, 14 d -> act); order: steps +1000 first (if auto steps on, ownership allows, goal+1000 <= 12000) then kcal -150 (lose) / +150 (gain); `tooFast` acts immediately without waiting; `|drift + delta| > 400` (401) -> `needRecalculation`, 400 allowed; `recomposition` keeps plan when weight flat and body fat meaningfully down; reasonCodes closed and non-empty on every outcome |
| PLAN-13 | One decision path for post-scan plan decision | U | T16 weekly_review_test, T64 result_view_test | result screen calls the same `decide` with the body-fat trend input; identical inputs give identical decisions; ineligible -> no decision text |
| PLAN-14 | Ownership matrix | U | T16 weekly_review_test | coached: applied + undo for 7 days; shared: proposal only, applied on accept; manual: insight only, plan unchanged; `autoAdjust` toggles forced off for manual; slider edit under coached switches ownership to shared |
| PLAN-15 | Weekly cadence idempotence | U | T82 review_scheduler_test | one review per ISO week keyed `yyyy-Www`; second open same week does nothing; 2026-12-31 and 2027-01-01 are both `2026-W53`; 2027-01-04 is `2027-W01`; scan reaching `done` triggers an immediate review once |
| PLAN-16 | Plan persistence and recompute | U | T81 plan_repository_test | round trip of every field; absent doc -> `needsProfile`/defaults; forged stored range (low 900) is re-clamped on read and never displayed; review docs immutable (update path absent); last 12 reviews listed |
| PLAN-17 | Plan screen | W | T86 nutrition_plan_page_test | range slider, macro cards, steps, ownership selector, explainer link, review card all render for eligible user; `needsProfile` shows the button to `/nutrition/profile`; "how your plan adapts" page reachable |
| PLAN-18 | kcal range slider behaviour | W | T84 kcal_range_slider_test | thumbs cannot be dragged below the lower bound or above the upper bound (drag far beyond -> value equals bound); step 10; width stays within 100-400; bounds shown as text |
| PLAN-19 | Providers | U | T83 nutrition_providers_test | eligibility provider recomputes on flag change; plan provider returns `referProfessional` with NO numbers for excluded profile; cards hidden for excluded |
| PLAN-20 | Pure data layers import no Flutter | U | T37 pure_data_layer_guard_test | scan all `lib/features/{body_scan,nutrition_plan,food_diary,activity}/data/**/*.dart` for `package:flutter/` imports -> none; also no hard-coded `Color(0x` literals in the new `widgets/` directories (A11Y-11) |
| PLAN-21 | Journey: existing user completes nutrition profile and sees plan | Y | T89 nutrition_journey_test | profile with `completedAt` set is not redirected to onboarding; Home card says profile needed; flow sheets 1-3 save through the repository keeping `completedAt`; plan then shows numbers within bounds; second journey with `nutritionGuidance = reported` shows only the notice |

### 4.4 SAFE - exclusions and clamps (every refusal and boundary)

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| SAFE-01 | Under-18 and unknown age | U | T15 nutrition_eligibility_test | clock years 2026-01-01, 2026-06-15, 2026-12-31 x birthYear 2007 -> eligible (age 18), 2008 -> `referProfessional(underAge)` (17), 2009 and 2020 -> underAge; birthYear null and no stored age -> `needsProfile(birthYear)`; legacy stored whole-number age 17 -> underAge, 18 -> pass; scan gate boundary agrees (`scanAllowedForAge(17)` false, 18 true) |
| SAFE-02 | Pregnancy / breastfeeding flag | U | T15 nutrition_eligibility_test | `professionalGuidance == reported` -> `referProfessional(guidance)`; also with every other field valid |
| SAFE-03 | Eating-disorder history / supervised nutrition flag | U | T15 nutrition_eligibility_test | `nutritionGuidance == reported` -> `referProfessional(guidance)` even when pregnancy answer is `none` and age is 40 |
| SAFE-04 | Clinician advice and surgery | U | T15 nutrition_eligibility_test | `clinicianAdvice == advisedAgainstExercise` -> `referProfessional(clinician)`; `surgery == underRestrictions` -> same; other surgery values do not refuse |
| SAFE-05 | Unanswered safety questions lock the coach | U | T15 nutrition_eligibility_test | `nutritionGuidance == null` -> `needsAnswer(nutritionGuidance)`; `professionalGuidance == null` -> `needsAnswer(professionalGuidance)`; unanswered is never treated as clear; no numbers produced |
| SAFE-06 | Evaluation order, first match wins | U | T15 nutrition_eligibility_test | profile that is 17 AND reported guidance -> underAge (row 2 before 3); reported guidance AND unanswered nutrition question -> guidance (rows 3-5 before 6); each of the 9 rows has one dedicated fixture proving its position |
| SAFE-07 | Neutral behaviour: no numbers anywhere, reason never stated or stored | W | T85 professional_notice_test, T83 nutrition_providers_test | text is the fixed neutral sentence in EN and RU, contains none of the words pregnancy, eating, disorder, age; plan screen, kcal ring, macro bars, steps goal, diary totals, Home card and the scan result's plan decision render NO digits from the plan; stored value is the generic flag only |
| SAFE-08 | Calorie floor boundaries | U | T13 safety_clamps_test, T14 plan_calculator_test | V-FLOOR-F floor 1200 and range low >= 1200 (never 1050); V-FLOOR-M floor 2068; unspecified uses 1500 absolute; floor = max(abs, round(BMR)) at BMR 1499 / 1500 / 1501 for male; stored low 1199 re-clamped to the floor |
| SAFE-09 | Maximum weekly loss rate | U | T13 safety_clamps_test | requested rate 1.5 %/wk is clamped to the BMI-row maximum (0.75 / 1.0 / 1.0); absolute 0.5 kg/wk for BMI < 25 even if 0.75 % would give more (e.g. 100 kg at 205 cm); slider at its low end never implies a deficit above `min(25 % TDEE, maxRate*7700/7)` |
| SAFE-10 | Deficit and surplus caps | U | T13 safety_clamps_test | V-LOSE-CAP deficit exactly 611.9 (25 % TDEE); TDEE - floor binding case V-FLOOR-F deficit 129.3; surplus <= 500 and <= 15 % TDEE (TDEE 2000 -> 300; TDEE 4000 -> 500) and >= 100 |
| SAFE-11 | Underweight guard | U | T13 safety_clamps_test | BMI 17.9 + goal lose -> coerced to maintain with `underweightNoDeficit`; 18.5 -> deficit allowed only at <= 0.25 %/wk while BMI < 20 (19.9 capped, 20.0 normal row); BMI 18.49 refused vs 18.50 allowed; target weight with BMI < 18.5 rejected |
| SAFE-12 | Protein range clamps | U | T13 safety_clamps_test | min 1.4 / 1.6 g/kg, max 2.2 g/kg of Wref, hard 220 g, 40 % kcal; V-PROT-OB 180; a hand-edited target below min or above max is clamped; high-protein advisory line present with protein card (W check in T86) |
| SAFE-13 | Fat/carb/steps/range-width clamps | U | T13 safety_clamps_test | fat 20-35 %, >= 0.6 g/kg; carb >= 100 g; steps computed 6000-12000, user-set 2000-30000 accepted, 1999 and 30001 refused; range width 99 -> 100, 401 -> 400 |
| SAFE-14 | Clamp constants table | U | T13 safety_clamps_test | one assertion per constant in design section 13.6 (so an accidental edit of any constant fails): ages 18, floors 1200/1500, 25 %, 15 %, 500, 7700, 0.5/0.75/1.0, protein factors, 220, 40 %, fat 20/35/0.6, carb 100, steps 6000/12000, review step 150, cooldown 14 d, drift 400, width 100/400 |
| SAFE-15 | Review never leaves safe bounds | U | T16 weekly_review_test | at lower bound: behind-twice -> `keep(atSafetyLimit)` with explanation code, never a value below bound; `clampToBounds` last; steps never above 12000 and never reduced automatically; kcal step is exactly 150 |
| SAFE-16 | Manual ownership cannot exceed bounds | W | T84 kcal_range_slider_test, T86 nutrition_plan_page_test | manual user drags past bound -> clamped; saved doc re-validated; rules backstop (RULES-04) refuses < 1200 |
| SAFE-17 | Tiny and extreme profiles | U | T14 plan_calculator_test | 40 kg / 140 cm woman, 200 kg / 190 cm man, age 18 and 100 produce a non-empty interval, floor-respecting range and no NaN/Infinity; rounding to 10 kcal and 1 g stable |
| SAFE-18 | Safety clamps bind estimator output used in plan | J | T79 validate_estimate.test | nonsense estimate never reaches `done` (SCAN-34), so a plan decision cannot be built from it |

### 4.5 ONB - onboarding and nutrition profile

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| ONB-01 | New `OnboardingStep.nutrition` in order | U | T39 onboarding_order_test | `kOnboardingOrder` contains `nutrition` exactly once, after `lifestyle` and before `healthFlags`; every enum value appears in the order; the exhaustive switch compiles with all cases (test iterates `OnboardingStep.values`) |
| ONB-02 | Answered rule and resume index | U | T38 step_nutrition_answered_test, T40 step_answered_test | step is unanswered for an empty `NutritionPrefs` and no allergens; answered when any one field set (each field tested alone) or allergens non-empty; `onboardingResumeIndex` lands on the nutrition step when everything before it is answered; existing steps' results unchanged |
| ONB-03 | Reuse of existing answers | U | T41 questionnaire_notifier_test | `weightLoss` goal -> goalDirection default lose, `muscleGain` -> gain, otherwise maintain; sex-at-birth default from gender male/female, none for others; height/weight/birth year are not re-asked (nutrition step reads them); `updateNutrition` keeps other draft fields |
| ONB-04 | `NutritionPrefs` model, migration-safe | U | T30 nutrition_prefs_json_test | profile JSON without `nutrition` parses to empty prefs; unknown enum names -> null; round trip equal; `excludedFoods` capped at 20 items of <= 40 chars (21st and 41st char dropped or refused consistently); mealsPerDay outside 2..6 refused; `UserProfile.toJson` includes `nutrition`; existing profile fixtures from `profile_models_test` still round trip |
| ONB-05 | HealthFlags new fields | U | T31 health_flags_json_test, T32 health_flags_field_coverage_test | JSON with and without `nutritionGuidance`/`foodAllergens`; unknown allergen names dropped; `isUnanswered` unaffected by allergens, `isEmpty` affected; `==`/`hashCode`/`copyWith` include both; coverage test fails if a field is added without being listed |
| ONB-06 | Step widget: skippable, defaults, chips | W | T42 step_nutrition_test | with nothing touched the primary button reads Skip and advancing is allowed; touching a field flips it to Next; steps buckets map to 2500/4000/6500/9500/12500; allergen chips (14 EU allergens) toggle; excluded foods 21st chip refused; ownership default Coached; realistic-pace message appears with target weight and obeys PLAN-11; Health Connect card is optional and offers manual tracking |
| ONB-07 | Health-flags step and lifestyle step additions | W | T43 step_health_test, T44 step_lifestyle_test | nutritionGuidance single choice (none / reported) with no "prefer not to say"; guidance question wording names breastfeeding (EN and RU); `pescatarian` chip exists and is saved in `Lifestyle.diet` |
| ONB-08 | Existing completed users never forced | U | T46 app_router_gating_test | profile with `completedAt != null` and empty `nutrition` is not redirected to `/onboarding` from any new route; incomplete profile still is |
| ONB-09 | "Complete your nutrition profile" flow | W | T45 nutrition_profile_flow_test | `missingNutritionInputs` decides sheets: nothing missing -> flow skips to plan; only safety questions missing -> only sheet 1; saving keeps `completedAt` and unrelated fields; cancel writes nothing |
| ONB-10 | `missingNutritionInputs` pure function | U | T17 missing_inputs_test | each of height, weight, birth year, sex basis, activity, goal, safety questions reported individually and in combination; complete profile returns empty |
| ONB-11 | Routes reachable | U | T47 reachability_test | every new route in the design table is reachable from a UI entry point and resolves to its page; `/body-scan?scanId=` resumes |
| ONB-12 | Step answers analytics-light | U | T73 body_scan_static_guard_test | no analytics dependency added (PRIV-17); step state is touched/untouched only |

### 4.6 FOOD - food scanning, diary, nutrition data

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| FOOD-01 | `coerceMealAnalysis` parsing and numeric hygiene | J | T104 coerce_meal_analysis.test | non-JSON, truncated JSON, JSON array, empty string -> empty items (no throw); NaN, Infinity, negative, string numbers dropped or item discarded; unknown fields ignored |
| FOOD-02 | Portion clamps | J | T104 coerce_meal_analysis.test | grams clamped to 1..3000 (0 -> 1, 5000 -> 3000); `low <= mid <= high` enforced by reordering; high/low = 4.0 no flag, 4.1 -> `portionUnclear` |
| FOOD-03 | Per-100 g clamps | J | T104 coerce_meal_analysis.test | kcal 900 ok, 901 clamped/flagged; any macro > 100 flagged; protein+carbs+fat 105.0 ok, 105.1 rejected; confidence clamped to 0..1 |
| FOOD-04 | kcal vs 4P+4C+9F sanity flag | J | T104 coerce_meal_analysis.test, T105 nutrition_normalise.test | V-ATWATER: 125 vs kcal 100 accepted, 126 -> `dataInconsistent`; 75 accepted, 74 flagged; flagged item still returned but not marked high confidence |
| FOOD-05 | Closed codes only | J | T104 coerce_meal_analysis.test | unknown `uncertainties`/`assumptions` strings dropped; known codes from the 11-code list kept; free text never passed through; long strings truncated; control characters removed |
| FOOD-06 | Totals recomputed server-side | J | T104 coerce_meal_analysis.test | model returns wrong item and meal totals -> output totals equal `per100g x grams / 100` summed; > 12 items cut to 12; items with no food -> empty list |
| FOOD-07 | `analyzeMealPhoto` request validation and abuse controls | J | T110 analyze_meal_photo.test | mode must be photo/describe; describe text 2 chars refused, 3 accepted, 200 accepted, 201 refused; note 201 chars refused; quotes, backticks and control characters in text/note refused; oversize image, wrong mime, bad base64 and bad signature refused; anonymous refused; kill switch off -> `feature-disabled`; parse happens before quota; quota 61st refused; provider failure refunds quota |
| FOOD-08 | Gateway call options | J | T110 analyze_meal_photo.test, T09 ai_gateway.test | operation `analyzeMealPhoto` is in `AI_GATEWAY_OPERATIONS`; call uses `jsonResponse`, `responseSchema`, temperature 0, `maxOutputTokens 1200`, timeout 25000; `responseSchema` is passed to `config.responseSchema`; prompt contains the note only as quoted data and states the note is authoritative |
| FOOD-09 | Enrichment chain, source tags, match quality, confidences | J | T110 analyze_meal_photo.test | whole food -> USDA first, packaged -> OFF, else `llm_estimate` with `matchQuality none` and `lowConfidenceItem`; every item carries `source` from {usda_fdc, open_food_facts, llm_estimate, user}; item confidence = model confidence x {1.0, 0.8, 0.5, 0.35}; entry confidence high only if all items >= 0.75 and no unresolved code, medium if all >= 0.5, else low; upstream failure degrades to the next source, never throws |
| FOOD-10 | `nutrition_normalise`: kJ, salt/sodium, sanity | J | T105 nutrition_normalise.test | uses `_100g` fields only; kcal absent -> kJ/4.184 (2252 kJ -> 538.2); kcal present wins (539); sodium 0.4 g -> salt 1.0 g (x2.5); missing energy and macros -> unusable; per-serving values never mistaken for per-100 g |
| FOOD-11 | OFF v3 fixture contract | J | T108 lookup_barcode.test | V-OFF product parsed with serving_size absent; fixed host/path/fields template exactly as designed; `User-Agent` header present; `dataQuality` complete/partial/inconsistent classification; attribution block returned |
| FOOD-12 | GTIN check digit | U, J | T93 gtin_validator_test, T107 gtin_validator.test | V-GTIN five valid codes pass; each with last digit changed fails; lengths 7, 9, 10, 11, 15 and non-digits fail; lengths 8/12/13/14 accepted; whitespace/leading zeros handling fixed (decided in test, same in Dart and TS) |
| FOOD-13 | `lookupBarcode` cache, fallback, breaker | J | T108 lookup_barcode.test | cache hit -> no network; miss -> OFF -> USDA `gtinUpc` -> `found:false`; positive TTL 30 d, negative 1 d (`expireAt`); breaker opens after 3 consecutive failures or one 429, answers `upstream-unavailable` from cache only for 5 minutes (injected clock: 4:59 open, 5:01 closed); invalid check digit rejected before any fetch; quota 121st refused; flag off -> `feature-disabled` |
| FOOD-14 | `searchFoods` | J | T109 search_foods.test | query 2 chars refused, 3 accepted, 60 accepted, 61 refused; limit > 20 clamped; cache key `q_<sha1(lang|query|scope)>` 7 d; USDA key read from the secret and never `DEMO_KEY` (fixture with missing secret -> `failed-precondition`); Search-a-licious down -> legacy endpoint; USDA without energy nutrient -> Atwater derived with `derivedEnergy`; dedupe and cap; quota 151st refused |
| FOOD-15 | Label parsing and normalisation | J | T106 label_normalise.test, T111 parse_nutrition_label.test | decimal comma "12,5" -> 12.5; kJ only -> kcal; per-serving + serving grams -> per 100 g (x100/servingG); `unreadableFields` -> `labelAmbiguous`; EN and RU label fixtures (Cyrillic units "ккал", "белки", "жиры", "углеводы"); sanity as FOOD-04; label photo never stored (PRIV-19) |
| FOOD-16 | Client label scaling | U | T94 label_scale_test | per-serving <-> per-100 g exact inverse; serving 0 or missing -> `scaleMissing`, no division by zero |
| FOOD-17 | Portion maths | U | T90 portion_math_test | grams range x per-100 g gives macro Range (low, mid, high) with low <= mid <= high; zero grams -> zero; edited grams recompute only that item |
| FOOD-18 | Day totals as ranges | U | T91 day_totals_test | mid = sum of mids; spreads combined by root-sum-square (two items each 100 below mid -> 141.4 not 200); status below/within/above uses mid against the plan range at its exact bounds; protein-minimum reached flag at exactly the minimum; remaining measured against the top of the range |
| FOOD-19 | Per-meal targets | U | T91 day_totals_test | 3 meals -> 30/35/35 %; 4+ meals spread the remainder evenly; shares sum to 100 % |
| FOOD-20 | Check-these resolution | U, W | T92 check_these_test, T99 check_these_chips_test | each of 11 codes has a concrete resolution; `hiddenIngredients` options none / 5 g / 14 g oil change the totals by exactly grams x the generic oil kcal per 100 g (5 g and 14 g; expected values computed from the fixture row, not hard-coded); resolving marks `resolved: true`; max 8 chips; chips are buttons with labels |
| FOOD-21 | Food suggestions respect diet, allergens, exclusions | U | T97 food_suggestions_test | vegan hides animal products, pescatarian allows fish only; allergen set removes tagged foods; excluded-food strings match case-insensitively; uncertain tags default to restrictive (hidden); at most 5 results; no "good/bad" field |
| FOOD-22 | Bundled generic table and search | U | T95 generic_foods_test | asset parses; every row has id `gen:<fdcId>`, sane per-100 g (kcal <= 900, macros <= 100); ranking exact token > prefix > substring; RU name fallback to English; empty/1-char query -> no results |
| FOOD-23 | Food entry model limits | U | T96 food_entry_test | round trip; 31 items refused, 30 accepted; > 8 check items refused; slot/source/confidence enums tolerant to unknown (degrade) on read but refused on write; quick-log stored as one `quick` item with 100 g pseudo-portion |
| FOOD-24 | Client API wrapper and offline fallback | U | T98 food_api_test | callable errors map to l10n slugs; `feature-disabled` not retried; offline -> add-food offers search and manual, queues nothing silently; no meal text in any logged string |
| FOOD-25 | Add-food UI invariants | W | T100 food_diary_page_test, T101 food_detail_sheet_test | nothing logged until Save; slot default by local time (08:00 breakfast, 13:00 lunch, 19:00 dinner, 16:00 snack as fixed in test); confidence and "likely range" shown; check-these chips visible; `referProfessional` hides the diary numbers |
| FOOD-26 | Barcode client | W | T102 barcode_flow_test | port emits EAN-13 -> check digit verified, callable invoked once (duplicate scans debounced); invalid digit -> inline error and no call; not found -> offers label scan or manual entry; "save this product" writes `saved_foods` only after confirmation |
| FOOD-27 | Food journey | Y | T103 food_diary_journey_test | search -> detail -> save appears in diary and totals; meal photo (fake API) -> chips resolved -> saved; delete entry removes local thumbnail; plan excluded user cannot reach numbers |
| FOOD-28 | Quota and operation registry | J | T08 abuse_guard.test, T09 ai_gateway.test, T10 ai_gateway_definitions.test | QUOTAS contain analyzeMealPhoto 60, parseNutritionLabel 60, barcodeLookup 120, foodSearch 150, bodyScanCreate 30, bodyScanEstimate 14, bodyScanDelete 60; `AI_GATEWAY_OPERATIONS` gains exactly the two AI operations and monitoring definitions derived from the tuple include them |
| FOOD-29 | Attribution and data-sources page content | W | T86 nutrition_plan_page_test | sources page lists USDA FoodData Central, Open Food Facts (ODbL), Mifflin-St Jeor and Deurenberg citations; ships from the attribution list |

### 4.7 ACT - sport-agnostic activity model and merge (foundation)

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| ACT-01 | Tolerant model JSON | U | T28 activity_models_test | round trip equal; unknown sport string -> `other`; unknown extra fields ignored; schema field kept; missing optional summary fields null |
| ACT-02 | Stream validity | U | T28 activity_models_test | non-increasing or duplicate `offsetsMs` rejected; values/offsets length mismatch rejected; GPS parallel lists equal length |
| ACT-03 | Canonical units, derived pace | U | T28 activity_models_test | stored in SI (m, m/s, W, bpm); no pace field stored; no km/mile conversion in the data layer |
| ACT-04 | Stable session id | U | T28 activity_models_test | `act_<sha1>` is identical across runs for the same source key and differs when `externalId` differs |
| ACT-05 | Exact duplicate | U | T29 activity_merger_test | same `sourceId` + `externalId` imported twice -> one session |
| ACT-06 | Same workout from watch + phone + platform echo | U | T29 activity_merger_test | three candidates -> one session with provenance of three; echo (platform record naming a held source) ranked below the direct source |
| ACT-07 | Merge thresholds at the boundary | U | T29 activity_merger_test | IoU 0.80 merged, 0.79 not (unless start/end rule); start diff 120 s and end diff 300 s merged, 121 s / 301 s not; distance relative difference 15 % merged, 16 % not; GPS mean distance 100 m merged, 101 m not |
| ACT-08 | Not merged | U | T29 activity_merger_test | brick session (run then ride, overlap below threshold) stays two; pool swim vs open-water swim never merged; running vs cycling never merged; same-source back-to-back with gap <= 60 s joined only when `joinSplits` is on (default off) |
| ACT-09 | Field policy and complementary merge | U | T29 activity_merger_test | HR from strap + GPS from phone with 3 s clock skew aligned (skew > 5 s not aligned); stream used only if coverage >= 80 % (79 % falls to next source); samples never mixed within one kind; summary recomputed from merged streams; disagreement > 10 % recorded in `mergeNotes` |
| ACT-10 | User edits win | U | T29 activity_merger_test | an edited field survives a re-merge with higher-priority source data |
| ACT-11 | Order independence | U | T29 activity_merger_test | 20 seeded shuffles of the same inputs produce an identical result (deep equality) |
| ACT-12 | UTC handling | U | T29 activity_merger_test | sessions across a DST change with different `utcOffsetMinutes` still match when UTC times match; display offset preserved |
| ACT-13 | `DeviceSource` contract and fake | U | T29 activity_merger_test | `FakeDeviceSource` honours permission/request/fetch/disconnect(deleteImported) semantics; capability matrix constants unchanged; no UI, no persistence, no Flutter import (T37) |

### 4.8 PROG - nutrition-aware programme level

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| PROG-01 | Neutral on missing or ineligible data | U | T18 nutrition_training_state_test | not eligible, unknown `kcalMid`, unknown phase -> `neutral == true`, volumeFactor 1.0, delta 0, no deload; never acts on missing data |
| PROG-02 | Deficit depth | U | T18 nutrition_training_state_test | V-TRAIN 0.0999 -> 1.0, 0.10 -> 0.95, 0.1999 -> 0.95, 0.20 -> 0.85; deficit alone never lowers intensity |
| PROG-03 | Surplus boost conditions | U | T18 nutrition_training_state_test | 1.05 only when sleep >= 7.0 AND adherence >= 0.70: (6.99, 0.7) -> 1.0, (7.0, 0.69) -> 1.0, (7.0, 0.7) -> 1.05 |
| PROG-04 | Protein adherence | U | T18 nutrition_training_state_test | fewer than 4 logged days in 14 -> adherence null and no reason; < 0.5 in deficit -> `proteinLow` + deload `consider`, volume unchanged by itself; 0.5 -> none |
| PROG-05 | Sleep | U | T18 nutrition_training_state_test | 6.0 h -> no change; 5.99 -> `intensityCapDelta -0.05` and `sleepLow` |
| PROG-06 | Fast loss | U | T18 nutrition_training_state_test | rate exactly -1.25 x max not triggered, beyond it -> volume min(current, 0.90), deload consider, `lossTooFast` |
| PROG-07 | Low intake, high load | U | T18 nutrition_training_state_test | kcalMid = floor x 1.05 with 5 sessions -> deload `recommended` + `lowIntakeHighLoad`; 4 sessions or floor x 1.06 -> not; no energy-availability or RED-S wording in any reason code |
| PROG-08 | Recovery signal preserved | U | T18 nutrition_training_state_test | `recoveryDeloadSignal` true -> `recommended` regardless of nutrition |
| PROG-09 | Clamps and no stacking | U | T18 nutrition_training_state_test | volumeFactor always in [0.70, 1.05]; delta in [-0.10, 0]; all rules triggered at once stay inside |
| PROG-10 | Nutrition can only lower load | U | T35 nutrition_advice_combination_test | combined cap = the MORE conservative of `AgeBand.intensityCap`, screening ceiling and nutrition delta; nutrition never raises a cap set by safety; injury filter output unchanged for the same inputs |
| PROG-11 | Builder hook neutral by default | U | T36 programme_builder_test | existing expectations pass unchanged with no nutrition parameter; with neutral advice output is identical to no parameter; non-neutral lowers sets by the factor (rounding rule fixed in test); if the seam is not wired (SD-7) this row is reported NOT_WIRED and only the provider/function rows apply |

### 4.9 RULES - Firestore and Storage rules, indexes, callable wiring

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| RULES-01 | `body_scans` read | R | T03 firestore_rules.test | owner reads own; other uid refused; unauthenticated refused; canary identity refused |
| RULES-02 | `body_scans` write surface | R | T03 firestore_rules.test | owner create refused; owner delete refused; owner update of `weightKg` (30, 300 ok; 29.9, 300.1 refused) and `clientNote` (200 chars ok, 201 refused) allowed; update of each of `estimate`, `status`, `provider`, `photosState`, `photosExpireAt`, `isBaseline`, `takenAt` refused separately; a write mixing allowed and forbidden key refused |
| RULES-03 | `weight_entries` | R | T03 firestore_rules.test | valid doc ok; day id `2026-1-5` refused; kg 10 and 400 refused (29.9/30/300/300.1 boundaries); unknown key refused; source `x` refused; other user refused |
| RULES-04 | `nutrition_plan` | R | T03 firestore_rules.test | valid ok; `kcalRange.low` 1199 refused, 1200 ok; `high` 6001 refused; `high < low` refused; stepsGoal 1999/30001 refused, 2000/30000 ok; docId other than `main` refused; unknown key refused; enum violations refused; other user refused |
| RULES-05 | `nutrition_plan_reviews` | R | T03 firestore_rules.test | create ok; update refused (immutable); delete ok; week id `2026-W5` refused; `reasonCodes` size 9 refused, 8 ok; decision outside enum refused |
| RULES-06 | `food_entries` | R | T03 firestore_rules.test | valid ok; 31 items refused, 30 ok, 0 refused; unknown slot/source refused; unknown key refused; name 81 chars refused; `checkThese` 9 refused; `totals` missing a key refused |
| RULES-07 | `body_scan_settings` | R | T03 firestore_rules.test | `retentionDays` 7 refused, 0/30/90/365 ok; reminder weekday 0 and 8 refused, minutes 1440 refused; `cloudConsent.acceptedAt` not equal to `request.time` refused; docId other than `main` refused; unknown key refused |
| RULES-08 | Profile writes: device-only flags and `nutrition` map | R | T03 firestore_rules.test | `health.flags.nutritionGuidance = "reported"` refused; `foodAllergens: ["peanuts"]` refused; both empty accepted; `nutrition` with unknown key refused; valid `nutrition` accepted; legacy profile WITHOUT new keys still accepted (old client rollout) |
| RULES-09 | Wildcard carve-out proof | R | T03 firestore_rules.test | a write to `users/{uid}/body_scans/x` that satisfies the generic wildcard shape is refused (proves the exclusion list and that the explicit block is not dead); same probe for each of the 7 new collections |
| RULES-10 | `saved_foods` | R | T03 firestore_rules.test | valid ok; name 81 refused; per100g value 1001 and -1 refused; unknown key refused; other user refused |
| RULES-11 | `nutrition_cache` server only | R | T03 firestore_rules.test | owner, other user, anonymous: read and write all refused |
| RULES-12 | Storage deny-all | S | T04 storage_rules.test | authenticated owner and anonymous: read and write on `users/<uid>/scans/<id>/front.jpg`, on a random path and on the root all refused |
| RULES-13 | Canary identity gets nothing on new paths | R | T03 firestore_rules.test | canary token refused on read and write for every new collection |
| RULES-14 | Data-access policy parity | R | T05 data_access_policy.test | rows for all 8 new paths exist and each CONDITIONAL cell names the emulator test; rules outcome for each cell equals the policy |
| RULES-15 | Indexes and TTL | J | T11 firestore_indexes_body_scan.test | `firestore.indexes.json` contains the two COLLECTION_GROUP composite indexes (`photosState ASC, photosExpireAt ASC`; `status ASC, pendingExpiresAt ASC`) and the `nutrition_cache.expireAt` TTL override; file parses |
| RULES-16 | Callable wiring | J | T06 release_guard.test, T07 scaling.test | new callables listed in release guard expectations; `BODY_SCAN` profile maxInstances 10, `enforceAppCheck` follows the AI flag, runtime service account `fn-data`; `FOOD_LOOKUP` maxInstances 10; food AI callables on `AI_METERED` |

### 4.10 I18N - localisation

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| I18N-01 | EN/RU key parity for all new keys | U | T120 new_keys_parity_test, T121 translation_completeness_test | key sets of `bodyScan*`, `scanCheck*`, `checkCode*`, `nutrition*`, `reviewReason*`, `onbNutrition*`, `diary*`, `food*`, `foodCheck*` are identical in EN and RU ARB; no empty value; placeholders match between locales |
| I18N-02 | No untranslated literals in new UI | U | T122 no_untranslated_strings_test | the existing scan covers new widget directories; a deliberately named exception list is empty for new code |
| I18N-03 | RU plurals | U | T123 body_scan_plurals_test | weeks, kilograms and points render the right form for 1, 2, 5, 11, 21, 22, 25 in RU (one/few/many) and 1 vs 2 in EN |
| I18N-04 | Every closed code has a key | U | T124 closed_code_keys_test | each `CheckCode` -> `checkCode*`, each review reason -> `reviewReason*`, each food code -> `foodCheck*`, each training reason has a key, in both locales; adding an enum value without a key fails |
| I18N-05 | Numbers and dates via intl | W | T64 result_view_test, T86 nutrition_plan_page_test | RU renders decimal comma and localised weekday names; metric units; no hand-built number strings |
| I18N-06 | Notification strings resolved by caller | U | T50 scan_reminder_weekly_test | scheduled title/body equal the localised strings for the active locale |
| I18N-07 | Provider free text never displayed | W | T64 result_view_test, T101 food_detail_sheet_test | an unknown code or free-text field in the entry is not found anywhere in the widget tree |
| I18N-08 | RU expansion | W | T126 body_scan_a11y_test | chips and status panel with +30 % longer RU strings and text scale 1.5 produce no overflow exception |
| I18N-09 | Neutral wording | U | T124 closed_code_keys_test | EN and RU ARB values for calorie-range status contain none of: "over budget", "burn it off", "cheat", "bad food" (and RU equivalents listed in the test) |

### 4.11 A11Y - accessibility

| ID | Behaviour | Lvl | Test | Key assertions (fail if broken) |
|---|---|---|---|---|
| A11Y-01 | Readiness chips announce `label: text`; overlay excluded | W | T59 setup_status_panel_test, T60 skeleton_overlay_smoke_test | semantics tree contains each label+state string; overlay subtree has no semantics nodes |
| A11Y-02 | Countdown live region and manual shutter reachable | W | T68 scan_capture_screen_test | countdown number exposed as live region; manual shutter button has a label, is focusable and >= 48 dp |
| A11Y-03 | Analysis stages polite live region, Cancel first | W | T63 analysis_progress_view_test | stage change announces once; Cancel is first in traversal order |
| A11Y-04 | Chart alternative | W | T65 trend_chart_test | data table present; one-sentence summary with numbers; dots vs line distinguished by marker shape and legend (not colour alone) |
| A11Y-05 | Range slider semantics | W | T84 kcal_range_slider_test | two thumbs labelled "lowest daily calories" and "highest daily calories" (EN+RU); increase/decrease actions move by 10; bounds announced; touch target >= 48 dp |
| A11Y-06 | Large text | W | T126 body_scan_a11y_test, T125 semantics_targets_test | result, plan and diary pages at text scale 2.0 in RU: scrollable, no RenderFlex overflow, no clipped fixed-height cards |
| A11Y-07 | Neutral colour for exceeding range | W | T86 nutrition_plan_page_test | `above` status uses the neutral token, not the error token, and no warning icon |
| A11Y-08 | Professional notice calm and non-diagnostic | W | T85 professional_notice_test | no error colour, no alert icon, link to data-sources page present |
| A11Y-09 | Chips are buttons | W | T99 check_these_chips_test | each chip has `button: true` and an action label; tap target >= 48 dp |
| A11Y-10 | Status never colour-only | W | T59 setup_status_panel_test, T84 kcal_range_slider_test | for each state the icon or text differs, not just colour (golden-free: compare widget types and strings) |
| A11Y-11 | Colours from tokens | U | T37 pure_data_layer_guard_test | no `Color(0x` literals in new `widgets/` files; they use `app_semantic_colors` tokens |

## 5. Negative-path list (each must exist as an explicit failing-input test)

| # | Trigger | Required outcome | Covered by |
|---|---|---|---|
| N-01 | birth year 2008 (age 17) at clock 2026 | `referProfessional(underAge)`, no numbers | SAFE-01 |
| N-02 | birth year unknown | `needsProfile(birthYear)`, no plan | SAFE-01 |
| N-03 | pregnancy/breastfeeding flag reported | neutral notice, no numbers anywhere | SAFE-02, SAFE-07 |
| N-04 | eating-disorder / supervised nutrition flag reported | neutral notice, reason not stated or stored | SAFE-03, SAFE-07 |
| N-05 | clinician advised against exercise; surgery under restrictions | neutral notice | SAFE-04 |
| N-06 | safety questions unanswered | coach locked, `needsAnswer` | SAFE-05 |
| N-07 | stored range low 1199 / 900 | re-clamped on read; rules refuse < 1200 | SAFE-08, PLAN-16, RULES-04 |
| N-08 | slider dragged beyond bounds | value stays at bound | PLAN-18, SAFE-16 |
| N-09 | requested pace above the BMI-row maximum | clamped to maximum | SAFE-09 |
| N-10 | BMI 17.9 asking for fat loss; target weight BMI < 18.5 | maintain / `targetBelowHealthyRange` | SAFE-11 |
| N-11 | review would breach bounds | `keep(atSafetyLimit)` | SAFE-15 |
| N-12 | fewer than 3 weights or < 7 days | `needMoreData`, no change | PLAN-12 |
| N-13 | client creates or deletes `body_scans`; edits `estimate`, `status`, `provider`, `photosState` | refused (each key separately; mixed write refused) | RULES-02 |
| N-14 | another uid or canary token reads or writes any new path | refused | RULES-01, -13 |
| N-15 | wildcard-shaped write to a new collection | refused (carve-out proof) | RULES-09 |
| N-16 | profile save with `nutritionGuidance` / `foodAllergens` / unknown `nutrition` key | refused | RULES-08 |
| N-17 | Storage SDK access to any path | refused | RULES-12 |
| N-18 | anonymous caller on any new callable | refused | SCAN-32, FOOD-07 |
| N-19 | missing cloud consent while provider needs photos | `consent-required`, no URLs | PRIV-06 |
| N-20 | malformed scanId; takenAt out of window; subject out of range | invalid-argument at exact boundaries | SCAN-32 |
| N-21 | cancelled scan re-created | `scan-cancelled` | SCAN-32 |
| N-22 | estimate with missing / oversize / non-JPEG upload | `missing-upload` / refusal, doc stays pending | SCAN-33 |
| N-23 | provider throws; provider returns nonsense | quota refunded; `provider-output-invalid`; no silent clamp | SCAN-33, -34 |
| N-24 | daily quota exceeded (each callable at N+1) | `resource-exhausted` | SCAN-32, -33, -35, FOOD-07, -13, -14, -28 |
| N-25 | expired signed URL (403) | one fresh-URL cycle then success or surfaced error | SCAN-11 |
| N-26 | upload network failure | 1/2/4 s retries then queued with attempt+1; capped at 5 | SCAN-09, -11 |
| N-27 | no head and no shoulder landmarks; blur exception | `blurUnavailable`, nothing uploaded | PRIV-03 |
| N-28 | legacy v1 local scan | never auto-uploaded | SCAN-10 |
| N-29 | account deletion mid-flight; storage delete failure | writes aborted; deletion retried via reconciler | PRIV-10, -14 |
| N-30 | model returns garbage / negative / NaN / > 105 g macros / kcal mismatch | coerced or dropped, `dataInconsistent` flagged | FOOD-01 to -06 |
| N-31 | photo with no food; describe text with quotes/backticks; oversize image; wrong mime | empty items / invalid-argument | FOOD-06, -07 |
| N-32 | bad barcode check digit or length | rejected before any network call | FOOD-12, -13, -26 |
| N-33 | OFF 429 / 3 failures; Search-a-licious down; USDA energy missing; `serving_size` absent | breaker, fallback, derived energy, handled | FOOD-11, -13, -14 |
| N-34 | label with kJ only, decimal comma, unreadable fields, Cyrillic | normalised or `labelAmbiguous` | FOOD-15 |
| N-35 | feature flag off | `feature-disabled`, not retried, fallback UI | SCAN-40 |
| N-36 | duplicate import; non-increasing stream offsets; unknown sport | one session; rejected; `other` | ACT-01, -02, -05 |
| N-37 | RU key missing / placeholder mismatch / enum without key | parity test fails | I18N-01, -04 |
| N-38 | forged stored plan or review doc | re-clamped on read; reviews immutable | PLAN-16, RULES-05 |
| N-39 | text scale 2.0 in RU | no overflow | A11Y-06 |
| N-40 | nutrition advice would raise an intensity cap | cap stays at the safety value | PROG-10 |

## 6. Not testable without a device, emulator-with-hardware, or operator action

Each item is reported in the final evidence table as `UNVERIFIED (NOT_RUN: <reason>)` with the proxy test that does exist and the residual risk. Never reported as passed, never silently omitted.

| Item | Why not testable in this phase | Proxy evidence in this map | Reported as |
|---|---|---|---|
| Real camera preview, real ML Kit pose detection, skeleton accuracy | needs device camera and ML runtime | fakes for `ScanCamera`/pose frames (SCAN-01..05, T52, T53, T59, T60) | UNVERIFIED (NOT_RUN: device); logic verified against synthetic landmarks only |
| Readiness thresholds (distance, luminance 0.25-0.92) calibration | no device fleet | boundary tests of the configured values (SCAN-01) | UNVERIFIED (NOT_RUN: calibration on the operator's phone); thresholds remain "opening values" |
| Face-blur quality on real photos, tattoos, hair, isolate performance on a phone | needs real images and device | synthetic pixel test, fail-closed tests (PRIV-01..04) | UNVERIFIED (NOT_RUN: device); only the synthetic claim is evidenced |
| Health Connect / HealthKit permission and reads | platform permission UI | `HealthService` mocks, step-bucket logic (PLAN-09, ONB-06) | UNVERIFIED (NOT_RUN: device/platform); iOS never verified |
| Play Integrity / App Check enforcement | needs real attestation | `noteAppCheck` call order and profile flags in jest (RULES-16) | UNVERIFIED (NOT_RUN: platform attestation) |
| Live Vertex AI meal / label output quality, schema adherence, latency, prompt-injection resistance | live paid model, Q-6 operator item | `coerceMealAnalysis` against hostile fixtures (FOOD-01..09), gateway option assertions | UNVERIFIED (NOT_RUN: live model); no accuracy is claimed anywhere |
| Real Open Food Facts / USDA network behaviour, rate limits, Russian coverage | live network, Q-4 key | recorded fixture 3017620422003, breaker with injected clock (FOOD-10..14) | UNVERIFIED (NOT_RUN: live network) |
| Real signed-URL PUT to a private bucket, content-length-range enforcement, IAM, public-access prevention, 400-day lifecycle | bucket not provisioned (Q-5) | signing options asserted on the mock (SCAN-32), deny-all `storage.rules` on emulator (RULES-12) | UNVERIFIED (NOT_RUN: bucket not provisioned) |
| Secret Manager `USDA_FDC_API_KEY` binding | operator secret | missing-secret behaviour (FOOD-14) | UNVERIFIED (NOT_RUN: operator secret) |
| Scheduled purge trigger firing; Firestore TTL deletion; composite index deployment | needs deployed project | purge logic with injected clock (SCAN-36), index file shape (RULES-15) | UNVERIFIED (NOT_RUN: deployed project) |
| Local notification delivery and tap routing | OS behaviour | `MockNotificationService` scheduling (SCAN-27) | UNVERIFIED (NOT_RUN: device); one-shot chaining limit stands |
| `mobile_scanner` real barcode decode; `useUnbundled` model download | camera hardware | port fake (FOOD-26) | UNVERIFIED (NOT_RUN: device) |
| Real body-composition provider; any accuracy figure | none exists (D-3) | provisional estimator vectors (SCAN-30) | UNVERIFIED by design; the PROVISIONAL banner is the product statement |
| Screen-reader behaviour (TalkBack/VoiceOver), real contrast | device assistive tech | semantics-tree assertions (A11Y-01..11) | UNVERIFIED (NOT_RUN: assistive technology) |
| Visual layout / goldens | CI-only goldens, prohibited here | widget structure assertions | UNVERIFIED (NOT_RUN: goldens are CI-only) |
| BLE, Wear OS, vendor clouds | Phase 2, not built | model/merge only (ACT-*) | OUT OF SCOPE this sprint |
| iOS in general | no iOS device or CI | none | UNVERIFIED (NOT_RUN: iOS), stated as a limit in the final report |
| Legacy CI checkers (`scripts/ci/check_*.js`) and the full suites | prohibited by operator policy | the focused tests RULES-14, I18N-01, SCAN-* above | NOT_RUN by policy; CI-only failures are known limits, not work |

## 7. Ordering for the post-coding test phase

Coding completes first (C01..C27 per the sprint plan; nothing is run during it). Then, with the complete-set rule of section 0:

0. **Setup.** TI-1..TI-4 (section 1). Confirm each `VERIFY` item the tests depend on by reading the code (flag names, `connectivity_plus`, `dio`, programme builder seam SD-7); any mismatch updates this map before authoring.
1. **E0 first** (rules and flags): rules are the highest-impact and fail-closed surface, and the client may only ship after the rules (rollout order). Author T01..T11 including the new Storage file; run G0.
2. **E1 pure domain** (safety clamps, eligibility, review, trend, flow machine, activity merger, model JSON, programme function): fastest feedback, highest risk of silent harm. Author T12..T37; run G1 = E0 + E1.
3. **E2 onboarding and profile flow**, run G2.
4. **E3 body scan** (Dart state/widgets, then Functions callables, then the two journeys); run G3.
5. **E4 nutrition plan UI and review**, run G4 including the plan journey.
6. **E5 food** (Functions normalisers first, then callables, then Dart data, widgets, journey); run G5.
7. **E6 privacy, deletion, export** (jest, local wipe, the account-deletion e2e on the Auth+Firestore emulator); run G6.
8. **E7 l10n and accessibility**; run G7.
9. **Final**: the all-files list of section 10, once after E7 and once again after the last fix. Failures are triaged (product bug / test defect / flake / environment) with evidence; product bugs are fixed by the implementers and the COMPLETE set so far is re-run (not only the red file). Suspected flake: repeat that single file at least 5 times first; quarantine only with marker, issue link and date, listed separately in the summary.
10. **Only then** the specialist review phase and the final GPT-PM gate, with the section 11 evidence table bound to the exact head.

Within a gate: pure-Dart and Jest files run before emulator files (cheap first); emulator suites are run sequentially (one Firestore emulator, `maxWorkers: 1` in the e2e config).

## 8. Test file index (exact paths from the repository root D:\Repo\Fitness_App_bodyscan)

N = create, X = extend an existing file (existing tests in an extended file must keep passing unchanged). Cmd per section 1.

| Id | Lvl | Epic | N/X | Path | Cmd | Requirements covered |
|---|---|---|---|---|---|---|
| T01 | U | E0 | N | `mobile/test/core/config/body_scan_flags_test.dart` | FT | SCAN-40 |
| T02 | J | E0 | N | `functions/src/__tests__/feature_flags.test.ts` | JT | SCAN-40 |
| T03 | R | E0 | X | `functions/src/__rules__/firestore_rules.test.ts` | RE | PRIV-16, RULES-01, RULES-02, RULES-03, RULES-04, RULES-05, RULES-06, RULES-07, RULES-08, RULES-09, RULES-10, RULES-11, RULES-13 |
| T04 | S | E0 | N | `functions/src/__rules__/storage_rules.test.ts` | RS | RULES-12 |
| T05 | R | E0 | X | `functions/src/__rules__/data_access_policy.test.ts` | RE | PRIV-21, RULES-14 |
| T06 | J | E0 | X | `functions/src/__tests__/release_guard.test.ts` | JT | RULES-16 |
| T07 | J | E0 | X | `functions/src/__tests__/scaling.test.ts` | JT | RULES-16 |
| T08 | J | E0 | X | `functions/src/__tests__/abuse_guard.test.ts` | JT | FOOD-28 |
| T09 | J | E0 | X | `functions/src/__tests__/ai_gateway.test.ts` | JT | FOOD-08, FOOD-28 |
| T10 | J | E0 | X | `functions/src/monitoring/__tests__/ai_gateway_definitions.test.ts` | JT | FOOD-28 |
| T11 | J | E0 | N | `functions/src/__tests__/firestore_indexes_body_scan.test.ts` | JT | RULES-15 |
| T12 | U | E1 | N | `mobile/test/features/nutrition_plan/data/energy_math_test.dart` | FT | PLAN-01, PLAN-02, PLAN-03 |
| T13 | U | E1 | N | `mobile/test/features/nutrition_plan/data/safety_clamps_test.dart` | FT | SAFE-08, SAFE-09, SAFE-10, SAFE-11, SAFE-12, SAFE-13, SAFE-14 |
| T14 | U | E1 | N | `mobile/test/features/nutrition_plan/data/plan_calculator_test.dart` | FT | PLAN-03, PLAN-04, PLAN-05, PLAN-06, PLAN-07, PLAN-08, PLAN-09, PLAN-11, SAFE-08, SAFE-17 |
| T15 | U | E1 | N | `mobile/test/features/nutrition_plan/data/nutrition_eligibility_test.dart` | FT | SAFE-01, SAFE-02, SAFE-03, SAFE-04, SAFE-05, SAFE-06 |
| T16 | U | E1 | N | `mobile/test/features/nutrition_plan/data/weekly_review_test.dart` | FT | PLAN-12, PLAN-13, PLAN-14, SAFE-15 |
| T17 | U | E1 | N | `mobile/test/features/nutrition_plan/data/missing_inputs_test.dart` | FT | ONB-10 |
| T18 | U | E1 | N | `mobile/test/features/nutrition_plan/data/nutrition_training_state_test.dart` | FT | PROG-01, PROG-02, PROG-03, PROG-04, PROG-05, PROG-06, PROG-07, PROG-08, PROG-09 |
| T19 | U | E1 | N | `mobile/test/features/nutrition_plan/data/nutrition_inputs_test.dart` | FT | PLAN-10 |
| T20 | U | E1 | N | `mobile/test/features/body_scan/data/scan_trend_test.dart` | FT | SCAN-16, SCAN-17, SCAN-18 |
| T21 | U | E1 | N | `mobile/test/features/body_scan/data/weight_slope_test.dart` | FT | SCAN-19 |
| T22 | U | E1 | N | `mobile/test/features/body_scan/data/scan_result_math_test.dart` | FT | SCAN-14, SCAN-15 |
| T23 | U | E1 | N | `mobile/test/features/body_scan/data/plausibility_test.dart` | FT | SCAN-20 |
| T24 | U | E1 | N | `mobile/test/features/body_scan/data/check_items_test.dart` | FT | SCAN-21 |
| T25 | U | E1 | N | `mobile/test/features/body_scan/data/face_region_test.dart` | FT | PRIV-01 |
| T26 | U | E1 | N | `mobile/test/features/body_scan/data/body_scan_flow_machine_test.dart` | FT | SCAN-07, SCAN-08 |
| T27 | U | E1 | N | `mobile/test/features/body_scan/data/body_scan_job_test.dart` | FT | SCAN-09 |
| T28 | U | E1 | N | `mobile/test/features/activity/data/activity_models_test.dart` | FT | ACT-01, ACT-02, ACT-03, ACT-04 |
| T29 | U | E1 | N | `mobile/test/features/activity/data/activity_merger_test.dart` | FT | ACT-05, ACT-06, ACT-07, ACT-08, ACT-09, ACT-10, ACT-11, ACT-12, ACT-13 |
| T30 | U | E1 | N | `mobile/test/features/profile/nutrition_prefs_json_test.dart` | FT | ONB-04 |
| T31 | U | E1 | N | `mobile/test/features/profile/health_flags_json_test.dart` | FT | PRIV-16, ONB-05 |
| T32 | U | E1 | X | `mobile/test/features/safety/health_flags_field_coverage_test.dart` | FT | PRIV-16, ONB-05 |
| T33 | U | E1 | X | `mobile/test/features/safety/health_rules_parity_test.dart` | FT | PRIV-16 |
| T34 | U | E1 | X | `mobile/test/features/safety/f014_persistence_merge_test.dart` | FT | PRIV-16 |
| T35 | U | E1 | N | `mobile/test/features/programmes/nutrition_advice_combination_test.dart` | FT | PROG-10 |
| T36 | U | E1 | X | `mobile/test/features/programmes/programme_builder_test.dart` | FT | PROG-11 |
| T37 | U | E1 | N | `mobile/test/core/architecture/pure_data_layer_guard_test.dart` | FT | PLAN-20, ACT-13, A11Y-11 |
| T38 | U | E2 | N | `mobile/test/features/onboarding/step_nutrition_answered_test.dart` | FT | ONB-02 |
| T39 | U | E2 | N | `mobile/test/features/onboarding/onboarding_order_test.dart` | FT | ONB-01 |
| T40 | U | E2 | X | `mobile/test/features/onboarding/step_answered_test.dart` | FT | ONB-02 |
| T41 | U | E2 | X | `mobile/test/features/onboarding/questionnaire_notifier_test.dart` | FT | ONB-03 |
| T42 | W | E2 | N | `mobile/test/features/onboarding/step_nutrition_test.dart` | FT | ONB-06 |
| T43 | W | E2 | X | `mobile/test/features/onboarding/step_health_test.dart` | FT | ONB-07 |
| T44 | W | E2 | N | `mobile/test/features/onboarding/step_lifestyle_test.dart` | FT | ONB-07 |
| T45 | W | E2 | N | `mobile/test/features/nutrition_plan/nutrition_profile_flow_test.dart` | FT | ONB-09 |
| T46 | U | E2 | X | `mobile/test/router/app_router_gating_test.dart` | FT | ONB-08 |
| T47 | U | E2 | X | `mobile/test/router/reachability_test.dart` | FT | ONB-11 |
| T48 | U | E3 | N | `mobile/test/features/progress_photos/scan/scan_models_v2_test.dart` | FT | SCAN-06 |
| T49 | U | E3 | X | `mobile/test/features/progress_photos/scan/scan_store_test.dart` | FT | SCAN-06 |
| T50 | U | E3 | N | `mobile/test/features/progress_photos/scan/scan_reminder_weekly_test.dart` | FT | SCAN-27, I18N-06 |
| T51 | U | E3 | X | `mobile/test/features/progress_photos/scan/scan_reminder_test.dart` | FT | SCAN-27 |
| T52 | U | E3 | X | `mobile/test/features/progress_photos/scan/readiness_evaluator_test.dart` | FT | SCAN-01 |
| T53 | U | E3 | X | `mobile/test/features/progress_photos/scan/auto_shutter_machine_test.dart` | FT | SCAN-02 |
| T54 | U | E3 | N | `mobile/test/features/body_scan/state/blur_service_test.dart` | FT | PRIV-02, PRIV-03, PRIV-04 |
| T55 | U | E3 | N | `mobile/test/features/body_scan/state/body_scan_job_runner_test.dart` | FT | SCAN-10, PRIV-14, PRIV-18 |
| T56 | U | E3 | N | `mobile/test/features/body_scan/state/upload_flow_test.dart` | FT | SCAN-11, PRIV-03, PRIV-07 |
| T57 | U | E3 | N | `mobile/test/features/body_scan/state/body_scan_history_merge_test.dart` | FT | SCAN-29 |
| T58 | U | E3 | N | `mobile/test/features/body_scan/state/body_scan_settings_test.dart` | FT | SCAN-28 |
| T59 | W | E3 | N | `mobile/test/features/body_scan/widgets/setup_status_panel_test.dart` | FT | SCAN-04, A11Y-01, A11Y-10 |
| T60 | W | E3 | N | `mobile/test/features/body_scan/widgets/skeleton_overlay_smoke_test.dart` | FT | SCAN-04, SCAN-05, A11Y-01 |
| T61 | W | E3 | N | `mobile/test/features/body_scan/widgets/cloud_consent_sheet_test.dart` | FT | PRIV-05 |
| T62 | W | E3 | N | `mobile/test/features/body_scan/widgets/weight_prompt_sheet_test.dart` | FT | SCAN-26 |
| T63 | W | E3 | N | `mobile/test/features/body_scan/widgets/analysis_progress_view_test.dart` | FT | SCAN-12, A11Y-03 |
| T64 | W | E3 | N | `mobile/test/features/body_scan/widgets/result_view_test.dart` | FT | SCAN-13, PLAN-13, I18N-05, I18N-07 |
| T65 | W | E3 | N | `mobile/test/features/body_scan/widgets/trend_chart_test.dart` | FT | SCAN-22, A11Y-04 |
| T66 | W | E3 | N | `mobile/test/features/body_scan/widgets/scan_history_list_test.dart` | FT | SCAN-23 |
| T67 | W | E3 | N | `mobile/test/features/body_scan/widgets/retention_settings_view_test.dart` | FT | PRIV-08, PRIV-09 |
| T68 | W | E3 | X | `mobile/test/features/progress_photos/scan/ui/scan_capture_screen_test.dart` | FT | SCAN-03, A11Y-02 |
| T69 | W | E3 | X | `mobile/test/features/progress_photos/scan/ui/scan_compare_screen_test.dart` | FT | SCAN-24 |
| T70 | W | E3 | X | `mobile/test/features/progress_photos/scan/ui/scan_gate_delete_test.dart` | FT | SCAN-25 |
| T71 | Y | E3 | N | `mobile/test/features/body_scan/body_scan_journey_test.dart` | FT | SCAN-37 |
| T72 | Y | E3 | N | `mobile/test/features/body_scan/body_scan_kill_resume_journey_test.dart` | FT | SCAN-38 |
| T73 | U | E3 | N | `mobile/test/features/body_scan/body_scan_static_guard_test.dart` | FT | PRIV-17, ONB-12 |
| T74 | J | E3 | N | `functions/src/__tests__/body_scan_create.test.ts` | JT | SCAN-32, PRIV-06, PRIV-07 |
| T75 | J | E3 | N | `functions/src/__tests__/body_scan_estimate.test.ts` | JT | SCAN-33, PRIV-08, PRIV-15 |
| T76 | J | E3 | N | `functions/src/__tests__/body_scan_delete.test.ts` | JT | SCAN-35 |
| T77 | J | E3 | N | `functions/src/__tests__/body_scan_purge.test.ts` | JT | SCAN-36 |
| T78 | J | E3 | N | `functions/src/__tests__/provisional_estimator.test.ts` | JT | SCAN-30 |
| T79 | J | E3 | N | `functions/src/__tests__/validate_estimate.test.ts` | JT | SCAN-34, SAFE-18 |
| T80 | J | E3 | N | `functions/src/__tests__/estimator_registry.test.ts` | JT | SCAN-31 |
| T81 | U | E4 | N | `mobile/test/features/nutrition_plan/state/plan_repository_test.dart` | FT | PRIV-14, PLAN-16 |
| T82 | U | E4 | N | `mobile/test/features/nutrition_plan/state/review_scheduler_test.dart` | FT | PLAN-15 |
| T83 | U | E4 | N | `mobile/test/features/nutrition_plan/state/nutrition_providers_test.dart` | FT | PLAN-19, SAFE-07 |
| T84 | W | E4 | N | `mobile/test/features/nutrition_plan/widgets/kcal_range_slider_test.dart` | FT | PLAN-18, SAFE-16, A11Y-05, A11Y-10 |
| T85 | W | E4 | N | `mobile/test/features/nutrition_plan/widgets/professional_notice_test.dart` | FT | SAFE-07, A11Y-08 |
| T86 | W | E4 | N | `mobile/test/features/nutrition_plan/nutrition_plan_page_test.dart` | FT | PLAN-17, SAFE-12, SAFE-16, FOOD-29, I18N-05, A11Y-07 |
| T87 | W | E4 | X | `mobile/test/features/progress_page_test.dart` | FT | SCAN-39 |
| T88 | W | E4 | X | `mobile/test/features/home/home_dashboard_test.dart` | FT | SCAN-39 |
| T89 | Y | E4 | N | `mobile/test/features/nutrition_plan/nutrition_journey_test.dart` | FT | PLAN-21 |
| T90 | U | E5 | N | `mobile/test/features/food_diary/data/portion_math_test.dart` | FT | FOOD-17 |
| T91 | U | E5 | N | `mobile/test/features/food_diary/data/day_totals_test.dart` | FT | FOOD-18, FOOD-19 |
| T92 | U | E5 | N | `mobile/test/features/food_diary/data/check_these_test.dart` | FT | FOOD-20 |
| T93 | U | E5 | N | `mobile/test/features/food_diary/data/gtin_validator_test.dart` | FT | FOOD-12 |
| T94 | U | E5 | N | `mobile/test/features/food_diary/data/label_scale_test.dart` | FT | FOOD-16 |
| T95 | U | E5 | N | `mobile/test/features/food_diary/data/generic_foods_test.dart` | FT | FOOD-22 |
| T96 | U | E5 | N | `mobile/test/features/food_diary/data/food_entry_test.dart` | FT | FOOD-23 |
| T97 | U | E5 | N | `mobile/test/features/nutrition_plan/data/food_suggestions_test.dart` | FT | FOOD-21 |
| T98 | U | E5 | N | `mobile/test/features/food_diary/state/food_api_test.dart` | FT | FOOD-24 |
| T99 | W | E5 | N | `mobile/test/features/food_diary/widgets/check_these_chips_test.dart` | FT | FOOD-20, A11Y-09 |
| T100 | W | E5 | N | `mobile/test/features/food_diary/food_diary_page_test.dart` | FT | FOOD-25 |
| T101 | W | E5 | N | `mobile/test/features/food_diary/food_detail_sheet_test.dart` | FT | FOOD-25, I18N-07 |
| T102 | W | E5 | N | `mobile/test/features/food_diary/barcode_flow_test.dart` | FT | FOOD-26 |
| T103 | Y | E5 | N | `mobile/test/features/food_diary/food_diary_journey_test.dart` | FT | PRIV-19, FOOD-27 |
| T104 | J | E5 | N | `functions/src/__tests__/coerce_meal_analysis.test.ts` | JT | FOOD-01, FOOD-02, FOOD-03, FOOD-04, FOOD-05, FOOD-06 |
| T105 | J | E5 | N | `functions/src/__tests__/nutrition_normalise.test.ts` | JT | FOOD-04, FOOD-10 |
| T106 | J | E5 | N | `functions/src/__tests__/label_normalise.test.ts` | JT | FOOD-15 |
| T107 | J | E5 | N | `functions/src/__tests__/gtin_validator.test.ts` | JT | FOOD-12 |
| T108 | J | E5 | N | `functions/src/__tests__/lookup_barcode.test.ts` | JT | FOOD-11, FOOD-13 |
| T109 | J | E5 | N | `functions/src/__tests__/search_foods.test.ts` | JT | FOOD-14 |
| T110 | J | E5 | N | `functions/src/__tests__/analyze_meal_photo.test.ts` | JT | PRIV-15, PRIV-19, FOOD-07, FOOD-08, FOOD-09 |
| T111 | J | E5 | N | `functions/src/__tests__/parse_nutrition_label.test.ts` | JT | PRIV-19, FOOD-15 |
| T112 | J | E6 | X | `functions/src/__tests__/delete_account.test.ts` | JT | PRIV-10 |
| T113 | J | E6 | X | `functions/src/__tests__/account_deletion_reconcile.test.ts` | JT | PRIV-10 |
| T114 | J | E6 | X | `functions/src/__tests__/account_export.test.ts` | JT | PRIV-12 |
| T115 | Y | E6 | X | `functions/src/__e2e__/account_deletion.e2e.test.ts` | EE | PRIV-11 |
| T116 | U | E6 | X | `mobile/test/features/account_deletion/local_data_wipe_test.dart` | FT | PRIV-11 |
| T117 | U | E6 | X | `mobile/test/features/data_export/data_export_test.dart` | FT | PRIV-13 |
| T118 | U | E6 | X | `mobile/test/features/data_export/server_export_merge_test.dart` | FT | PRIV-13 |
| T119 | U | E6 | N | `mobile/test/features/body_scan/privacy_copy_test.dart` | FT | PRIV-20 |
| T120 | U | E7 | N | `mobile/test/l10n/new_keys_parity_test.dart` | FT | I18N-01 |
| T121 | U | E7 | X | `mobile/test/l10n/translation_completeness_test.dart` | FT | I18N-01 |
| T122 | U | E7 | X | `mobile/test/l10n/no_untranslated_strings_test.dart` | FT | I18N-02 |
| T123 | U | E7 | N | `mobile/test/l10n/body_scan_plurals_test.dart` | FT | I18N-03 |
| T124 | U | E7 | N | `mobile/test/l10n/closed_code_keys_test.dart` | FT | I18N-04, I18N-09 |
| T125 | W | E7 | X | `mobile/test/features/accessibility/semantics_targets_test.dart` | FT | A11Y-06 |
| T126 | W | E7 | N | `mobile/test/features/accessibility/body_scan_a11y_test.dart` | FT | I18N-08, A11Y-06 |

## 9. Per-epic complete sets and gate commands

After each epic the authoring agents run EVERY file listed for that epic AND every file of all earlier epics (gate Gn = sets E0..En, cumulative, nothing sampled). Run order inside a gate: JT, RE/RS/EE (emulator), then FT. Paths are relative to the directory in the Set-Location line. Epic names follow the sprint plan (E0 flags/rules/infra, E1 pure domain, E2 onboarding, E3 body scan, E4 nutrition plan UI and review, E5 food, E6 privacy/deletion/export, E7 l10n and accessibility).

### E0 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/core/config/body_scan_flags_test.dart
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/feature_flags.test.ts src/__tests__/release_guard.test.ts src/__tests__/scaling.test.ts src/__tests__/abuse_guard.test.ts src/__tests__/ai_gateway.test.ts src/monitoring/__tests__/ai_gateway_definitions.test.ts src/__tests__/firestore_indexes_body_scan.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules src/__rules__/firestore_rules.test.ts src/__rules__/data_access_policy.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/storage_rules.test.ts
```

### E1 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/nutrition_plan/data/energy_math_test.dart test/features/nutrition_plan/data/safety_clamps_test.dart test/features/nutrition_plan/data/plan_calculator_test.dart test/features/nutrition_plan/data/nutrition_eligibility_test.dart test/features/nutrition_plan/data/weekly_review_test.dart test/features/nutrition_plan/data/missing_inputs_test.dart test/features/nutrition_plan/data/nutrition_training_state_test.dart test/features/nutrition_plan/data/nutrition_inputs_test.dart test/features/body_scan/data/scan_trend_test.dart test/features/body_scan/data/weight_slope_test.dart test/features/body_scan/data/scan_result_math_test.dart test/features/body_scan/data/plausibility_test.dart test/features/body_scan/data/check_items_test.dart test/features/body_scan/data/face_region_test.dart test/features/body_scan/data/body_scan_flow_machine_test.dart test/features/body_scan/data/body_scan_job_test.dart test/features/activity/data/activity_models_test.dart test/features/activity/data/activity_merger_test.dart test/features/profile/nutrition_prefs_json_test.dart test/features/profile/health_flags_json_test.dart test/features/safety/health_flags_field_coverage_test.dart test/features/safety/health_rules_parity_test.dart test/features/safety/f014_persistence_merge_test.dart test/features/programmes/nutrition_advice_combination_test.dart test/features/programmes/programme_builder_test.dart test/core/architecture/pure_data_layer_guard_test.dart
```

### E2 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/onboarding/step_nutrition_answered_test.dart test/features/onboarding/onboarding_order_test.dart test/features/onboarding/step_answered_test.dart test/features/onboarding/questionnaire_notifier_test.dart test/features/onboarding/step_nutrition_test.dart test/features/onboarding/step_health_test.dart test/features/onboarding/step_lifestyle_test.dart test/features/nutrition_plan/nutrition_profile_flow_test.dart test/router/app_router_gating_test.dart test/router/reachability_test.dart
```

### E3 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/progress_photos/scan/scan_models_v2_test.dart test/features/progress_photos/scan/scan_store_test.dart test/features/progress_photos/scan/scan_reminder_weekly_test.dart test/features/progress_photos/scan/scan_reminder_test.dart test/features/progress_photos/scan/readiness_evaluator_test.dart test/features/progress_photos/scan/auto_shutter_machine_test.dart test/features/body_scan/state/blur_service_test.dart test/features/body_scan/state/body_scan_job_runner_test.dart test/features/body_scan/state/upload_flow_test.dart test/features/body_scan/state/body_scan_history_merge_test.dart test/features/body_scan/state/body_scan_settings_test.dart test/features/body_scan/widgets/setup_status_panel_test.dart test/features/body_scan/widgets/skeleton_overlay_smoke_test.dart test/features/body_scan/widgets/cloud_consent_sheet_test.dart test/features/body_scan/widgets/weight_prompt_sheet_test.dart test/features/body_scan/widgets/analysis_progress_view_test.dart test/features/body_scan/widgets/result_view_test.dart test/features/body_scan/widgets/trend_chart_test.dart test/features/body_scan/widgets/scan_history_list_test.dart test/features/body_scan/widgets/retention_settings_view_test.dart test/features/progress_photos/scan/ui/scan_capture_screen_test.dart test/features/progress_photos/scan/ui/scan_compare_screen_test.dart test/features/progress_photos/scan/ui/scan_gate_delete_test.dart test/features/body_scan/body_scan_journey_test.dart test/features/body_scan/body_scan_kill_resume_journey_test.dart test/features/body_scan/body_scan_static_guard_test.dart
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/body_scan_create.test.ts src/__tests__/body_scan_estimate.test.ts src/__tests__/body_scan_delete.test.ts src/__tests__/body_scan_purge.test.ts src/__tests__/provisional_estimator.test.ts src/__tests__/validate_estimate.test.ts src/__tests__/estimator_registry.test.ts
```

### E4 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/nutrition_plan/state/plan_repository_test.dart test/features/nutrition_plan/state/review_scheduler_test.dart test/features/nutrition_plan/state/nutrition_providers_test.dart test/features/nutrition_plan/widgets/kcal_range_slider_test.dart test/features/nutrition_plan/widgets/professional_notice_test.dart test/features/nutrition_plan/nutrition_plan_page_test.dart test/features/progress_page_test.dart test/features/home/home_dashboard_test.dart test/features/nutrition_plan/nutrition_journey_test.dart
```

### E5 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/food_diary/data/portion_math_test.dart test/features/food_diary/data/day_totals_test.dart test/features/food_diary/data/check_these_test.dart test/features/food_diary/data/gtin_validator_test.dart test/features/food_diary/data/label_scale_test.dart test/features/food_diary/data/generic_foods_test.dart test/features/food_diary/data/food_entry_test.dart test/features/nutrition_plan/data/food_suggestions_test.dart test/features/food_diary/state/food_api_test.dart test/features/food_diary/widgets/check_these_chips_test.dart test/features/food_diary/food_diary_page_test.dart test/features/food_diary/food_detail_sheet_test.dart test/features/food_diary/barcode_flow_test.dart test/features/food_diary/food_diary_journey_test.dart
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/coerce_meal_analysis.test.ts src/__tests__/nutrition_normalise.test.ts src/__tests__/label_normalise.test.ts src/__tests__/gtin_validator.test.ts src/__tests__/lookup_barcode.test.ts src/__tests__/search_foods.test.ts src/__tests__/analyze_meal_photo.test.ts src/__tests__/parse_nutrition_label.test.ts
```

### E6 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/features/account_deletion/local_data_wipe_test.dart test/features/data_export/data_export_test.dart test/features/data_export/server_export_merge_test.dart test/features/body_scan/privacy_copy_test.dart
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts src/__tests__/account_export.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.e2e.config.js firestore,auth demo-fitness-e2e src/__e2e__/account_deletion.e2e.test.ts
```

### E7 files (authored or extended in this epic)

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/l10n/new_keys_parity_test.dart test/l10n/translation_completeness_test.dart test/l10n/no_untranslated_strings_test.dart test/l10n/body_scan_plurals_test.dart test/l10n/closed_code_keys_test.dart test/features/accessibility/semantics_targets_test.dart test/features/accessibility/body_scan_a11y_test.dart
```

## 10. FINAL set: all agent-written tests, every file explicit

Run after E7 and again after the last fix. Same three-part order. This is the only multi-file invocation; it is an explicit list of the 126 files in section 8, never a directory, glob or bare runner.

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/mobile; flutter test test/core/config/body_scan_flags_test.dart test/features/nutrition_plan/data/energy_math_test.dart test/features/nutrition_plan/data/safety_clamps_test.dart test/features/nutrition_plan/data/plan_calculator_test.dart test/features/nutrition_plan/data/nutrition_eligibility_test.dart test/features/nutrition_plan/data/weekly_review_test.dart test/features/nutrition_plan/data/missing_inputs_test.dart test/features/nutrition_plan/data/nutrition_training_state_test.dart test/features/nutrition_plan/data/nutrition_inputs_test.dart test/features/body_scan/data/scan_trend_test.dart test/features/body_scan/data/weight_slope_test.dart test/features/body_scan/data/scan_result_math_test.dart test/features/body_scan/data/plausibility_test.dart test/features/body_scan/data/check_items_test.dart test/features/body_scan/data/face_region_test.dart test/features/body_scan/data/body_scan_flow_machine_test.dart test/features/body_scan/data/body_scan_job_test.dart test/features/activity/data/activity_models_test.dart test/features/activity/data/activity_merger_test.dart test/features/profile/nutrition_prefs_json_test.dart test/features/profile/health_flags_json_test.dart test/features/safety/health_flags_field_coverage_test.dart test/features/safety/health_rules_parity_test.dart test/features/safety/f014_persistence_merge_test.dart test/features/programmes/nutrition_advice_combination_test.dart test/features/programmes/programme_builder_test.dart test/core/architecture/pure_data_layer_guard_test.dart test/features/onboarding/step_nutrition_answered_test.dart test/features/onboarding/onboarding_order_test.dart test/features/onboarding/step_answered_test.dart test/features/onboarding/questionnaire_notifier_test.dart test/features/onboarding/step_nutrition_test.dart test/features/onboarding/step_health_test.dart test/features/onboarding/step_lifestyle_test.dart test/features/nutrition_plan/nutrition_profile_flow_test.dart test/router/app_router_gating_test.dart test/router/reachability_test.dart test/features/progress_photos/scan/scan_models_v2_test.dart test/features/progress_photos/scan/scan_store_test.dart test/features/progress_photos/scan/scan_reminder_weekly_test.dart test/features/progress_photos/scan/scan_reminder_test.dart test/features/progress_photos/scan/readiness_evaluator_test.dart test/features/progress_photos/scan/auto_shutter_machine_test.dart test/features/body_scan/state/blur_service_test.dart test/features/body_scan/state/body_scan_job_runner_test.dart test/features/body_scan/state/upload_flow_test.dart test/features/body_scan/state/body_scan_history_merge_test.dart test/features/body_scan/state/body_scan_settings_test.dart test/features/body_scan/widgets/setup_status_panel_test.dart test/features/body_scan/widgets/skeleton_overlay_smoke_test.dart test/features/body_scan/widgets/cloud_consent_sheet_test.dart test/features/body_scan/widgets/weight_prompt_sheet_test.dart test/features/body_scan/widgets/analysis_progress_view_test.dart test/features/body_scan/widgets/result_view_test.dart test/features/body_scan/widgets/trend_chart_test.dart test/features/body_scan/widgets/scan_history_list_test.dart test/features/body_scan/widgets/retention_settings_view_test.dart test/features/progress_photos/scan/ui/scan_capture_screen_test.dart test/features/progress_photos/scan/ui/scan_compare_screen_test.dart test/features/progress_photos/scan/ui/scan_gate_delete_test.dart test/features/body_scan/body_scan_journey_test.dart test/features/body_scan/body_scan_kill_resume_journey_test.dart test/features/body_scan/body_scan_static_guard_test.dart test/features/nutrition_plan/state/plan_repository_test.dart test/features/nutrition_plan/state/review_scheduler_test.dart test/features/nutrition_plan/state/nutrition_providers_test.dart test/features/nutrition_plan/widgets/kcal_range_slider_test.dart test/features/nutrition_plan/widgets/professional_notice_test.dart test/features/nutrition_plan/nutrition_plan_page_test.dart test/features/progress_page_test.dart test/features/home/home_dashboard_test.dart test/features/nutrition_plan/nutrition_journey_test.dart test/features/food_diary/data/portion_math_test.dart test/features/food_diary/data/day_totals_test.dart test/features/food_diary/data/check_these_test.dart test/features/food_diary/data/gtin_validator_test.dart test/features/food_diary/data/label_scale_test.dart test/features/food_diary/data/generic_foods_test.dart test/features/food_diary/data/food_entry_test.dart test/features/nutrition_plan/data/food_suggestions_test.dart test/features/food_diary/state/food_api_test.dart test/features/food_diary/widgets/check_these_chips_test.dart test/features/food_diary/food_diary_page_test.dart test/features/food_diary/food_detail_sheet_test.dart test/features/food_diary/barcode_flow_test.dart test/features/food_diary/food_diary_journey_test.dart test/features/account_deletion/local_data_wipe_test.dart test/features/data_export/data_export_test.dart test/features/data_export/server_export_merge_test.dart test/features/body_scan/privacy_copy_test.dart test/l10n/new_keys_parity_test.dart test/l10n/translation_completeness_test.dart test/l10n/no_untranslated_strings_test.dart test/l10n/body_scan_plurals_test.dart test/l10n/closed_code_keys_test.dart test/features/accessibility/semantics_targets_test.dart test/features/accessibility/body_scan_a11y_test.dart
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; npx --no-install jest src/__tests__/feature_flags.test.ts src/__tests__/release_guard.test.ts src/__tests__/scaling.test.ts src/__tests__/abuse_guard.test.ts src/__tests__/ai_gateway.test.ts src/monitoring/__tests__/ai_gateway_definitions.test.ts src/__tests__/firestore_indexes_body_scan.test.ts src/__tests__/body_scan_create.test.ts src/__tests__/body_scan_estimate.test.ts src/__tests__/body_scan_delete.test.ts src/__tests__/body_scan_purge.test.ts src/__tests__/provisional_estimator.test.ts src/__tests__/validate_estimate.test.ts src/__tests__/estimator_registry.test.ts src/__tests__/coerce_meal_analysis.test.ts src/__tests__/nutrition_normalise.test.ts src/__tests__/label_normalise.test.ts src/__tests__/gtin_validator.test.ts src/__tests__/lookup_barcode.test.ts src/__tests__/search_foods.test.ts src/__tests__/analyze_meal_photo.test.ts src/__tests__/parse_nutrition_label.test.ts src/__tests__/delete_account.test.ts src/__tests__/account_deletion_reconcile.test.ts src/__tests__/account_export.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore demo-fitness-rules src/__rules__/firestore_rules.test.ts src/__rules__/data_access_policy.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.rules.config.js firestore,storage demo-fitness-rules src/__rules__/storage_rules.test.ts
```

```powershell
Set-Location D:/Repo/Fitness_App_bodyscan/functions; node scripts/run_emulator_tests.js jest.e2e.config.js firestore,auth demo-fitness-e2e src/__e2e__/account_deletion.e2e.test.ts
```

## 11. Evidence record, counts, residual notes

**Evidence table to fill in the test phase** (verification-contract; one row per requirement id, bound to the exact head; a new commit invalidates it):

| Claim (requirement id) | Evidence (Tnn, assertion) | Command | Head | Result (PASS / FAIL / NOT_RUN) | Not covered |
|---|---|---|---|---|---|

Rows for the section 6 items are filled with `UNVERIFIED (NOT_RUN: reason)`; attempted, skipped or cancelled files are never recorded as PASS.

**Counts (this map, before authoring):**

| Item | Count |
|---|---|
| Requirement ids | 201: SCAN 40, PLAN 21, ONB 12, SAFE 18, PRIV 21, FOOD 29, ACT 13, PROG 11, RULES 16, I18N 9, A11Y 11 |
| Test files | 126 (91 to create, 35 to extend) |
| By level | pure-Dart unit U 66, widget W 27, Jest J 25, Firestore rules R 2, Storage rules S 1, journey Y 5 (4 mobile + 1 emulator e2e) |
| By epic | E0 11, E1 26, E2 10, E3 33, E4 9, E5 22, E6 8, E7 7 |
| Negative-path items | 40 (section 5) |
| Not-testable-here items | 18 (section 6) |
| Planned quarantines | 0 |

Test-case counts (individual `test()` cases) are not predicted here; the authoring agents report them per file. Expected vectors are hand-computed and must be re-derived by the author.

**Residual notes.** (1) Rows PROG-11 and the programme builder hook depend on decision SD-7 (small seam or provider only). (2) TI-1 and TI-2 are test-infrastructure changes and are committed with their own change record. (3) Hard-coded literals such as the hold time 1000 ms, countdown 3-2-1 and quotas are assertions on purpose: changing them must change a test. (4) The map does not claim any accuracy of the body-fat estimate: SCAN-30 verifies the formula and honesty properties only.
