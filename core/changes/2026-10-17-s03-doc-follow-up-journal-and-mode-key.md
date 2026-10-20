# S03 documentation follow-up: journal tree and mode key

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md: new rows for the local activity journal (on by default, per-account tree, excluded from Android backup and device transfer) and for the mode state key; the status paragraph and one gap row point to the implemented exclusion.
- core/DATA_INVENTORY_2026-08-11.md: SharedPreferences row for activity.mode.v1.<uid> and a Files row for the journal tree.
- mobile/IOS_PERMISSIONS_TODO.md: real directory names, four-entry exclusion list, Apple marking requirement for any Apple build target.

## Why
Follow-up RV-17 of the S03 design review: the documents named directories that do not match the code and did not know the mode key.

## Affected contracts and paths
None in code.

## Verification state
Documentation only; nothing was run. Two matrix cells are marked INFERENCE (see the lessons entry).
