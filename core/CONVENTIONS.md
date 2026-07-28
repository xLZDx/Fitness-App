# Engineering conventions

The rules a change is reviewed against. Previously these were scattered across `CLAUDE.md`, the
reviewer agent and the feature command; this is now the single source they all point at.

## Feature layout

```
mobile/lib/features/<name>/
    <name>_page.dart      UI entry point — only if the feature has a screen
    data/                 models, repositories, pure logic — NO Flutter imports
    state/                Riverpod providers
    widgets/              feature-local widgets
```

All 33 features follow this, so a path can be guessed safely. Twelve features are logic-only (no
page) — that is a valid shape, not an unfinished one.

Keep the data layer free of Flutter imports: it is the cheap place to unit-test, and that property
is worth protecting. Start each data-layer file with a doc-comment naming its ticket ID and purpose
(`/// TX.3 — Buddy Matching.`) — that convention is what lets `core/CODEMAP.md` describe modules
without anyone reading them.

## State and routing

- **Riverpod** for state (`flutter_riverpod`). Providers live in `state/`, never created inside
  `build()`. Reach for `setState` only for genuinely local widget state.
- **go_router** for navigation, with **every** route declared in
  `mobile/lib/core/router/app_router.dart`. Five routes sit inside `MainShell` (bottom nav):
  `/home`, `/scan`, `/workouts`, `/progress`, `/profile`. Everything else is pushed full-screen.

## Cross-platform — design for iOS even though Android ships first

This is a standing project rule, not a preference. Every package and abstraction choice must
accommodate iOS from day one:

- Prefer packages declaring **both** `android` and `ios` support in `pubspec.yaml`.
- No Android-only API references in shared code.
- Health data goes through the `HealthService` interface
  (`mobile/lib/core/health/health_service.dart`) — that is the Health Connect ↔ HealthKit seam and
  is load-bearing. Never call a platform health API directly.
- Wear OS ships first, Apple Watch later — keep phone-side wear comms a generic interface.
- Material everywhere for now; Cupertino-style fallbacks (date pickers, switches, action sheets)
  get switched in selectively when iOS spins up.
- App Store IAP is planned alongside Stripe: `SubscriptionAction` is the abstract surface, with a
  `StoreKitCheckoutService` to sit beside `CloudFunctionsStripeService`.

## Design system

Shared visuals live in `mobile/lib/shared/widgets/` — `glass.dart`, `aurora_background.dart`,
`glass_nav_bar.dart`, `main_shell.dart`. Reuse them rather than re-implementing blur/glass effects.
Colours come from `mobile/lib/core/theme/app_palette.dart`, not hard-coded values.

## Injury filtering is a safety requirement

Any code path that surfaces exercises to a user must pass through
`mobile/lib/features/equipment/data/exercise_filter.dart`. Injury-aware filtering is the product's
core differentiator *and* a safety property — an unfiltered exercise list reaching a user with a
logged contraindication is a defect, not a style issue.

## Testing

- `mobile/test/` (71 files) is the **only** suite. There is **no** `mobile/integration_test/` —
  `flutter test integration_test` fails, and `scripts/dev/run_tests.ps1 -Integration` has nothing
  to run. If you add integration tests, create the directory and update this file, `CLAUDE.md` and
  `AGENTS.md` together.
- `flutter analyze` + `flutter test` after every change; 0 failures required.
- Never state a pass count you did not produce from a run made *after* the current changes.
- UI changes need a build + install on the `Pixel_API_34` emulator and a visual check. Analyze and
  test passing does not prove a screen renders.
- Do a **full restart** when re-testing a running app — a stale process serves old code and yields
  both false passes and false failures.

## Docs that must move with the code

- Add or remove a feature → update the tables in `core/CODEMAP.md` in the **same commit**. The link
  audit cannot detect a feature you forgot to add.
- Move, rename or delete any file a doc names → run `scripts/dev/audit_doc_links.ps1`; it must exit 0.
