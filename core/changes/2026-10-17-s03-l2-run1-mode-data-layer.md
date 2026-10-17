# S03 lane L2 run 1: mode state data layer

Date: 2026-10-17. Kind: production code (data layer), story S03-01.

## What changed
New files under mobile/lib/features/modes/data/:
- mode_models.dart: `AppMode`, `ChooserStatus`, `ModeAvailability`, `ModeAnswer`, `ModeState`, the three-way `ModeRead`, `ModeWriteResult`, the default availability table.
- mode_codec.dart: `encodeModeState` and `decodeModeState`; the decoder never throws; corrupt, unknown shape and newer version map to an unreadable result, never to an empty state.
- mode_store.dart: `ModeStore` and `PrefsModeStore` over SharedPreferences, key `activity.mode.v1.<uid>`, with the fail-closed wiped-uid refusal (before and after the await, and removal of a key written while the account was being wiped).

## Why
Story S03-01 (design 2.2, 5.1 to 5.3): per-account mode state that survives restarts, is never silently overwritten when unreadable, and is not resurrected after account deletion.

## Affected contracts and paths
Adds a new SharedPreferences key family (`activity.mode.v1.<uid>`) that the existing account-deletion wipe already removes by prefix and suffix; no existing file is changed. Nothing uses the data layer yet; run 2 adds the notifier, the migration and the warm-up provider, run 3 the onboarding hook and the main.dart watch.

## Verification state
Nothing was run. The tests (DT-01-x) are written and run by the test agents after epic 1; until then NOT_RUN.
