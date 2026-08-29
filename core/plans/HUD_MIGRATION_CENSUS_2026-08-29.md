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
| `GlassCard(` call sites | 126 → 124 after sub-gate 1 → **117** after sub-gate 2 |
| Files with at least one `GlassCard(` call | 40 (39 real usage sites + `glass.dart`'s own definition) → 38 after sub-gate 1 → **37** after sub-gate 2 |
| Files importing `shared/widgets/glass.dart` | 45 → 43 after sub-gate 1 → **42** after sub-gate 2 |
| Files referencing `aurora_background`/`AuroraBackground` | 5 (2 are theme/token files, 1 is the definition file itself, 1 is a comment-only mention in `workout_player_page.dart` — **corrected**: `main.dart` is the ONLY real widget-tree usage, see the struck sub-gate 3 below) |
| Files already using `HudSurface`/`HudPanel`/`HudButton`/`HudChip` | 20 (+ `HudSheet`, the new opaque-surface widget from sub-gate 1) |
| Files with BOTH legacy `GlassCard` and HUD widgets (partial migration) | 3: `home_page.dart`, `scanner_page.dart`, `workouts_page.dart` → 2 after sub-gate 1 → **0** after sub-gate 2 (`home_page.dart` fully migrated; `scanner_page.dart` closed with 2 sites reclassified `INTENTIONAL_LEGACY_EXCEPTION`, not partial-migration debt) |

### Sub-gate 2 — closed, 2026-08-29

Migrated all 7 `GlassCard` call sites in `home_page.dart` (`_AiPlanCard`, `_PostureCheckCard`,
`_SummaryLinkCard`, `_UpcomingCard`, `_SuggestionCard`, `_SuggestionsPlaceholder`,
`_SuggestionsMessage`) to `HudPanel` — all sit on the app's own background as in-page cards, not
over content they don't own, so `HudPanel` (not `HudSheet`) is the correct target. Every site used
only `key`/`onTap`/`padding`/`child`, all of which `HudPanel` accepts 1:1; `GlassCard`'s and
`HudPanel`'s default padding are both `EdgeInsets.all(18)`, and both give an `onTap` card identical
`Semantics(button: true)` wrapping (verified by reading `glass.dart`'s `build()`) -- a behavior-
preserving swap, not a redesign. `glass.dart` import removed; `flutter analyze` clean; existing
`home_page_test.dart` suite green (9/9).

`scanner_page.dart` had only 2 remaining `GlassCard` sites left, both an error-state card with
`tint: theme.colorScheme.error` (`scan.when`'s `error` branch, and `_LiveSection`'s error branch).
Neither `HudPanel` nor `HudSurface` exposes a flat colour-fill override (`HudSurface.overlay` is a
`Gradient?`, not a plain `Color?`) -- migrating these would mean inventing a new, unreviewed status-
tint mechanism, which is exactly what GPT-PM's design guidance said not to do ad hoc. Reclassified
both `INTENTIONAL_LEGACY_EXCEPTION` with an inline doc comment at each site pointing back here.
`scanner_page.dart` therefore keeps its `glass.dart` import and is *closed* for this migration gate
(no more accidental/undecided `GlassCard` usage in it), not "still partial" -- the 2 remaining sites
are a recorded, reasoned decision, not overlooked debt. `flutter analyze` clean; existing
`scanner_page_test.dart` suite green (64/64, including its own error-path assertions).

**New finding, not yet scoped as a sub-gate**: a `HudPanel`/`HudSurface` status-tint variant (flat
error/warning/success fill, analogous to `HudSheet`'s opaque-fill precedent) would let these last 2
sites -- and any future one needing the same -- retire `GlassCard`'s `tint` parameter entirely. Left
for a future sub-gate rather than designed here without review.

### Sub-gate 1 — closed, 2026-08-29

Resolved the opaque-surface gap this file first identified: added `HudSheet` to
`shared/widgets/hud/hud_surface.dart` (derives `panel`'s border/glow/topHighlight byte-for-byte,
replaces only `fill` with the already-shipped `AppSemanticColors.surfaceElevated`, zeroes
`cssBlur`/`saturate` since an opaque fill has nothing to backdrop-blur), per GPT-PM's explicit
approved design (round review, 2026-08-29, full reply archived in `core/DECISION_LOG.md`). Migrated
the two identified bottom sheets — `workouts_page.dart`'s `_ConfirmSwitchSheet` and
`difficulty_rating_sheet.dart`'s `DifficultyRatingSheet` — off `GlassCard(floating: true, ...)` onto
`HudSheet(...)`. Both files' `glass.dart` imports removed; zero remaining `GlassCard` references in
either (grep-verified). 6 new widget tests in `mobile/test/shared/widgets/hud/hud_components_test.dart`
pin: fill opacity (alpha 1.0, both themes), fill resolving to the real `surfaceElevated` token (not an
invented value), border/glow read directly off `HudTokens.dark/.light.panel` (not copied literals),
default radius = `HudTokens.radiusSheet` (26, previously unused, distinct from `radiusPanel`=30),
survival under a bare `MaterialApp` (no app theme installed), and default padding. `flutter analyze`
clean on all 3 touched source files + the test file; `flutter test` green: 58/58 in
`hud_components_test.dart` (52 pre-existing + 6 new), 40/40 in the existing `workouts_page_test.dart`
regression suite. `GlassCard.floating`'s dead-parameter cleanup (this file's secondary finding) is
deferred to `glass.dart`'s eventual full retirement, not done in this sub-gate.

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

**Correction to this finding's own first pass, caught before relying on it further**: the first read
of `glass.dart` assumed `floating: true` was still the mechanism keeping this sheet opaque. It is
not -- `floating` is declared and extensively documented (the day-3-donation-sheet bug it was
introduced to fix) but is **never read inside `GlassCard.build()`**; grepping the file confirms it
appears nowhere else. `GlassCard`'s actual opacity comes from a separate, later fix ("Ф1c: flat
opaque surface, not translucent white") that made the DEFAULT fill of every `GlassCard` opaque
(`tokens?.surfaceElevated ?? theme.colorScheme.surfaceContainerHighest`, no alpha), superseding
`floating` for that purpose -- so `floating: true` on this call site is dead weight, not the load-bearing flag its own comment claims.

That correction does not remove the real gap, though -- it relocates it. Checked `HudGlass` (the
recipe `HudPanel`/`HudSurface` read their fill from, `core/theme/hud_tokens.dart`): its `fill` field
is **deliberately** near-transparent by design -- `rgba(255,255,255,.014)` on dark, with the panel's
shape "carried entirely by `innerBorder` and `glow`," not the fill. That is the correct, intentional
aesthetic for a panel sitting on the app's own background, and exactly wrong for a sheet presented
over scrollable content it does not own: migrating `workouts_page.dart`'s confirm sheet (or
`difficulty_rating_sheet.dart`'s, same documented reason) to a stock `HudPanel` as-is would very
likely reintroduce the exact "поздравление с 3 днем просто наезжает и не читается" bug `GlassCard`'s
own comment records, at a ~1.4% fill alpha instead of GlassCard's opaque one.

So: the real, confirmed gap is that **no HUD glass recipe/opaque-surface variant exists yet for a
sheet over content it doesn't control** -- `HudGlass`'s only recipes are all deliberately translucent
by design. Per GPT-PM's DoD ("don't do mechanical blind replacement"), this class of site needs
either (a) a new opaque `HudGlass` recipe / `HudSheet` variant added to the shared widget library
first, then migrated, or (b) classification as `INTENTIONAL_LEGACY_EXCEPTION` with this reasoning
recorded -- not a blind swap to a stock `HudPanel` that would silently reintroduce the bug the
original `GlassCard` comment exists to prevent. Secondary, smaller finding worth fixing regardless
of the above: `GlassCard.floating`'s dead parameter and stale doc comment should be removed or
reconciled when `glass.dart` is eventually retired, so nobody reads it as still-load-bearing again.

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
3. ~~**`aurora_background` retirement**~~ -- **void, corrected 2026-08-29 before any work started
   on it.** The original framing (2 real usage sites, small and bounded) was itself wrong: checked
   `workout_player_page.dart:1037` and it is a comment, not a usage -- `main.dart:620` is the only
   real one. More importantly, `AuroraBackground` is not legacy competing with `HudSkyBackground` --
   its own doc comment already states it is "one flat fill, nothing else" (a past fix already
   stripped the gradient/bloom layers this migration gate exists to retire elsewhere), and it sits
   at `main.dart`'s app-wide router wrapper as the base/fallback background. `HudSkyBackground` is a
   different, complementary widget -- a photographic time-of-day scene, composed separately and only
   inside `main_shell.dart`'s body and `onboarding_page.dart` (confirmed by grepping every call
   site), not a replacement for the app-wide flat base layer. There is nothing to retire here: no
   duplicate visual system, no dead code, no HUD-vs-legacy conflict. Removing or swapping
   `AuroraBackground` would drop the base fill every route outside the main shell still needs.
   Struck from the sub-gate order; not attempted.
4. **Remaining ~36 files**, grouped by feature area (equipment/workouts/progress/settings/etc.),
   each its own sub-gate per GPT-PM's explicit guidance not to land one 46-file commit.

## What this file is not

Not a plan with a GO -- no `pm_rosetta_plan`/GPT-PM approval has been sought for a specific
migration order yet. Not a classification of all 40 files (`MIGRATE_TO_HUD` /
`INTENTIONAL_LEGACY_EXCEPTION` / `DEAD_CODE` per file) -- that is the next concrete step, file by
file, not assumed from the aggregate counts above.
