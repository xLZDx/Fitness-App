# S03 lane L2 run 5: persist again after a failed save

Date: 2026-10-17. Kind: production code (state), story S03-01.

## What changed
- mobile/lib/features/modes/state/mode_providers.dart: persist-failed flag and the repeat-write rule for the notifier methods.

## Why
Test plan row DT-09-2: Try again after a failed save must persist, not report unchanged.

## Affected contracts and paths
Return values of the notifier methods are unchanged in the normal case; the repeat after a failure now writes. The main.dart opener overrides follow after lane L6.

## Verification state
Nothing was run; NOT_RUN until the test agents.
