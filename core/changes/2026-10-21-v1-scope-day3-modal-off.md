# Change record: Day-3 welcome modal off in v1 (2026-10-21)

## What changed
- `mobile/lib/features/moments/state/moment_providers.dart`: new `day3WelcomeModalEnabledProvider` (default false).
- `mobile/lib/features/home/home_page.dart`: after the Day-3 eligibility check the Home screen returns without showing `Day3WelcomeModal` unless the provider is true. Launch counting still runs, and the `finally` block still marks the Day-3 step settled and offers the mode chooser.

## Why
Operator decision of 2026-10-21. The modal is entirely a Supporter-subscription ask ("See ways to support" opens /subscription), and the donor wall is login-only in v1. The second moment, `firstInjuryFilter`, has no consumer anywhere in `mobile/lib` (only its own unit test), so there is nothing to hide. Code and strings are kept; rollback is one provider default.

## Affected contracts and paths
Home Day-3 flow only. `shouldShowDay3Welcome` and the moment repository are unchanged. Because the modal is never shown, `markShown(day3Welcome)` is not written either.

## Verification state
Not run by the author. `test/features/modes/mode_chooser_test.dart` DT-08-9 expects the modal and must override the provider to true; a new test must prove the default (no modal, chooser offered).
