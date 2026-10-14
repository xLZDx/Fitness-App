# Change record: scan result to equipment page mapping fixes

## What changed
- `mobile/assets/data/equipment.json`: the `bench_press` row was named "Weight bench" with the description of a generic adjustable bench. Renamed to "Bench press station" (matching the canonical model name it answers) with a description of the barbell bench-press station. "Weight bench" is an alias of `adjustable_bench`, so the old name resolved to a different catalogue page than the row it labelled.
- `functions/src/ai_exercise_generation.ts`: `EQUIPMENT_NAMES_EN` entry for `bench_press` updated to the same name. Required, not optional: `functions/src/__tests__/ai_exercise_generation.test.ts` (parity block) compares this map to `equipment.json` pair by pair.
- `mobile/lib/features/visual_equipment/data/machine_text_anchor.dart`: removed the phrase `'hip thrust' -> 'hip_thrust_machine'`. That id does not exist in the catalogue, so a placard reading "HIP THRUST" produced a confident result whose page was "not found".
- `mobile/lib/features/scanner/scanner_page.dart`: `_openEquipment` forwarded the current scan's `scanId` for every caller. "My machines" chips and the live card, which open a machine that is not this scan's answer, therefore carried scan A's `scanId` into machine B's equipment/exercise/workout chain. Now only the locked card and the matches rows (`fromCurrentScan: true`) forward it.
- New tests: `mobile/test/features/visual_equipment/canonical_machine_catalogue_contract_test.dart` and `mobile/test/features/scanner/scanner_match_navigation_test.dart`.

## Why
Operator report from a real phone: the Scan tab named one machine and the page that opened did not match it (an elliptical page for a machine that was not an elliptical). Investigation found no id/index/slug confusion in the route (`/equipment/:id` takes the id verbatim) and no alias collision between the 71 canonical machine names; the defects above are the ones that could be reproduced from data and code. Gemini answers were not in question.

## Affected contracts and paths
Catalogue name of one row (`bench_press`, English only; the Russian name was already correct); text-anchor phrase table; scanId forwarding from the Scan tab (additive restriction: history chips and live card now navigate without `?scanId=`).

## Verification state
Focused Flutter run from `mobile/` (8 files, 228 tests, all passed): the two new files, `machine_text_anchor_test`, `text_anchor_pipeline_test`, `scanner_page_identity_visibility_test`, `scanner_page_scan_id_cleanup_test`, `vendor_catalog_test`, `ai_exercise_generator_test`.
- Contract test: all 71 canonical names parsed from the TypeScript source resolve through the real `EquipmentAliasIndex` and the real `parseResponse` to a hand-written expected id and category; no cardio page for a non-cardio machine; no duplicate alias; every catalogue row reachable; each row's own English and Russian name resolves back to itself; anchor and on-device label map ids exist in the catalogue.
- Navigation test: real `ScannerPage`, GoRouter, `EquipmentDetailPage` and Russian catalogue; each alternatives row (chest press, pec deck, leg press) opens its own page; remembered chips open their own page with no `scanId`; a second scan never reuses the first scan's `scanId` or rows.

NOT verified: no live camera or real device run; no real Gemini answers; the Jest parity test for `EQUIPMENT_NAMES_EN` was not run (no `functions/node_modules` in this worktree), so the one-line map edit rests on reading that test; the operator's exact "elliptical" scan was not reproduced, so it may also have been a plain model misclassification, which the client cannot detect.

## Addendum: machine page hero picture (follow-up, branch sprint/coach-form-fixes-2026-10)

### What changed
- `mobile/lib/features/equipment/state/equipment_providers.dart`: `equipmentHeroImageProvider` no longer returns the poster of the first injury-safe exercise linked to the machine. It calls the new pure `pickHeroExercise` (`mobile/lib/features/equipment/data/equipment_hero.dart`) and gets the alias index from a new `equipmentAliasIndexProvider`.
- Rule: (0) the machine row's optional `heroExerciseId`, if present among the candidates; (1) an exercise whose English id slug resolves through the alias index to this machine; (2) an exercise whose vendor equipment label does; otherwise no hero (the page already draws its placeholder). Within a tier the shortest slug wins, then the id, so the pick is stable across catalogue order and language (translated titles are never read).
- `mobile/lib/features/equipment/data/equipment_models.dart`: `EquipmentItem.heroExerciseId` (optional, kept through translation overlays).
- `mobile/assets/data/equipment.json`: `bench_press` gets `heroExerciseId: ea_barbell_bench_press`.
- `mobile/assets/data/equipment_aliases.json`: added aliases `airbike` (air_bike), `ski ergometer` (ski_erg), `sissy squat` (sissy_squat_machine), so the exercises the vendor named that way are recognised as their machine.
- Tests: new `mobile/test/features/equipment/equipment_hero_contract_test.dart`; `mobile/test/features/equipment/hero_image_test.dart` fixtures renamed so they name the machine, plus new cases for non-naming exercises, ordering stability, label fallback and the curated id.

### Why
Operator screenshot: the "Жим лёжа (стойка)" page (bench_press) showed a man seated on a bench curling dumbbells. A machine's exercise list holds everything that can merely use it, so "first with a poster" was an accident of file order. The same defect shape existed for most machines (dip station showed an ab tuck, vertical pole a dragonfly, barbell a split squat). Other uses of `posterFor` (exercise thumbnails, player, exercise reference) show an exercise's own poster and are not affected; the scanner result rows and "My machines" chips show no pictures.

### Measured effect (real assets, unscreened by injuries)
Of 69 machines: 35 changed hero, 29 unchanged, 5 without a hero. Of those 5, four never had a poster-bearing exercise (recumbent_bike, glute_kickback_machine, t_bar_row, rotary_torso_machine) and one lost a wrong hero (sliding_disc, whose only poster exercise is a towel-slide lunge). bench_press now resolves to the barbell bench press; the old rule picked `ea_alternating_biceps_curl_seated_dumbbells`. The operator's reference example "Жим JM со штангой" (`ea_barbell_jm_bench_press`) was not chosen: JM press is a triceps variation, and the plain barbell bench press is the movement this station is for; changing `heroExerciseId` swaps it.

### Verification state
Focused Flutter run from `mobile/` of 16 files, 320 tests, all passed: the new contract test, `hero_image_test`, the scan catalogue contract test, the scanner navigation test, and the existing asset/registry/label/vendor/recognition/equipment-detail/router tests that read the files touched. The contract test asserts every chosen hero names its machine (or is the curated one), curated ids exist/belong/have a poster, the pick is order-independent over shuffled input, the no-hero set is pinned, and the old rule really picked the curl for bench_press.
NOT verified: how the new posters look on a device; injury screening on top of the ranking (the contract test uses unscreened exercises; a screened-out hero falls to the next ranked one); several non-bench picks are plausible rather than ideal (for example squat_rack picks `ea_back_lever`, which names the rack only by vendor label) and were not reviewed one by one.

## Addendum 2: review fixes for the hero and scan work

### What changed
- `mobile/test/features/equipment/hero_image_test.dart`: injury screening of the header is now covered with a real profile (knee injury): a contraindicated curated hero is replaced by the next safe naming exercise, or by no hero; screening is shown to run before ranking. A header built from the raw unscreened list fails these cases.
- `mobile/test/features/equipment/equipment_hero_contract_test.dart`: the self-referential check stays as a sanity check, but the real guard is a pinned map machine id -> hero exercise id for all 69 machines (5 are deliberately `null`), plus pinned counts versus the old rule (35 changed, 1 lost, 29 unchanged). A new alias, a looser label rule or a catalogue change that re-points a header now fails and has to be reviewed.
- `mobile/assets/data/equipment.json`: `squat_rack` -> `ea_barbell_full_squat` and `barbell` -> `ea_barbell_deadlift` are now curated (the generic rule had picked a back lever and a barbell curl). `bench_press` stays `ea_barbell_bench_press`.
- Documented limit (test `the barbell stations keep their curated header exercise`): the alias index takes the longest alias in the text, so `dumbbell bench press` and `band bench press` name bench_press exactly like the barbell press, and without a curated id the generic pick for bench_press is not the barbell press. Rejecting implements generically would need per-machine "designed implement" data, which is what `heroExerciseId` is; the test fails if a barbell station loses its curated id, and also fails if the generic rule starts picking the barbell press by itself (so the curation can then be removed).
- `mobile/test/features/scanner/scanner_match_navigation_test.dart`: the `confident` outcome IS reachable (printed-text anchor), so no call site was removed. A new test forces a confident result (fake controller) and covers the locked card button and the runner-up rows; each asserts the scan id is forwarded, and the history chip asserts it is not. The alternatives call site is covered by the first test. Dropping `fromCurrentScan: true` on any of the three sites fails a test.
- `mobile/test/features/visual_equipment/canonical_machine_catalogue_contract_test.dart` and the hero contract test no longer depend on the working directory: they locate the `mobile` package by walking up to its pubspec (`name: fitness_app`) and reach `functions/` from there.

### Verification state
Focused Flutter run from `mobile/` of 16 files, 327 tests, all passed. `functions/src/__tests__/ai_exercise_generation.test.ts`: ran after `npm ci --prefix functions` (setup only; `node_modules` is not tracked): 33 of 33 passed, including the three `EQUIPMENT_NAMES_EN/RU parity with the live mobile assets` cases that check the `bench_press` rename.
NOT verified: poster appearance on a device; the working-directory helper was exercised only from the package root (the only place `flutter test` runs); several generic (uncurated) picks remain plausible rather than ideal and are now pinned, not endorsed.

## Addendum 3: confirmation experience (candidate pictures, 3 alternatives, manual picker)

### What changed
- `functions/src/ai_equipment_recognition.ts`: the prompt now asks for exactly 3 alternatives (the 3 most plausible OTHER machines, ordered by confidence) instead of "up to 2 only when genuinely plausible". `maxOutputTokens` stays 256 (best + 3 is about 100 tokens). Test: `functions/src/__tests__/ai_equipment_recognition.test.ts` (new prompt assertion).
- `mobile/lib/features/visual_equipment/data/visual_equipment_service.dart`: `kScanCandidateCount = 4` (best + 3). The controller asks the service for it, and the cloud service's `classifyFile`/`parseResponse` defaults use it, so `rankTopK` no longer cuts the 4th candidate.
- `mobile/lib/features/scanner/widgets/machine_thumb.dart` (new): each candidate row shows the machine's hero image (`equipmentHeroImageProvider`), or a neutral gradient icon tile when there is none.
- `mobile/lib/features/scanner/widgets/manual_machine_picker.dart` (new): "Not it - choose manually" row at the end of the candidate list opens a searchable list of ALL catalogue machines (localised names, thumbnails). Search matches the display name and any alias (`EquipmentAliasIndex.idsMatching`, new).
- Picking a machine opens `/equipment/<id>` (without this scan's id, because the scan described a different answer) and records it through the same `_remember` path with the new `RecognitionSource.manual` and confidence 1.0. A tapped candidate is still the user's own identification, unchanged.
- l10n (RU + EN): `scannerNotThisPickManually`, `scannerManualPickerTitle`, `scannerManualPickerSearchHint`, `scannerManualPickerNoResults`.

### Why
Measured on 33 labelled photos (`core/ml/eval`): model top-1 is 16/33 and the right machine is in the top 3 alternatives for 20/33; prompt variants (thinking, chain of thought, 2048px) did not help. The operator should not have to guess: every answer is a candidate list, the rows are recognisable by picture, and there is always a way out when the machine is not listed.

### Limits (read before relying on this)
- This does NOT raise model accuracy. It makes correction one tap.
- The 3-alternatives prompt only takes effect after the Cloud Function `aiEquipmentRecognition` is DEPLOYED. The deploy has NOT been done. Until then the app still works but receives the old 1 + up to 2 answer (the extra row space is simply unused).
- The pictures are the posters of the clips that demonstrate each machine (5 machines have none and show the neutral tile); they are not photos of the real gym equipment.
- `RecognitionSource.manual` is a new persisted value; an older build reading it gets `null` source (already handled by `recognitionSourceByName`).

### Verification state
Jest `ai_equipment_recognition.test.ts`: 22 of 22. Flutter, focused, from `mobile/`: new `scanner_manual_pick_test.dart` (5 tests: thumbnails + names + confidence + topK 4; order of 4 candidates and manual row last; "жим" finds `Жим лёжа (стойка)`, opens `/equipment/bench_press` without scanId and remembers a manual pick at 1.0; alias search and empty state; dismissing files nothing), `scan_controller_test` (topK 4), `gemini_equipment_service_test` (best + 3 kept in order, fifth cut), and the neighbouring scanner, history and l10n suites. NOT verified: appearance on a device, the deployed prompt's real effect on accuracy.

## Addendum 4: full-screen scan window with a draggable result sheet

### What changed
- `mobile/lib/features/scanner/scanner_page.dart`: the camera preview now fills the whole Scan area edge to edge (status bar to bottom nav) instead of a 230px card. The title is drawn over the camera (dark HUD tokens plus a soft scrim). Everything else lives in a `DraggableScrollableSheet` over the preview, above the bottom nav (`shellBottomObstruction`).
- The collapsed sheet (`kScanSheetCollapsedPx`) is a pinned header: drag handle, the primary shutter button ("Распознать"), the Gallery / Live row and the cloud-upload disclosure (the claim the user consents to when tapping the shutter is never scrolled away). Below it scrolls the answer: locked card, candidates with "choose manually", last-session memory, AI coach entry, notes, identity badge, "My machines", preparing cards.
- A scan that ends (any answer, including "could not tell what that is") opens the sheet to 60% by itself; "Scan again" collapses it. The live reading (Live mode) rides just above the sheet over the preview, wherever the sheet is.
- `mobile/lib/features/scanner/widgets/scan_viewfinder.dart`: `fullBleed` (no card chrome, dark bracket inks) and `guideInsets` (brackets, glyph and hint sit clear of the title and of the collapsed sheet). `windowNormalized(card, guideInsets:)` makes the capture crop exactly the frame the user aimed through.
- Tests: `mobile/test/features/scanner_page_test.dart` rewrote the three retired card-layout tests as full-screen tests (preview == screen rect; title over the camera and frame clear of title and sheet; collapsed sheet holds shutter, Gallery, Live and is 226px; fling opens and closes the sheet; the crop window includes the insets; an answer opens the sheet and Scan again collapses it) and moved the low-light banner and "My machines" tests to the new layout.

### Retired tests (decision, not deletion)
`mobile/test/features/scanner/scan_reference_geometry_test.dart` (3 groups) and `mobile/test/golden/scan_reference_golden_test.dart` (2 groups per theme) measure the 230px reference-card layout. The operator ordered the full-screen window, so they are marked `skip:` with the reason; the reference widgets (`ScanViewfinder` card mode, `ScanMatchCard`) are unchanged. Goldens and `tools/design/scan_fidelity_check.py` therefore no longer describe the Scan screen.

### Limits
- Not verified on a device: sheet feel, overlap with the real bottom nav, brackets vs real camera aspect, title legibility on bright scenes.
- The sheet opens by a jump, not an animation (deterministic under test, and the answer is readable the moment it lands).
- `test/theme/app_semantic_colors_test.dart` "hardcoded whites" tripwire currently reads 70 against a pinned 69: the extra white is in the coach files committed by the parallel coach-form work, not in this change (the thumbnail bed uses a named constant, not `Colors.white`).

### Verification state
Focused Flutter run from `mobile/`: `scanner_page_test.dart` 55 of 55, `test/features/scanner/*` (navigation, manual pick, identity visibility, scan-id cleanup, strip overflow, frame), `machine_card_flow_test.dart`, `test/shared`, `test/l10n`: all passed, 15 tests skipped as retired (above).

## Addendum 5: camera zoom presets and pinch

### What changed
- `mobile/lib/core/camera/camera_zoom.dart` (new): `CameraZoom` owns the open camera's zoom range and level. Presets are 0.6, 1, 2, 3, 5, 10x and only those inside the device's real min/max are offered; 0.6x only when the device reports a minimum of 0.6 or less (an ultra-wide lens; 0.5999 counts, 0.7 does not). Every level is clamped to the device range before it reaches the camera. A pinch produces a level per frame, so `requestLevel` keeps one call in flight and only the latest waiting level. `ZoomBackend` is the seam: the real one wraps the plugin `CameraController`, tests supply a fake with any min/max.
- `mobile/lib/core/camera/camera_session.dart`: the session publishes the range after the camera opens (it still opens at the widest zoom, as before) and clears it on stop or a failed start; `session.zoom` is the one handle.
- `mobile/lib/features/scanner/widgets/zoom_controls.dart` (new): a small current-zoom label plus one chip per preset, the active one highlighted, over the preview just above the sheet; `ZoomPinchLayer` adds two-finger pinch over the preview (a one-finger drag does nothing). Hidden while no camera is open, for a fixed-zoom camera, and while the camera is blocked.
- `mobile/lib/features/scanner/scanner_page.dart`: wires both in; leaving the screen resets zoom to 1x before the camera is released.
- Tests: `mobile/test/features/scanner/scan_zoom_test.dart` (17: presets for 0.6..10 and 1..4 devices and the 0.6 rule, clamping, reset, no camera, coalescing, chips and highlight, pinch ratio, pinch clamped at both ends, one finger ignored), `mobile/test/helpers/fake_zoom_backend.dart`, and four page tests in `scanner_page_test.dart` (presets per device on the real screen and reachable above the sheet, tap zooms, leaving resets to 1x, none when the camera is blocked).

### Limits
- Not verified on hardware: whether a given phone's plugin reports 0.6 as the minimum (the logical camera must expose the ultra-wide lens), how smooth the pinch feels, and that the picture actually changes (the fake proves the calls, not the optics).
- The session still opens at the widest zoom the device reports (existing behaviour), so on an ultra-wide phone the first preview is at 0.6x; only leaving the screen resets to 1x as ordered.

### Verification state
Focused Flutter run: `scan_zoom_test.dart` 17/17, `scanner_page_test.dart`, `test/features/scanner/*`, `test/l10n`: all passed (7 retired skips from Addendum 4).

## Addendum 6: automatic on-phone scan history (storage layer)

### What changed
- `mobile/lib/features/scanner/history/scan_record.dart`, `scan_history_store.dart`, `scan_history_providers.dart` (new). Every scan is saved automatically, ON THE PHONE ONLY, in `<docs>/scan_history/<uid>/<scanId>/` (`record.json` + `photo.jpg`). One record holds: timestamp (UTC), source (camera / gallery / live), outcome, who answered (cloud / on-device fallback / printed text / nobody), the model's raw reply verbatim, every candidate in the order shown with its confidence and the user's optional rating (ok / not ok / none), which machine the user opened or chose by hand, and the app build (git sha, version). The photo is the same resized JPEG the cloud was sent (`resizeForCloud` is deterministic on the classified file). Live readings are recorded without a photo, under the same 5-minute throttle as "My machines". Scans that ended in a timeout, a failure or "could not tell" are recorded too.
- Retention: the newest 500 scans or 1 GiB, whichever is hit first, per account; the scan just saved always survives. `clear(uid)` is the "Clear history" action (UI in the next step). Writes are serialised and `record.json` is replaced atomically; folder deletes retry briefly (Windows/antivirus handle locks).
- Raw answer plumbing: `RawAnswerReporting` (like `FallbackReportingRecogniser`) on the cloud and hybrid recognisers, and `ScanResult.rawAnswer`; no screen renders it.
- `mobile/lib/features/scanner/scanner_page.dart`: saves after every classification (fire and forget, never throws into recognition), records the opened candidate and the manual pick against the scan. A rating or choice made before the photo has been written waits for the record instead of being lost.
- Wipe: `DeviceLocalDataWipe` now deletes `<docs>/scan_history/<uid>/` (own try block, reported as `scan_history` in `LocalWipeIncomplete`). Another account's history is untouched.
- Backup: `backup_rules.xml` and both sections of `data_extraction_rules.xml` exclude `app_flutter/scan_history`; `backup_rules_test.dart` now expects five exclusions, ties the excluded name to `kScanHistoryDir`, and checks the wipe path and the inventory entry.
- Inventory: `core/DATA_INVENTORY_2026-08-11.md` (device files table plus a backup paragraph) and `.csv` document the new data class.

### scripts/ci/data_lifecycle_policy.json
Not changed on purpose. That file classifies Firestore collections only (retention and access axes) and its checker reports any entry it cannot discover in `firestore.rules` or in production `.collection(...)` calls as stale; this data class never touches Firestore. The device-only class is recorded in the inventory and pinned by `backup_rules_test.dart` and `scan_history_store_test.dart` instead. (The checker itself was not run: the project rules allow only focused tests.)

### Limits
- Stored in the clear (app-private sandbox, no encryption at rest), because the operator must be able to export it readable; excluded from backup and device transfer and wiped with the account. The progress-photo AES store was not reused: its key is bound to the photo directory and an encrypted export would be unreadable.
- Not uploaded by the app. Whether a user-initiated export leaves the phone is the user's choice (next step).
- `backup_rules_test.dart` "pubspec.lock pins the plugins" fails in this checkout with `shared_preferences missing from pubspec.lock` although the lock contains it; it does not touch anything changed here and was failing before this change was made (not investigated further).

### Verification state
Focused Flutter run from `mobile/`: `scan_history_store_test.dart` 30/30 (record content, rating persistence and clearing, serialised writes, retention by count and by bytes, wipe, export, recorder incl. cloud and on-device fallback records), `scanner_history_flow_test.dart` 6/6 (cloud scan, on-device fallback scan, failed scan, opened candidate, manual pick, two scans through the real ScannerPage), `account_deletion/*`, `scan_controller_test`, `gemini_equipment_service_test`, `scanner_page_test`: green; `backup_rules_test.dart`: 10 of 11 (the lock test above fails).

## Addendum 7: optional OK / NOT OK marks, scan history screen, export, clear

### What changed
- `mobile/lib/features/scanner/widgets/rating_marks.dart` (new): two small marks (check = OK, cross = NOT OK) on each candidate row right after the "% confidence" text, and under the locked card. Optional: nothing depends on them, tapping the active mark again clears it, a mark swallows its own tap (rating a row does not open it), a new scan starts with no marks. A rating is written to the scan's saved record (`ScanHistoryRecorder.rate`, which waits for the record if the photo is still being written).
- `mobile/lib/features/scanner/history/scan_history_page.dart` (new): "История сканов" screen (RU) / "Scan history" (EN). List newest first of this account's scans with thumbnail (the saved resized photo, a neutral tile for live readings), top candidate name, time, source, who answered (cloud / on-device fallback / printed text / no answer) and the rating marks given. Detail page: photo, every candidate with editable marks, what the user opened or chose by hand, the model's raw reply (selectable), app build and git sha. Entry: a history button over the camera (top right of the Scan screen); routes `/scan-history` and `/scan-history/:id` are top-level, so the camera is released while they are open.
- Export: one JSON (`scan_history.json`, every record with its app build and the relative photo path) plus a `photos/` folder, written to app temp storage and handed to the system share sheet (`share_plus` is already a dependency). The share sheet is the only way the history leaves the phone, and only after the user taps Export. A failure shows a message and keeps everything.
- "Очистить историю" / "Clear history": confirm dialog (cancel deletes nothing), then deletes this account's scans and photos only.
- l10n RU + EN (parity tests green): 23 new keys (`scanRateOk`, `scanRateNotOk`, `scanHistory*`).

### Limits
- Export is plaintext on purpose (the operator compares it by hand); the exported files sit in app temp storage until the OS clears it. There is no zip (no archive package is a dependency): the JSON and the photos are shared as separate files.
- Ratings of a scan can be changed later only from the history detail or from the live result list while that scan is still on screen.
- Not verified on a device: the real share sheet, the look of the history screen, thumbnails of large histories (decoded at 2x thumbnail size).

### Verification state
Focused Flutter run from `mobile/`: `scan_history_page_test.dart` 6/6 (list, empty state, detail and rating there, export content, share failure, clear with cancel/confirm), `scanner_history_flow_test.dart` 10/10 (4 new for the marks: both marks per row after the %, OK / NOT OK saved and cleared by tapping again without opening the machine, optional, no carry-over to the next scan), `scanner_page_test.dart` 60/60 (history button opens the screen and releases the camera), plus l10n, scanner, router, account-deletion suites.

## Addendum 8: privacy-review fixes for the scan history (export copy, wipe race, per-account cap)

### What changed
- Plaintext export copy: `ScanHistoryStore.export` writes `<temp>/scan_history_export/` (named by `kScanExportDirName`). `ScanHistoryPage._export` now deletes that folder in a `finally` as soon as the share call returns, on success and on failure. `ScanHistoryStore.clear(uid)` ("Clear history") and `DeviceLocalDataWipe` (account deletion) delete it too, so it cannot outlive the history it was copied from. The store takes a `temporary` directory resolver (default `getTemporaryDirectory`) so tests use a real temp folder.
- Same-uid race: `ScanHistoryStore.wipeAccount(uid)` runs inside the store's serial queue, deletes `scan_history/<uid>` and remembers the uid; after that `save`, `setRating` and `setChoice` for that uid return null and write nothing, so a scan whose photo was still being resized when the account was deleted can no longer recreate the folder. `DeviceLocalDataWipe(scanHistory: ...)` goes through it; `main.dart` passes the live store. Without a live store (headless sweep) the folder is deleted directly as before. Only an account wipe locks a uid for the process lifetime; the user's own "Clear history" does not.
- When only the documents folder is injected into `DeviceLocalDataWipe` (tests), the temp folder defaults to `<docs>/_temp`, so no test reaches the real platform temp directory.
- Inventory: `core/DATA_INVENTORY_2026-08-11.md` and `.csv` state that the 500 scans / 1 GiB cap is PER ACCOUNT and describe `<temp>/scan_history_export/` honestly (plaintext, temp storage, deleted after share / clear / wipe). `backup_rules_test.dart` pins those statements.

### Limits
- On Android the share target may read the file after `Share.shareXFiles` returns; deleting right then can cut a very large export short for the receiving app. Accepted: a plaintext copy lingering in temp storage is the worse failure, and the user can export again.
- A crash between writing the export and the `finally` leaves the folder until the next export, "Clear history" or the account wipe.
- The wipe lock is in memory: after a process restart a late in-flight save cannot exist any more (the save belongs to the dead process).

### Verification state
Focused Flutter run from `mobile/`: `scan_history_store_test.dart` (now includes export-then-clear leaves no temp folder, wipe removes the export copy with and without the live store, a deferred save reaching the store after the wipe leaves no `scan_history/<uid>`, a save queued behind the wipe is deleted by it, rating/choice after the wipe are dropped, another account stays writable), `scan_history_page_test.dart` (export copy gone after a successful share, and after a failing share), `scanner_history_flow_test.dart`, `local_data_wipe_test.dart`, `account_deletion_journey_test.dart`, `interrupted_wipe_test.dart`, `account_deletion_providers_test.dart`: 124/124 passed. `backup_rules_test.dart`: 10/11, the one failure is the pre-existing "pubspec.lock pins the plugins" check (`shared_preferences missing from pubspec.lock`), untouched by this change. Not run: analyzer, full suites, a real device share sheet.
