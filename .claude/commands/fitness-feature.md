---
description: Scaffold a new feature following this repo's exact layout convention, then wire its route
---

Add a feature named `$ARGUMENTS` without inventing a new structure. Every existing feature follows
the same shape — match it, so the next reader (and `core/CODEMAP.md`) can predict where things are.

Full rule set: `core/CONVENTIONS.md`. The steps below are the applied version of it.

## 1. Confirm the name is free

Check `core/CODEMAP.md` and `mobile/lib/features/` — 33 features already exist. Reuse an existing
one if the capability belongs there rather than creating a near-duplicate.

## 2. Create the layout

```
mobile/lib/features/<name>/
    <name>_page.dart      UI entry point — ONLY if the feature has a screen
    data/                 models, repositories, pure logic — no Flutter imports
    state/                Riverpod providers
    widgets/              feature-local widgets
```

Create only the directories you actually need. Twelve existing features are logic-only (no page) —
`voice`, `buddy`, `cycle_aware`, `body_comp`, ... — so a feature with no screen is normal, not an
omission.

Start each data-layer file with a doc-comment naming the ticket ID and what the module does,
matching the existing style:

```dart
/// TX.3 — Buddy Matching.
///
/// In-gym presence sharing via BLE: two phones in the same building ...
```

That convention is what makes `core/CODEMAP.md` describable without reading every file — keep it.

## 3. Wire the route (only if there is a page)

Add to `mobile/lib/core/router/app_router.dart` — **all** routes live there, none are declared
elsewhere. Decide deliberately whether it belongs inside `MainShell` (bottom nav — currently
`/home`, `/scan`, `/workouts`, `/progress`, `/profile`) or is pushed full-screen.

## 4. Respect the cross-cutting rules

- **iOS portability**: no Android-only APIs in shared code; any health data goes through
  `lib/core/health/health_service.dart`, never a platform API directly.
- **Design system**: reuse `lib/shared/widgets/` (`glass.dart`, `aurora_background.dart`) and take
  colours from `lib/core/theme/app_palette.dart` — do not re-implement the glass look.
- **Injury filtering**: if the feature surfaces exercises, they must pass through
  `lib/features/equipment/data/exercise_filter.dart`. This is a safety rule, not a style one.

## 5. Test the logic

Add tests under `mobile/test/` for anything in the feature's data layer — pure logic is the cheap
place to test. There is no `integration_test/` directory in this repo.

## 6. Update the map, then verify

Add the feature to the tables in `core/CODEMAP.md` (route table if it has a route, plus the feature
table with file/line counts and purpose) in the **same commit**. The link audit cannot catch a
feature you forgot to document.

Then run `/fitness-verify`.
