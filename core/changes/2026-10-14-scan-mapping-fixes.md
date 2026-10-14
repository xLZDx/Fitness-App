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
