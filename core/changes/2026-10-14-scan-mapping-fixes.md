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
