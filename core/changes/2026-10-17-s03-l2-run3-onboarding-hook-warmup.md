# S03 lane L2 run 3: onboarding hook and warm-up watch

Date: 2026-10-17. Kind: production code (wiring), story S03-01.

## What changed
- mobile/lib/features/onboarding/onboarding_page.dart: after a successful profile submit and before `context.go('/home')`, an awaited `initIfAbsent(InitSource.onboarding)` call in try/catch with mounted checks.
- mobile/lib/main.dart: one import and `ref.watch(modeWarmUpProvider);` in `FitnessApp.build`.

## Why
Story S03-01 (design 2.2, RV-1, RV-18a): a new user must get the mode chooser exactly once, the writer of the first chooser status is a single atomic function, and the mode state plus the migration start before the first frame.

## Affected contracts and paths
The onboarding flow gains one awaited call that cannot block it. `/onboarding/edit` for an onboarded user stays a no-op. No timer provider watches the mode state.

## Verification state
Nothing was run. The tests (DT-01-x, F-7) are written and run by the test agents after epic 1; until then NOT_RUN.
