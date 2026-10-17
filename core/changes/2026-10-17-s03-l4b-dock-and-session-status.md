# S03 lane L4b: dock widgets and active session status

Date: 2026-10-17. Kind: production code (UI, state), story S03-07.

## What changed
- mobile/lib/features/workouts/state/active_session_status.dart (new): `ActiveSessionStatus`, `ActiveSessionOwner`, the derivation from the set and rest timers, the owner controller, the test seam for the driven timers.
- mobile/lib/shared/widgets/dock_widgets.dart (new): `RecordPill`, `RecordingStrip`, `RailRecordSlot`, `openActiveSessionDestination`.
- mobile/lib/features/equipment/workout_player_page.dart: owner capture before the two rest-timer starts and on the set-timer start transition, destination parameter on two private buttons.

## Why
Story S03-07 (contract S-4, RV-4, RV-8): a running workout stays reachable from every tab without the timers being touched, and never shows to a different account.

## Affected contracts and paths
The timer providers are read-only; no `autoDispose` was added. The new widgets use ARB getters that lane L13 adds; until then the widget file does not compile.

## Verification state
Nothing was run. The tests (DT-07-x) are written and run by the test agents after epic 7; until then NOT_RUN.
