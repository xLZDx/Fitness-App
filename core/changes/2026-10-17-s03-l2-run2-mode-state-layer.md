# S03 lane L2 run 2: mode state layer

Date: 2026-10-17. Kind: production code (state layer), story S03-01.

## What changed
New files under mobile/lib/features/modes/state/:
- mode_flags.dart: `ModeFlags` (compile-time switches for ride and explore, default off) and the availability table (train and body always available, no paywall).
- mode_providers.dart: store, flags and wipe-guard providers, `ModeNotifier` and `modeStateProvider`, `modeChangedProvider` with a broadcast bus, `modeWarmUpProvider` (the single provider the app root will watch), `InitSource`, `ModeSaveResult`.
- mode_migration.dart: `modeMigrationProvider`, the once-per-process-per-uid migration from the first profile value.

## Why
Story S03-01 (design 2.2, RV-1, RV-2, RV-14, RV-18a): one atomic writer of the first chooser status, no overwrite of unreadable stored values, no write for a wiped or switched account, one warm-up provider.

## Affected contracts and paths
Reads `currentProfileProvider`, `authUserProvider` and `accountBeingDeletedUidProvider` read-only. No timer provider is imported or watched (R-M1). Not yet wired: the onboarding hook and the `main.dart` watch are run 3.

## Verification state
Nothing was run. The tests (DT-01-x) are written and run by the test agents after epic 1; until then NOT_RUN.
