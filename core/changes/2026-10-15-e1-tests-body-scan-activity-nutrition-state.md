# E1 tests: body-scan data guards, activity, nutrition state, and a flow-machine fix

## What
- mobile/test/features/body_scan/data/plausibility_test.dart
- mobile/test/features/body_scan/data/check_items_test.dart
- mobile/test/features/body_scan/data/face_region_test.dart
- mobile/test/features/body_scan/data/body_scan_flow_machine_test.dart
- mobile/test/features/body_scan/data/body_scan_job_test.dart
- mobile/test/features/activity/data/activity_models_test.dart
- mobile/test/features/activity/data/activity_merger_test.dart
- mobile/test/features/nutrition_plan/data/nutrition_training_state_test.dart
- mobile/test/features/nutrition_plan/data/missing_inputs_test.dart
- mobile/test/features/nutrition_plan/data/nutrition_inputs_test.dart

## Product defect found and fixed (E1 source)
mobile/lib/features/body_scan/data/body_scan_flow_machine.dart, cancel branch.
Cancelling a scan that is verifying in a LOCAL-ONLY context (provisional scan, cloud flag off) emitted
`deleteBodyScan`, although such a scan never created a server document or object (D-52, SCAN-52).
Fix: the delete/mark-pending effect is emitted only when `s.mayHaveUploaded && !c.localOnly`.
Found by body_scan_flow_machine_test (SCAN-52 case); green after the fix.

## Coverage-map verdict (V-LOSE-M / V-LOSE-CAP vs D-39)
The implementation is correct and the map section 3 values are wrong. With the D-39 lose range
(-200 .. +100 kcal around the target) and slider bounds rounded inward:
- V-LOSE-M: target 2007.5, range 1900-2110, slider bounds 1900-2440.
- V-LOSE-CAP (80 kg / 175 cm): bounds 1810-2400, range 1810-1910.
The map is corrected in a separate commit.

## Residual risk recorded
Cancel from `queued` with attempt > 0 emits no delete effect although an earlier attempt may have uploaded an object
(the map SCAN-08 lists only uploading/analysing/verifying). Not changed: it matches the map; flagged for review.

## Verification
- flow machine + activity_models + activity_merger: 356 passed, 0 failed.
- nutrition_training_state + missing_inputs + nutrition_inputs: 98 passed, 0 failed.
- plausibility, check_items, face_region, body_scan_job ran in the same batch as the flow machine; green after the fix.
Final complete run of every E1 file is recorded in the final change record.
