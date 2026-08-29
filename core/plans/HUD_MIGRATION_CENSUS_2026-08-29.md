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
| `GlassCard(` call sites | 126 → 124 → 117 → 96 (gate 4) → 84 (sub-gate 5) → 67 (sub-gate 6) → 50 (sub-gate 7) → 45 (sub-gate 8) → 34 (sub-gate 9) → **0** after sub-gate 10 (1 remaining call is `deload_banner.dart`'s own intentional exception, kept as `GlassCard` on purpose -- see below) |
| Files with at least one `GlassCard(` call | 40 (39 real usage sites + `glass.dart`'s own definition) → 38 → 37 → 31 (gate 4) → 20 (sub-gate 5) → 14 (sub-gate 6) → 12 (sub-gate 7) → 8 (sub-gate 8) → 6 (sub-gate 9) → **2** after sub-gate 10: `deload_banner.dart` (the intentional exception) + `glass.dart`'s own definition. Methodology note carried forward: a raw `grep -rl "GlassCard("` also matches `hud_surface.dart`'s `HudPanelTone` doc comment (prose, not a call site) -- excluded from this and every count above. |
| Files importing `shared/widgets/glass.dart` | 45 → 43 → 42 → 38 (gate 4) → 33 (sub-gate 5) → 33 (sub-gate 6) → 33 (sub-gate 7) → 33 (sub-gate 8) → 32 (sub-gate 9) → **32** after sub-gate 10 (unchanged: all 4 files in this batch use `FrostedScaffold`/`GlassAppBar` and scoped their import to `show` rather than dropping it) |
| `INTENTIONAL_LEGACY_EXCEPTION` sites (`GlassCard` kept for a capability `HudPanel` genuinely lacks) | 2 (`scanner_page.dart`) + 1 (`deload_banner.dart`) → 6 (sub-gate 7) → 1 (sub-gate 8) → 1 (sub-gate 9) → **1** after sub-gate 10 (unchanged: only `deload_banner.dart`; this sub-gate's 3 error sites -- `progress_photos_page.dart`, `subscription_page.dart` -- all landed directly on `HudPanelTone.error`, `progress_page.dart` and `settings_page.dart` had no tint sites at all) |

**Migration substantially complete as of sub-gate 10.** Every `GlassCard` call site in the app is
either migrated to `HudPanel`/`HudSheet`/`HudPanelTone.error`, or is `deload_banner.dart`'s single
remaining, deliberately-kept recovery-accent exception (see "Suggested sub-gate order" below for
what would close it). `shared/widgets/glass.dart` itself stays in the tree -- `FrostedScaffold` and
`GlassAppBar` are still the app's scaffold/app-bar primitives and were never in scope for this
migration; only `GlassCard` (and its `tint`/gradient capability) was being retired.
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

### Sub-gate 3 ("aurora_background retirement") — struck, void, 2026-08-29

Found void before writing any code; see the corrected entry in "Suggested sub-gate order" below.
`AuroraBackground` is already a flat fill (own doc comment: "one flat fill, nothing else") and sits
as `main.dart`'s app-wide base layer; `HudSkyBackground` is a complementary photographic layer
composed only inside `main_shell.dart` and `onboarding_page.dart`, not a replacement for it.
Nothing to retire. No code changed.

### Sub-gate 4 (equipment cluster) — closed, 2026-08-29

Migrated the `features/equipment/` cluster: `equipment_detail_page.dart` (8 sites, all in-page
cards -- one custom `HudPanel(radius: 12, padding: ...)` override, matching the site's original
`borderRadius: 12` exactly, param renamed since `HudPanel` calls it `radius` not `borderRadius`),
`exercise_page.dart` (1 site, in-page card with `onTap`), `exercise_reference.dart` (9 sites, all
in-page -- one more `radius`-override site), `last_session_card.dart` and `setup_note_card.dart`
(1 site each, plain in-page cards) -- all → `HudPanel`. `equipment_report_sheet.dart` (1 site) is a
genuine `showModalBottomSheet` presented over whatever screen opened it (its own doc comment
confirms), classified by actual widget-tree role per GPT-PM's guardrail rather than by its
filename alone -- migrated to `HudSheet`, dropping the dead `floating: true` flag.

**Caught mid-migration, not after**: `equipment_detail_page.dart` and `exercise_page.dart` both
also use `FrostedScaffold` from `glass.dart` (a class this gate is not touching) -- an initial bulk
import swap broke both files' analyze pass immediately, caught by the tool's own post-edit file-
diff notice before either was left broken. Both keep a scoped `import '...glass.dart' show
FrostedScaffold;` alongside the new HUD import, so `glass.dart`'s import count doesn't fall as far
as the raw file-migration count would suggest (see the Numbers table above).

`flutter analyze` clean on all 6 files. `flutter test`: `equipment_detail_coach_gate_test.dart`,
`equipment_report_sheet_test.dart`, `exercise_page_test.dart`, `setup_note_card_test.dart`,
`last_session_card_test.dart` all green (no dedicated test file exists for
`exercise_reference.dart` itself; it's covered indirectly through the pages that render it).

### Sub-gate 5 (single-site files across 11 areas) — closed, 2026-08-29

Migrated every remaining single-`GlassCard`-site file in one batch, classified by actual role
per GPT-PM's ownership guardrail, not by filename:

- **`HudSheet`** (genuine `showModalBottomSheet`/`DraggableScrollableSheet` content, confirmed
  from each widget's own `.show()`/doc comment, not assumed from the name): `set_capture_sheet.dart`,
  `day3_welcome_modal.dart` (the original "day-3 donation sheet" bug this whole gap is named
  after), `plate_calculator.dart` and `warmup_calculator.dart` (both explicitly doc-commented
  "bottom-sheet appropriate; can be embedded inline" and both already carried the dead
  `floating: true` flag -- the same tell sub-gate 1's two sheets had).
- **`HudPanel`** (in-page cards, confirmed by reading each site's real container): 
  `account_deletion_page.dart`, `login_page.dart`, `moderation_page.dart`, `privacy_page.dart`,
  `terms_page.dart`, `licences_page.dart` (2 sites). `machine_card_view.dart` needed checking its
  actual embedding context first -- it renders inside `scanner_page.dart`'s
  `DraggableScrollableSheet`, which looked sheet-shaped by container alone, but that sheet's own
  root `Container` is ALREADY opaque (`color: theme.colors.surfaceElevated`, with a comment citing
  this exact gate's own bug) specifically so cards nested inside it can stay translucent -- matching
  every one of that file's own already-shipped `HudPanel` cards in the same sheet. Ownership is
  about what's directly behind a widget, not "is this anywhere inside something called a sheet."
- **`INTENTIONAL_LEGACY_EXCEPTION`** (kept as `GlassCard`, documented inline): `deload_banner.dart`
  -- needs `tint: AppPalette.auroraPeach`, the same flat-colour-fill gap already recorded for
  `scanner_page.dart`'s error cards. Second confirmed instance of the same gap (see the status-tint
  finding from sub-gate 2/4) -- still a candidate for one future consolidated sub-gate, not two
  separate ones.

`flutter analyze` clean on all 12 touched files. `flutter test`: `account_deletion_page_test.dart`,
`account_deletion_providers_test.dart`, `login_page_test.dart`, `plate_calculator_test.dart`,
`warmup_calculator_test.dart`, `set_capture_sheet_wording_test.dart` all green (30 total
assertions across the account-deletion/login/set-capture suites, plus 10 pure-function assertions
for the two calculators). No dedicated widget test exists for `day3_welcome_modal.dart`,
`moderation_page.dart`, `privacy_page.dart`, `terms_page.dart`, `licences_page.dart`,
`machine_card_view.dart`, or `deload_banner.dart` -- `flutter analyze` plus the surrounding
regression suites is the coverage this sub-gate has for those.

### Sub-gate 6 (2-3-site batch across 6 feature areas) — closed, 2026-08-29

Migrated the next batch of files carrying 2-3 `GlassCard(` sites each -- `social_feed_page.dart`,
`about_page.dart`, `celebrity_plans_page.dart`, `backup_page.dart`, `marketplace_page.dart`,
`injuries_page.dart` -- 17 sites total, same ownership-by-actual-container discipline as every
prior sub-gate:

- **`HudSheet`** (genuine `showModalBottomSheet`, confirmed from the call site itself, not the
  filename): `social_feed_page.dart`'s `_composeSheet` -- explicit `padding: EdgeInsets.all(16)`
  preserved (the sheet already had a deliberate, non-default padding), dead `floating: true`
  dropped.
- **`HudPanel`** (in-page cards sitting on the page's own background): every other site in this
  batch -- `social_feed_page.dart`'s `_PostCard` (`padding: EdgeInsets.all(14)`); `about_page.dart`'s
  mission card, fund-use card and `_PrincipleCard` (padding 20/18/16 respectively, all preserved);
  `celebrity_plans_page.dart`'s intro card, error-branch card and `_PlanCard`
  (`padding: EdgeInsets.all(16)`); `backup_page.dart`'s three plain cards (what-it-carries, create,
  restore); `marketplace_page.dart`'s intro card, error-branch card and `_CoachCard`
  (`padding: EdgeInsets.all(16)`, conditional `onTap` -- `HudPanel` supports this identically, so no
  capability gap); `injuries_page.dart`'s summary card, empty-state card and `_InjuryCard`'s form
  card. None of the 17 sites needed `tint`/`gradient`, so none triggered an
  `INTENTIONAL_LEGACY_EXCEPTION`.
- Every touched page-level file kept a scoped `import '...glass.dart' show FrostedScaffold,
  GlassAppBar;` alongside the new `hud_surface.dart` import (all six still return a `FrostedScaffold`
  with a `GlassAppBar`) -- this is why the "files importing `glass.dart`" count in the table above
  does not drop for this sub-gate even though 17 `GlassCard(` sites left. `injuries_page.dart`
  additionally uses `GlassTextField`, but that's sourced from `features/onboarding/widgets/inputs.dart`
  (already imported), not from `glass.dart` -- an initial `show ... GlassTextField` on the `glass.dart`
  import was a mistake caught immediately by `flutter analyze` (`undefined_shown_name`) and removed.
- `marketplace_page.dart`'s `_CoachCard` carried a doc comment explaining `bookingDisabled` in terms
  of "`GlassCard`'s own `onTap != null` check" and "`glass.dart`" -- updated to name `HudPanel` and
  `hud_surface.dart` instead, after confirming (`hud_surface.dart:311-312`,
  `Semantics(button: onTap != null, ...)`) the claim still holds for the new widget.

`flutter analyze` clean on all 6 touched files. `flutter test`: `marketplace_page_test.dart` and
`injuries_page_test.dart` both green, plus `hud_components_test.dart`'s `HudSheet` group -- 73 total
assertions across the three suites run. No dedicated widget test exists for `social_feed_page.dart`,
`about_page.dart`, `celebrity_plans_page.dart`, or `backup_page.dart` -- `flutter analyze` is the
coverage this sub-gate has for those four.

### Sub-gate 7 (4-site batch across 5 feature areas) — closed, 2026-08-29

Migrated `contribute_video_page.dart`, `team_feed_page.dart`, `donor_wall_page.dart`,
`posture_page.dart`, `workout_summary_page.dart` -- 20 `GlassCard(` sites, 17 migrated to
`HudPanel`, 3 kept as `GlassCard` under `INTENTIONAL_LEGACY_EXCEPTION`.

- **`HudPanel`** (in-page cards, no capability gap): all sites in `posture_page.dart` (intro card,
  disclaimer card, no-body-detected card, `_MetricCard`) and `workout_summary_page.dart`
  (`_EmptyDay`, `_StatTile`, `_MuscleLoad`, `_NextWorkout` -- the last has a conditional `onTap`,
  which `HudPanel` supports identically); plus the non-error sites in the other three files:
  `contribute_video_page.dart`'s intro/form/success cards, `team_feed_page.dart`'s empty-state card
  and `_LockedHero`/`_PostCard`, `donor_wall_page.dart`'s intro card and `_DonorList`/`_DonorTile`.
- **`INTENTIONAL_LEGACY_EXCEPTION`** (kept as `GlassCard`, documented inline, same as the two prior
  instances): `contribute_video_page.dart`'s error card, `team_feed_page.dart`'s error branch, and
  `donor_wall_page.dart`'s error branch -- all three are `tint: <error color>` on the async-error
  path, the identical shape as `scanner_page.dart` (sub-gate 2) and `deload_banner.dart` (sub-gate
  5). Each site now carries the inline exception comment introduced in sub-gate 5.
- Where a file keeps at least one `GlassCard` site, its `glass.dart` import stayed **unqualified**
  (full import, not `show`) rather than split -- `GlassCard` itself is still directly referenced, so
  a `show FrostedScaffold, GlassAppBar` clause would just break the remaining site. Where a file
  dropped its last `GlassCard` site (`posture_page.dart`, `workout_summary_page.dart`), the import
  scoped down to `show FrostedScaffold, GlassAppBar` per the established pattern.

**Flag for GPT-PM, not deferred again**: this sub-gate is the third round in which a fresh
`GlassCard` error-tint site turned up (sub-gate 2: 2 sites in `scanner_page.dart`; sub-gate 5: 1
site in `deload_banner.dart`; this sub-gate: 3 more sites across 3 files). The running total is now
**6 `tint` sites across 5 files**, all doing the exact same thing -- an async-error or validation
card painted in `colorScheme.error` (occasionally another semantic tone). Every prior round's
guidance was "consolidate into one future sub-gate, not one round per instance"; six real,
independently-discovered sites is past the point where "future" should mean "next session," not
"eventually." Proposed shape for that sub-gate, to put to GPT-PM before starting it: a `HudPanel`
variant (or a `tone`/`status` parameter on the existing one) that swaps only the fill for a
semantic-status color the same way `HudSheet` already swaps only the fill of `HudPanel`'s own
recipe for an opaque surface -- i.e. reuse the established "derive border/glow/shadow from the
panel recipe, replace one visual property" pattern rather than inventing a fourth one. Not
implemented in this sub-gate; this is the design question to raise, not a decision made
unilaterally.

`flutter analyze` clean on all 5 files. `flutter test`: 15 assertions across
`team_feed_demo_banner_test.dart` (7), `posture_page_test.dart` (3), `donor_wall_test.dart` (5,
model/repository-level, not a page widget test) -- all green. No dedicated widget test exists for
`contribute_video_page.dart` or `workout_summary_page.dart` -- `flutter analyze` is this sub-gate's
coverage for those two.

### Sub-gate 8 (status-tint gap closed: `HudPanelTone.error`) — closed, 2026-08-29

Raised the flag from sub-gate 7 with GPT-PM before implementing anything (real exchange via
PM Bridge, not a unilateral call). Verdict: **MODIFY** -- approved the reuse-HudPanel's-recipe
shape, but made one correction that changed scope: **`deload_banner.dart` is not an error-tint
site.** It shows `tint: AppPalette.auroraPeach` for a recovery *recommendation*
(`shouldDeload == true`), not an async-error/validation state -- visually similar (both are a
flat-tinted `GlassCard`) but semantically a different thing. So the evidenced pattern is **5 error
sites across 4 files**, not 6 across 5, and `deload_banner.dart` stays an
`INTENTIONAL_LEGACY_EXCEPTION` on its own, correctly re-labelled rather than folded into the new
mechanism just to clear one more site.

GPT-PM's full ruling, implemented as given:

- **Shape**: `HudPanel` itself gets a `tone` parameter (not a new `HudStatusPanel` widget, not a
  raw overlay, not a colored-border substitute). `HudPanelTone.error` derives from `t.panel` --
  the exact recipe `HudPanel` already uses -- with only the fill replaced by
  `Theme.of(context).colorScheme.error`, and `cssBlur`/`saturate` zeroed the same way `HudSheet`
  already zeroes them for an opaque fill (nothing behind a solid color needs backdrop-filtering).
  Border, glow, drop shadows and top highlight stay byte-identical to `t.panel`.
- **API**: an enum (`HudPanelTone`), not a raw `Color? tint` parameter -- a raw color parameter
  would just recreate `GlassCard`'s own escape hatch this whole gate exists to retire. Only
  `HudPanelTone.error` is defined; `warning`/`success`/`info` were explicitly NOT pre-added
  ("just because those are conventional names" -- GPT-PM's own words) without an evidenced site.
  `tone` is asserted mutually exclusive with `secondary`/`dense` (both pick a tier of the same base
  fill a tone has already overridden).
- **Priority**: implement now, in its own sub-gate, rather than batching it with the remaining
  plain-site sweep -- "five confirmed error sites... is already enough recurrence to justify the
  abstraction."
- **Value preserved, not switched**: the error fill stays `theme.colorScheme.error` (what all 5
  sites already resolved to), not swapped to `AppSemanticColors.danger` -- GPT-PM was explicit that
  token normalization is a separate design decision from this migration, absent evidence the two
  values are identical in both themes.

Implementation: `HudPanelTone` enum + `tone` param + `_toneGlass()` on `HudPanel`
(`hud_surface.dart`), following the exact "same recipe, one field overridden" shape
`HudPanel._denseGlass`/`HudSheet._opaqueGlass` already establish. Migrated all 5 evidenced sites:
`scanner_page.dart` (2, its last remaining `GlassCard` sites -- `glass.dart` import scoped down to
`show FrostedScaffold`), `contribute_video_page.dart`, `team_feed_page.dart`,
`donor_wall_page.dart` (1 each, all now fully off `GlassCard`, imports scoped to
`show FrostedScaffold, GlassAppBar`). `deload_banner.dart`'s exception comment corrected to state
plainly it is a distinct recovery-accent case, not the same gap, so a future reader doesn't
mistake it for an unmigrated instance of the same pattern.

New tests, per GPT-PM's own list of invariants to pin (`hud_components_test.dart`, new "HudPanel
tone" group, 8 assertions): `HudPanelTone.normal` unaffected; `.error` resolves to the real
`colorScheme.error` in both themes (not a new literal); border/glow/dropShadows/topHighlight
byte-identical to `t.panel`; blur/saturation disabled on a toned panel; `tone` + `secondary`/`dense`
throws an assertion; padding/radius/`onTap`/semantics behave exactly like an ordinary `HudPanel`.

Verification: `flutter analyze lib/` clean (5 pre-existing, unrelated warnings elsewhere in the
tree, none in touched files). `flutter test`: 120 total assertions across
`scanner_page_test.dart`, `team_feed_demo_banner_test.dart`, `donor_wall_test.dart` and
`hud_components_test.dart` (including the 8 new ones) -- all green. Census:
`GlassCard` sites 50→45, files with a real call 12→8 (7 real usage + `glass.dart`'s own
definition), `glass.dart` importers unchanged at 33, `INTENTIONAL_LEGACY_EXCEPTION` sites 6→1
(only `deload_banner.dart`, correctly re-scoped).

### Sub-gate 9 (`ai_planner_page.dart`, `health_sync_card.dart`) — closed, 2026-08-29

Migrated the next two files, 11 `GlassCard(` sites total. Both files carried their own
`tint: colorScheme.error` async-error site -- both landed directly on `HudPanelTone.error`
(sub-gate 8's already-approved mechanism), no new design question needed: `ai_planner_page.dart`'s
plan-generation error branch and `health_sync_card.dart`'s health-read-failed branch. The other 9
sites (intro/sign-in/hero/exercise-row cards in `ai_planner_page.dart`; `_AskCard`, `_SetupCard`,
`_LoadingTile`, and `_SnapshotCard`'s two branches in `health_sync_card.dart`) are plain in-page
cards -> `HudPanel`, including `ai_planner_page.dart`'s exercise-row card (`onTap`, supported
identically) and `health_sync_card.dart`'s `_LoadingTile` (a `const HudPanel` -- confirmed the
constructor stays `const`-compatible, same as `GlassCard`'s).

`health_sync_card.dart` dropped its `glass.dart` import entirely rather than scoping it down: it
is a card widget, not a page, and never used `FrostedScaffold`/`GlassAppBar` -- the first file in
this migration for which that was true. `ai_planner_page.dart` scoped to
`show FrostedScaffold, GlassAppBar` per the established page-level pattern.

`flutter analyze` clean on both files. `flutter test`: `health_sync_card_test.dart` (7 assertions)
and `ai_planner_providers_test.dart` (2 assertions, provider-level not page-widget) both green.
No dedicated widget test exists for `ai_planner_page.dart` itself -- `flutter analyze` is this
sub-gate's coverage for it. Census: `GlassCard` sites 45->34, files with a call 8->6,
`glass.dart` importers 33->32, `INTENTIONAL_LEGACY_EXCEPTION` sites unchanged at 1.

### Sub-gate 10 (`progress_photos_page.dart`, `subscription_page.dart`, `progress_page.dart`, `settings_page.dart`) — closed, 2026-08-29

The final batch -- migrated the four largest remaining files, 32 `GlassCard(` sites total. Two more
files carried their own `tint: colorScheme.error` async-error site
(`progress_photos_page.dart`'s photo-load failure, `subscription_page.dart`'s `_ErrorCard`); both
landed on `HudPanelTone.error`, no new design question. `progress_page.dart` and
`settings_page.dart` had no tint sites at all -- every one of their 18 combined sites was a plain
in-page card.

Two API translations worth naming explicitly (`GlassCard.borderRadius` -> `HudPanel.radius`, the
same rename every prior sub-gate has made when it came up): `progress_page.dart`'s
`_HeadlineStat` (`borderRadius: 16`) and `_PhotoComparePreview` (`borderRadius: 18`, `onTap` +
`padding: EdgeInsets.zero` -- confirmed `HudPanel` still applies zero padding correctly on the
`onTap` branch, where padding moves from the outer `HudSurface` to an inner `Padding` around the
`InkWell`'s child; behavior unchanged). `settings_page.dart`'s 8 tappable rows (about, terms,
privacy, export, backup, licences, moderation, delete-account) all carry `onTap`, supported
identically -- including the delete-account row, which tints its own icon/text `colorScheme.error`
but never tinted the card's fill, so it needed no `HudPanelTone` at all.

`flutter analyze lib/` clean (same 5 pre-existing, unrelated warnings elsewhere in the tree; one
real fix made along the way: `progress_photos_page.dart`'s page-level `theme` local went unused
once its `tint: theme.colorScheme.error` reference became `tone: HudPanelTone.error`, removed).
`flutter test`: 53 total assertions across `progress_photos_demo_banner_test.dart` (17),
`progress_page_test.dart` (13), `settings_page_test.dart` (11), `subscription_page_test.dart`
(12) -- all green, every one of the four files in this batch has a dedicated widget-test suite.

Census: `GlassCard` sites 34->0 (the one remaining call is `deload_banner.dart`'s own intentional
exception), files with a call 6->2 (`deload_banner.dart` + `glass.dart`'s own definition),
`glass.dart` importers unchanged at 32, `INTENTIONAL_LEGACY_EXCEPTION` sites unchanged at 1.

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
