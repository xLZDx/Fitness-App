# v1 scope: test update and results (2026-10-21)

Code under test: commit 4745cde1 (`/donors` login-only, `/coaches` demo-gated, Profile Coaching section behind the demo flag). No file under `mobile/lib` was changed.

## Files changed
- `mobile/test/router/app_router_gating_test.dart`: `/coaches` and `/coaches/x` moved from "not gated" to "gated" (pure, `redirectFor`, live router); new tests for `/donors` (signed-out -> `/login`, signed-in onboarded -> reachable and `DonorWallPage` built, signed-in not onboarded -> `/onboarding`); prefix look-alikes `/coachesx`, `/coach` stay ungated.
- `mobile/test/router/app_router_test.dart`: `/donors` removed from the public-path list; new test pinning that it is not public.
- `mobile/test/router/back_navigation_test.dart`: about -> donor wall stacking scenario now runs signed in; new signed-out test asserts `/donors` never shows the donor wall.

## Commands (cwd `mobile/`, Flutter `/d/flutter/bin/flutter`)
- `flutter test --timeout 60s test/router/app_router_gating_test.dart test/router/app_router_test.dart test/router/back_navigation_test.dart` -> +80, all passed
- Per file: gating +36, app_router +33, back_navigation +11, all passed.

## Not verified
- Profile screen with the demo flag off shows no Coaching section: NOT testable. `ProfilePage` reads the compile-time constant `kDemoFeaturesEnabled` directly (no provider), which is always true under `flutter test`. A test needs a product change (read `demoFeaturesEnabledProvider`). The flag-on side is covered by the existing `profile_page_test.dart` (COACHING heading, Coaches tile), which was not re-run.
- No other tests under `mobile/test` reference `/donors`, `/coaches` or the Coaching section in a way that pins the old behavior (grep).

## Addendum: Profile screen (after commit e919f13b)
`ProfilePage` now reads `demoFeaturesEnabledProvider`, so the Profile checks became testable.
- Changed: `mobile/test/features/profile/profile_page_test.dart`, 2 new tests. Flag off: no COACHING heading, no Coaches tile, no COMMUNITY heading or Community tile; YOU/PROGRESS/MEMBERSHIP/APP, Settings and Sign out still present (control). Flag on: COACHING, Coaches, COMMUNITY and Community present.
- Command (cwd `mobile/`): `flutter test --timeout 60s test/features/profile/profile_page_test.dart test/features/profile_page_test.dart` -> +11 all passed (9 in the changed file, 2 in the untouched second file).
- Not verified: the celebrity-plans tile is not asserted by title; the real release build (`kReleaseMode`) is not exercised, only the provider override.
