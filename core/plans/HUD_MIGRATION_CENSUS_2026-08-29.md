# HUD migration completion / legacy-glass retirement — fresh census, 2026-08-29

Opened per GPT-PM's explicit scoping of "finish the redesign" after MVP1.G4 closed (see
`core/DECISION_LOG.md`, "G4 closure report published" entry and the immediately following exchange).
Superseded scope: `PLAN_REDESIGN_REMAINDER_2026-08-12.md` (R11b/R11f/R11h/Ф3 against `App.tsx`) is
historical only — `App.tsx` (the Figma-Make prototype) is no longer the target design;
`core/MASTER_PLAN_2026-08-26.md` §3 records HUD Glass as the shipped, superseding design line.

This file is step 1 of GPT-PM's stated DoD for this gate ("fresh inventory... not trusting the old
142"), not the whole gate. It does not commit to a specific per-file migration order beyond the
observation below; sub-gates come from this data, not from mechanically working the list top-down.

## Numbers (measured 2026-08-29, `mobile/lib`, not carried over from any prior doc)

| Metric | Count |
|---|---|
| `GlassCard(` call sites | 126 |
| Files with at least one `GlassCard(` call | 40 (39 real usage sites + `glass.dart`'s own definition) |
| Files importing `shared/widgets/glass.dart` | 45 |
| Files referencing `aurora_background`/`AuroraBackground` | 5 (2 are theme/token files, 1 is the definition file itself — only `main.dart` and `features/equipment/workout_player_page.dart` are real widget-tree usages) |
| Files already using `HudSurface`/`HudPanel`/`HudButton`/`HudChip` | 20 |
| Files with BOTH legacy `GlassCard` and HUD widgets (partial migration) | 3: `home_page.dart`, `scanner_page.dart`, `workouts_page.dart` |

The old `PLAN_REDESIGN_REMAINDER_2026-08-12.md` number (142 `glass.dart` occurrences / 46 files) is
stale and not reused here; these are fresh counts against current HEAD.

## HUD widget catalog (what already exists to migrate onto)

- `shared/widgets/hud/hud_surface.dart` — `HudSurface`, `HudPanel`, `HudButton`, `HudChip`,
  `HudQuality` (an `InheritedWidget` toggling frost/quality by device class), `HudKeyboardActivation`.
- `shared/widgets/hud/hud_scaffold.dart` — `HudScreenBody`, `HudScrollFade`, `HudScreenTitle`,
  `HudSectionHeader`, `HudNavBar`/`HudNavItem`.
- `shared/widgets/hud/hud_metric.dart` — `HudRing`, `HudRingLabel`, `HudProgressTrack`,
  `HudZoneBar`, `HudMetricRow`, `HudToggle`, `HudSettingRow`.
- `core/background/hud_sky.dart` — `HudSkyBackground`, `HudSkyScope`, `HudBackgroundProfile`,
  `HudSkySelection` (the background system `aurora_background.dart` is being retired in favor of).
- `core/theme/hud_tokens.dart` — `HudGlass`, `HudTokens` (the `ThemeExtension` every HUD widget reads
  from — `context.hud`).

`shared/widgets/glass.dart` (the legacy surface being retired) defines exactly 3 classes:
`GlassCard`, `GlassAppBar`, `FrostedScaffold`.

## A real design question found in the first file inspected, not a rubber-stamp finding

`workouts_page.dart` is one of the 3 partially-migrated files — every panel in it already uses
`HudPanel`/`HudChip` except one: a bottom sheet (`_ProgrammeSwitchConfirmSheet` or equivalent,
~line 1720) that deliberately keeps `GlassCard(floating: true, ...)`. The surrounding comment is
explicit about why: *"an ordinary GlassCard is translucent, and a translucent card over the
template list this sheet opens on top of would read the list through the confirmation text"* — and
names `difficulty_rating_sheet.dart` as using the same pattern for the same reason.

Checked `hud_surface.dart` for an equivalent opaque/floating mode on `HudPanel`/`HudSurface`: **none
exists today.** This means the remaining `GlassCard` usage in confirm/rate bottom sheets is not
leftover laziness -- it is filling a real gap in the HUD widget vocabulary (an opaque
sheet-over-scrollable-content surface). Per GPT-PM's DoD ("don't do mechanical blind replacement"),
this is exactly the kind of site that needs either (a) a genuine `HudPanel`/new `HudSheet` opaque
variant added to the shared widget library first, then migrated, or (b) classification as
`INTENTIONAL_LEGACY_EXCEPTION` with this reasoning recorded -- not a blind swap to a translucent
`HudPanel` that would silently reintroduce the exact readability bug the original comment describes.

**This is the first concrete finding of the classification pass (DoD item 2), not yet complete for
all 40 files** -- recorded here so it isn't rediscovered from scratch by whichever session continues
this gate.

## Suggested sub-gate order (not yet authorized as a plan/GO -- a proposal for the next session)

1. **Confirm/rate bottom-sheet opacity gap** -- resolve the `HudPanel` opaque-surface question first
   (affects at least `workouts_page.dart` and `difficulty_rating_sheet.dart`; likely others among the
   40 once each is actually read) since every subsequent sub-gate that touches a sheet will hit it.
2. **Finish the 3 partially-migrated files** (`home_page.dart`, `scanner_page.dart`,
   `workouts_page.dart`) -- smallest remaining surface per file, and already HUD-aware, so lowest risk
   to close first and validate the migration pattern end-to-end (incl. real-device check) before
   scaling to the other 37.
3. **`aurora_background` retirement** -- only 2 real usage sites (`main.dart`,
   `workout_player_page.dart`) once the theme/token files are excluded; small, bounded, good second
   proof point.
4. **Remaining ~36 files**, grouped by feature area (equipment/workouts/progress/settings/etc.),
   each its own sub-gate per GPT-PM's explicit guidance not to land one 46-file commit.

## What this file is not

Not a plan with a GO -- no `pm_rosetta_plan`/GPT-PM approval has been sought for a specific
migration order yet. Not a classification of all 40 files (`MIGRATE_TO_HUD` /
`INTENTIONAL_LEGACY_EXCEPTION` / `DEAD_CODE` per file) -- that is the next concrete step, file by
file, not assumed from the aggregate counts above.
