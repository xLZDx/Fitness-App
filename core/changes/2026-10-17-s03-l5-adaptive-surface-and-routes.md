# S03 lane L5: adaptive surface and S03 routes

Date: 2026-10-17. Kind: production code (UI, routing), story S03-06.

## What changed
- mobile/lib/shared/widgets/adaptive_surface.dart (new): `AdaptiveSurface.show`, one route for bottom sheet, popover and dialog that re-evaluates the placement from the live window class, focus return, Esc and scrim close, open-surface depth counter reset on account change.
- mobile/lib/core/router/s03_routes.dart (new): path constants, `/mode-questions/:mode` guard (unknown or unavailable mode redirects to Home with no write), no-transition page builder for reduced motion, three stub pages.
- mobile/lib/core/router/app_router.dart: two imports and one splice `...buildS03Routes(availability: ...)` before the shell route.

## Why
Story S03-06 (design 2.6, RV-9, RV-15): every surface is a route so that Back and Esc close it and a resize re-places it; the new pages get their routes once, so later lanes never touch the router.

## Affected contracts and paths
Adds the routes `/mode-chooser`, `/mode-questions/:mode` and `/sources` (stubs until lanes L6 and L9). Existing routes are untouched.

## Verification state
Nothing was run. The tests (DT-06-x, DT-09-6) are written and run by the test agents after epic 6; until then NOT_RUN.
