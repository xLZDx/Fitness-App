# R11 — Figma parity rebuild, plan (2026-08-08)

Written after a full-app audit, per the operator's directive ("прогони
агентов по всему что есть, почини баги и собери новый гейт под реальный
App.tsx. ГО"). Full evidence lives in `core/DECISION_LOG.md`, entries at
18:11 (Home) and 19:15 (the other 9 screens/flows) — this file is the
*plan*, not a repeat of the evidence.

## 1. What this gate exists to fix

R9/R9b recoloured the app's existing UI (pink/violet gradients -> lime).
Except for one screen (Workout Summary, built at R5 directly from the real
prototype source), **every other screen predates the Figma Make redesign
entirely** — the structural rebuild the original R1-R9 sequence was
supposed to deliver never happened, because R1-R4 were scoped from an
audit document's prose retelling of the design, not from `App.tsx` itself
(root cause: `DECISION_LOG.md`, 18:11 entry). Recolouring a screen that was
never rebuilt does not make it match the design — it makes it look like the
design's *palette* on the old *layout*, which is exactly what the operator
noticed on a real device.

## 2. Scope-trigger acknowledgement

This project's own Quantified Scope-Trigger rule: a gate estimated at >2h,
touching >15 files, or specified in >350 lines must be split into sub-gates
and proposed BEFORE building, even under a standing GO. Nine screens/flows,
several needing new custom widgets (canvas-drawn rulers, an SVG body
diagram, a camera viewfinder that does not exist yet) and two touching
business-sensitive copy (pricing tiers, trial length), is unambiguously
past that line. What follows is the split, not a build.

## 3. Sub-gates, sized by concrete signal (not a guessed hour count)

| Gate | Screen(s) | What's missing (see decision log for full detail) | Size signal | Needs a decision beyond engineering? |
|---|---|---|---|---|
| **R11a** | Home | Greeting+name header, program-progress bar, "today" hero with the real workout, recovery strip, week strip, restructured stats | M — 1 screen, ~5 new sub-components, no new data model | No — all data already exists in providers |
| **R11b** | Onboarding | 13-step wizard vs current 7; none of `WheelYear`/`HRuler`/`VRuler`/`BodyDiagram`/`ChoiceCard`/`BMICard`/`DeltaCard` exist | **XL** — largest gate. 4 new custom-drawn picker widgets (canvas gesture handling), a new SVG body-part diagram, 6 new step screens, re-sequencing the whole flow | Partially — the step *order* is a UX decision, not just a port |
| **R11c** | Scan | Full-bleed camera canvas, animated scan-frame, bottom-sheet result with description/stats/CTA | L — 1 screen, but a layout inversion (card-list -> full-bleed), new animated overlay | No |
| **R11d** | Exercise + Equipment | Immersive hero image/video, quick-stats row, featured/full-list split, sticky CTA, suitability signal | L — 2 screens, both need a hero treatment neither has today | No |
| **R11e** | Workout Player + Rest Timer | Multi-exercise loop, inline weight/rep steppers, full-screen rest overlay (currently an inline card) | **XL, and blocked on a data-model question** — the prototype logs N exercises x M sets per session; the app's `WorkoutSession` model deliberately supports "one exercise, at most one set per session" (F3.4, decision log). Rebuilding the loop without reopening that decision is not possible. | **Yes — explicit product decision required** before scoping starts |
| **R11f** | Progress Photos | 7 of 9 flow states missing entirely (privacy gate, angle select, capture w/ viewfinder, preview, metadata, notification, export) — the scanner-style blind-capture bug (no viewfinder) is a symptom of this same gap | **XL** — real feature work, not just layout: a live camera viewfinder for photo capture does not exist anywhere in this feature today | No, but it's the single biggest functional gap in the app |
| **R11g** | Progress charts | Missing "Фото прогресса" block (feature exists elsewhere, just not surfaced here); has 3 sections (8-week chart, full records list, recent-activity) the design never specified | S — smallest gate. Mostly additive (surface the photo block) plus a decision on the 3 extra sections | Minor — keep, cut, or fold the 3 Flutter-only sections is a product call |
| **R11h** | Technique Coach | 8-phase wizard (intro/preparation/quality-check/calibration/ready/summary) missing; current screen is one persistent camera panel | L — wraps the EXISTING real pose-detection engine in new screen states; does not touch the ML/rep-counting logic itself | No |
| **R11i** | Workouts + Profile + Paywall | Programs(with progress%)/Library split gone; AI-coach chat panel not wired to Workouts; Profile is a flat list vs 7 grouped sections; Paywall is 3-tier/bullets vs the design's 2-tier comparison table, and claims a 14-day trial vs the design's 7 | **L, and Paywall half is blocked on a business decision** — tier count and trial length are pricing/monetisation calls, not layout | **Yes — for the Paywall portion specifically** |

## 4. Recommended order

Not alphabetical — ordered by (a) no external decision blocking it, (b)
user-facing frequency, (c) smallest-first where independent, so the first
few gates ship visible progress fast per the operator's own gate-based
build/verify/commit/stop rhythm:

1. **R11a Home** — the screen every session opens on; the one the operator's
   own complaint was about; no blockers.
2. **R11g Progress charts** — smallest gate, ships a real fix (surfacing the
   Photo Progress block) with minimal new surface.
3. **R11d Exercise + Equipment** — no blockers, high frequency (opened from
   every workout and every scan result).
4. **R11c Scan** — no blockers, second screen in the core loop after Home.
5. **R11h Technique Coach** — no blockers, isolated from the rest (only
   touches its own screen states, not the pose engine).
6. **R11b Onboarding** — no blockers but XL; scheduled after the smaller
   wins land, not first, so scope discipline is proven on smaller gates
   before the largest one.
7. **R11f Progress Photos** — XL and genuinely new feature work (the
   viewfinder); benefits from being scheduled once the team's rhythm on
   this gate size is established.
8. **R11e Workout Player** — **held** until the multi-exercise-session data
   model question is answered; engineering scoping cannot start honestly
   before that.
9. **R11i Workouts + Profile + Paywall** — **held**, Paywall half specifically,
   until tier count / trial length is confirmed; Workouts+Profile portions
   could proceed independently if the operator wants to split this gate
   further.

## 5. What this plan does NOT do

It does not start building any of the nine. Per Gate-Based Development, a
sub-gate above becomes buildable only on its own explicit `GO R11<letter>`
— the standing GO that authorised the audit-and-fix-bugs turn does not
retroactively authorise nine gates' worth of new screens.

---

## 6. Execution status — updated 2026-08-08, 22:40 local (Europe/Chisinau) / 19:40 UTC

Operator authorised the whole sequence: *"Пуш + ГО R11a–R11i по порядку автономно"*
— a multi-gate GO in this plan's own recommended order (§4), run
autonomously. Section 5 above is superseded by that GO for R11a–R11i.

| Gate | Status | Commit |
|---|---|---|
| **R11a** Home | **DONE** | `11f94b6` |
| **R11g** Progress | **DONE** | `a4d00e0` |
| **R11d** Exercise + Equipment | **DONE** | `7d614ca` |
| **R11c** Scan | **PARTIAL** — scan frame only | `9579144` |
| **R11h** Technique Coach | not started | — |
| **R11b** Onboarding | not started | — |
| **R11f** Progress Photos | not started | — |
| **R11e** Workout Player | **HELD** — needs a data-model decision | — |
| **R11i** Workouts + Profile + Paywall | **HELD (Paywall half)** — needs a pricing decision | — |

Verification at the stopping point: `flutter analyze` 7 issues (identical
to the pre-R11 baseline, 0 new), `flutter test` 1791 passed / 0 failed
(1748 before R11a). Nothing pushed since `4dc291a` — all four gate commits
are local and need a separate push-GO.

### Where to resume

**Next gate in order is R11c's remainder**, then R11h.

R11c's outstanding work, in the order it should be done:

1. Invert `mobile/lib/features/scanner/scanner_page.dart`'s build (line
   ~424): `Stack` with the preview `Positioned.fill` behind everything,
   instead of a `SizedBox(height: 0.68 * screen)` inside a `ListView`.
2. Replace `GlassAppBar` with a glass row over the preview: back,
   "Распознавание" pill, capture-mode toggle.
3. Move the capture + gallery buttons into a control cluster over the
   camera; the design also has a flash control, which has **no equivalent
   anywhere in the app** — it needs a `CameraSession` torch API first, so
   treat it as its own sub-item, not a layout detail.
4. Put the result cards into a `DraggableScrollableSheet` over the preview.
5. Re-run `test/features/scanner_page_test.dart` — 40 tests assert the
   current structure and several use `scrollUntilVisible` against the
   `ListView` that step 1 removes. Expect to rewrite their scrolling, not
   their assertions.

`ScanFrame` (`mobile/lib/features/scanner/widgets/scan_frame.dart`) is
already built, tested and wired; the inversion does not change it.

### Two gates still need an operator decision before they can be scoped

- **R11e** — does a `WorkoutSession` become multi-exercise / multi-set?
  The F3.4 decision (one exercise, at most one set per session) is what
  makes the design's player loop unbuildable as specified. Reversing it is
  a data-model change with a migration, not a layout change.
- **R11i, Paywall half** — 2 tiers or 3, and 7-day trial or 14. Both are
  monetisation calls. The Workouts and Profile halves have no blocker and
  can proceed alone if the operator wants the gate split.
