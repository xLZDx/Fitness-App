# S02-08 change record: data lifecycle matrix updated to the implemented behaviour

Date: 2026-10-16. Story: S02-08 (design 6 "DATA_LIFECYCLE_MATRIX.md" row; GPS-PRIV-004; test id F43).

## What changed

`docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md`:
- C1 (cloud, retained, exported, deleted cells), C2 and C8 rewritten from "per D-16 / none" to the implemented behaviour: private canonical object, user-set expiry derived at purge time, download links instead of body export, heart rate never in the cloud.
- Section 2 debug-sessions row: closed-schema callable is the only writer, client create is NONE, Phase 1 behaviour change recorded.
- Section 3 sweep map: the `activities` row marked implemented; new rows for `activity_streams`, `activity_settings`, `activity_tombstones`, the two top-level server-only documents; the `streams/` row now also covers `quarantine/`.
- New "Status after S02" paragraph under section 4 listing resolved and still-open gaps.

## Why

Matrix maintenance rule (section 5): the sprint that adds a collection or Storage path updates the matrix in the same PR.

## Deviations

The default expiry value, the "never" option and whether C2 may differ from C1 remain OPEN operator decisions (design 12.3); the cells say so instead of recording them as decided. Section 4 gap rows are left as written (history); resolution is stated in the new status paragraph.

## Verification state

No checks were run. F43 is a string check by the test agents.
