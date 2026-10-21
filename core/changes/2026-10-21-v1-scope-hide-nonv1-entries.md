# Change record: hide non-v1 entries and close /donors (2026-10-21)

## What changed
- `mobile/lib/core/router/app_router.dart`: `/donors` removed from `_publicPaths` (the donor wall now requires a signed-in user); `/coaches` and `/coaches/...` added to `isDemoGatedPath`, so a release build redirects them to `/home` like the other demo routes.
- `mobile/lib/features/profile/profile_page.dart`: the whole Coaching section (coach marketplace tile and celebrity plans) is shown only when `kDemoFeaturesEnabled` is true.

## Why
Operator decision of 2026-10-21 (independent review of the FitnessUp v1 rebaseline): the coach marketplace (Stripe Connect via Cloud Functions), social feed, celebrity plans and community are outside the nine v1 areas; `/donors` becomes login-only. `buddy` and `sdk_export` are not wired anywhere and stay in code, deferred. Nothing is deleted. The moments notifications are not touched (open decision).

## Affected contracts and paths
Router redirect contract and the Profile screen only. Provider overrides in `main.dart` are unchanged. `about_page.dart` still shows the donor-wall button; a signed-out visitor who taps it is redirected to `/login`.

## Verification state
Not run by the author (coding phase). Existing tests that pin the old behavior must be updated by the test agents: `test/router/app_router_gating_test.dart` (lines ~77, 94, 187-188, 359-360), `test/router/app_router_test.dart` (~176) and `test/router/back_navigation_test.dart` (~119, 185-198).

## Follow-up (same day)
`profile_page.dart` now reads `demoFeaturesEnabledProvider` instead of the compile-time constant `kDemoFeaturesEnabled`, so the release-build behavior (no Coaching or Community section) can be driven by a widget test. Behavior with the default provider value is unchanged. Test for the flag-off Profile screen is owed by the test agents.
