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

| Gate | Status | Commit(s) |
|---|---|---|
| **R11a** Home | **DONE** | `11f94b6` |
| **R11g** Progress | **DONE** | `a4d00e0` |
| **R11d** Exercise + Equipment | **DONE** | `7d614ca` |
| **R11c** Scan | **DONE** | `9579144` + `4ddea5a` |
| **R11h** Technique Coach | **PARTIAL** — readiness stages, not the full wizard | `9794d27` |
| **R11b** Onboarding | **PARTIAL** — rulers + BMI/delta, not the 13-step flow | `4f78b0c` |
| **R11f** Progress Photos | **PARTIAL** — angle + viewfinder, 2 of 9 states | `0e98021` |
| **R11e** Workout Player | **PARTIAL** — see §7 | pending |
| **R11i** Workouts + Profile + Paywall | **PARTIAL** — Workouts done via §7's Programme gate; Profile grouped; Paywall still **HELD** on pricing | `3b6841b` + pending |

Verification at THIS stopping point: `4dc291a..a67e5b9` is pushed; the R11a
through R11i(Profile) commits above that are local and need a separate
push-GO. §7 below covers what unblocked R11e and R11i's Workouts half, and
carries its own verification numbers.

## 7. Post-decision closure — 2026-08-09

The operator answered both open questions directly:

1. **R11e** — *"это одна тренировка, но тут надо смотреть на уровень
   человека, время тренировки, направление и цели... один поход в
   тренажерный зал это одна тренировка на разных тренажерах... количество
   подходов, разнообразие предложенных упражнений зависит от каждого
   человека индивидуально"* — a session is ONE workout regardless of how
   many exercises it holds. This is the answer §6's blocking question
   needed: multi-exercise sessions are allowed, and "1 session = 1 workout"
   is a counting rule, not a data-model constraint.
2. **Programme entity (named three times in §6)** — *"согласен с планом...
   Это добавление, а не изменение"* — build it as an additive header over
   the existing schedule, per the impact analysis presented separately.
3. **Paywall** — explicitly deferred: *"отложи на потом, прода еще нету тк
   что щас это не важно"*. Still HELD; not started.

### Gate P — the programme entity

Built exactly as scoped: `Programme` + `ProgrammeTemplate` (6 templates,
sourced from the real `PROGRAMS` array in the prototype, `App.tsx:4726-4733`)
+ `ScheduledSession.programmeId` (nullable, additive — no migration) +
`ProgrammeRepository` (mock + Firestore) + `buildProgrammeSchedule` (pure,
turns a template into real screened-catalogue `ScheduledSession` rows) +
`ProgrammeAction` (enroll / add-one-exercise). Wired into: Home's header bar
(replaces the plain schedule bar when a programme is active), the Equipment
exercise page ("Add to programme" button, R11d's own named gap), the GDPR
export, and R11i's Workouts split (below).

### R11e — closure

Two parts, matching how every other PARTIAL gate in this plan is reported:

1. **Data correctness (full, not partial).** `WorkoutSession.asLogEntryView()`
   — documented in its own comment as "silently correct today, silently
   lossy the day [multi-exercise] stops holding" — is now
   `asLogEntries()`: one row per exercise, all sharing a new
   `WorkoutLogEntry.sessionId`. Every counter that used to count rows
   (`deriveProgress`'s total/thisWeek/last8Weeks, `deriveWeekTotals`'s
   `workouts`) now counts distinct `sessionId`s, so a 5-exercise gym visit
   is one workout in every stat, matching the operator's own resolution.
   `sessionId` defaults to `id` — every existing single-exercise session,
   every legacy `workout_logs` document, reads back byte-identical.
2. **Player loop (real, deliberately smaller than the prototype's exact
   screen).** `_AddExerciseButton` lets the player append a second (third,
   ...) exercise to the SAME open session via the existing
   `SetCaptureSheet`/`DifficultyRatingSheet` flow, reusing the real
   injury-screened catalogue. What is NOT built: the prototype's dedicated
   full-screen carousel with progress dots — this reuses the existing
   single-exercise screen's chrome plus one more button, not a new screen
   design. A real bug was found and fixed while wiring this: the entry
   exercise's own "Mark complete" re-edit path used to overwrite the whole
   `exercises` list, silently dropping anything `_AddExerciseButton` had
   already appended — extracted into `replaceEntryExercise`, unit-tested
   directly (`workout_session_models_test.dart`).

### R11i — Workouts half, closure

Programs/Library sub-tab split built on Gate P: `_ProgramsTab` (current-
programme card with real week/percent + a "continue to the next scheduled
session" CTA sourced from `upcomingSessionsProvider`, goal-filtered template
browse list, enroll wired to `ProgrammeAction.enroll`) sits behind a toggle
next to `_LibraryTab` (the original Train tab, moved verbatim). Existing
`workouts_page_test.dart` assertions needed one mechanical change — tap
"Library" first, since the page no longer opens directly on it — everything
those tests were actually pinning is unchanged.

### What is still open

- **Paywall** — deferred by the operator, not started.
- **R11e's exact screen chrome** — full-screen rest overlay between
  exercises, progress dots, is not built; the append flow is a button on
  the existing screen.
- **Device verification** — see §8.

### Verification for §7

`flutter analyze` — 7 issues, identical to the pre-R11 baseline, 0 new.
`flutter test` — **1879 passed / 0 failed** (1826 before this closure pass;
+53 new tests: programme model/schedule/repo/action, R11e's `asLogEntries`/
`replaceEntryExercise`/session-counting fixes, R11i's Programs-tab wiring).
Two real bugs were found and fixed by this verification pass itself, not
shipped: `asLogEntries()` initially suffixed EVERY row's id with an index,
including the single-exercise case, breaking the "byte-identical to
`asLogEntryView()`" promise (caught by this closure's own new test); the
whites-ratchet and floating-sheet design-system tripwires both fired
correctly on new code (3 new sanctioned translucent-white surfaces, one new
sheet needed `GlassCard(floating: true)` instead of a hand-rolled solid
container) and were resolved per their own established conventions, not
by loosening either test.

## 8. Device verification

No physical phone was connected to this machine when the release build ran
(`flutter devices`: only `emulator-5554` (Pixel_API_34, Android 14),
Windows desktop, Chrome, Edge — no ADB-connected hardware). The release APK
was built (`flutter build apk --release`) and installed on the emulator as
the strongest verification available in this session; the operator needs to
sideload the same APK onto their own device for the "real telefon" test.
See the turn's final report for the APK path, install/launch result on the
emulator, and the exact screens walked live.

### What each PARTIAL still owes

Each gate's own commit body carries the full list under "Что осталось
непокрытым". The short version:

- **R11h** — `launch` and `preparation` screens (they change WHEN the camera
  opens, which nine `start_lifecycle_test.dart` tests pin deliberately and
  which wants device verification first); `paused`/`summary` as real phases.
  A real settling signal for `calibration` does not exist, and the gate
  refuses to fake the design's percentage bar.
- **R11b** — the 13-step flow (a UX decision, not a port); `WheelYear`
  (needs birth-year in the profile model, which stores `age`);
  `BodyDiagram` selector; `ChoiceCard`.
- **R11f** — privacy gate, preview+retake, metadata (weight/note/milestone —
  the model already has all three fields and nothing sets them, which is
  also why R11g's compare card can only sometimes show a delta), export,
  reminder.
- **R11i** — Workouts' Programs/Library split, which needs a programme
  entity that does not exist; the Paywall.

### The programme entity, named three times

R11a's progress bar, R11d's "add to programme" button and R11i's Workouts
split all stopped at the same missing thing: this app has no multi-week
programme. `GeneratedPlan` (`mobile/lib/features/ai_planner/data/workout_plan.dart:4`)
is ONE day. Three gates worked around it honestly; a fourth should probably
build it rather than work around it again.

### No device verification, anywhere

Every gate above is `flutter analyze` + `flutter test` green and nothing
more. For a redesign that is the weakest possible evidence: none of these
screens has been rendered on the `Pixel_API_34` emulator or a phone. This
is the single largest gap in the whole sequence.

### Two gates still need an operator decision before they can be scoped

- **R11e** — does a `WorkoutSession` become multi-exercise / multi-set?
  The F3.4 decision (one exercise, at most one set per session) is what
  makes the design's player loop unbuildable as specified. Reversing it is
  a data-model change with a migration, not a layout change.
- **R11i, Paywall half** — 2 tiers or 3, and 7-day trial or 14. Both are
  monetisation calls. The Workouts and Profile halves have no blocker and
  can proceed alone if the operator wants the gate split.
