# S03 lane L9 run 2: sign-out guard and Sources completion

Date: 2026-10-17. Kind: production code, stories S03-15 and S03-16.

## What changed
- mobile/lib/features/activity/state/sign_out_guard.dart (new): `confirmSignOutWithLocalData`.
- mobile/lib/features/activity/widgets/sign_out_warning_sheet.dart (new): the four sheets.
- mobile/lib/features/profile/profile_page.dart: the sign-out tile calls the guard before signing out.
- mobile/lib/features/modes/pages/sources_page.dart: recovery-loss line, May-provide lines, no Try again for failedToOpen.
- mobile/lib/core/router/s03_routes.dart: the Sources route uses the real page.

## Why
Stories S03-15 and S03-16 (design 2.5, F-19, F-42, F-45, RV-12, RV-16): local activity must never be lost or hidden silently at sign-out.

## Affected contracts and paths
Profile sign-out now asks before it signs out when local activity exists or cannot be checked. Account deletion is unchanged.

## Verification state
Nothing was run; NOT_RUN until the test agents (epic 4 and the sign-out guard tests).
