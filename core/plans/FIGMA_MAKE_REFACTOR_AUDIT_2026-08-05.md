# R0 / Gate 0 — Figma Make → Flutter audit (2026-08-05)

Read-only audit required by `DEV_SINGLE_FILE_MASTER_PROMPT_v1.8_EN.md`. No production
file was modified to produce it; the reference repository was cloned to a scratch
directory and neither repository was written to.

Method note: five specialist agents ran in parallel (screen/spec enumeration, decision
register, Flutter theme readiness, architecture/sequencing, test coverage). Every
load-bearing finding below was then re-verified directly against the file it cites.
Where an agent's claim and my own earlier claim disagreed, the disagreement is recorded
rather than smoothed over — see §11.

---

## 1. Git baseline

| | Production | Design reference |
|---|---|---|
| Repository | `xLZDx/Fitness-App` | `xLZDx/ReviewExistingExamples` |
| Branch | `master` | `main` |
| HEAD | `5b2fd70` | `8209787cd494439539b635080209cbadf5a780bc` |
| Committed | 2026-08-05 | 2026-08-05 17:54:22 UTC / 20:54 Europe/Chisinau |
| Upstream | `origin/master`, 0 ahead / 0 behind | — |
| Unpushed | none | — |
| Untracked | `core/vendor_clip_gaps_2026-08-05.csv`, `.xlsx` — unrelated to this refactor | — |

`xLZDx/Figma` also exists on the account and is **empty** (0 commits). It is not the
reference repository; do not clone it by name.

The reference repo is a Figma Make export: 52 files, one component (`src/App.tsx`),
five design specifications, a decision register, and 18 images.

---

## 2. Figma Make access

The web URL is **not usable as a design source**. Verified 2026-08-05:

```
GET https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples
http=200  bytes=769401  <title>Figma</title>
frames=0  screens=0  transitions=0
```

The response is the SPA shell; the prototype renders client-side after authentication.
Adding `?t=…`, `?fullscreen=1`, or `code-node-id=0-6` changes nothing (byte-identical
apart from a session nonce). No Figma MCP or Dev Mode is available in this environment.

One artefact *is* public: the file's cover thumbnail, 800×675 WebP, reachable through
the page's `og:image`. It shows a single screen titled "Research & Design System" —
which the master prompt itself classifies as an internal governance artefact, not a
production requirement. All size parameters (`&width=2400`, `&scale=4`,
`&resolution=full`) return the same 13,120-byte file, so no higher resolution exists.

**This does not block the audit, because the GitHub reference repository supersedes the
web link entirely.** The full design is readable there.

---

## 3. Screens visible in the design

`src/App.tsx` is **5,471 lines** — a genuine multi-screen prototype, not a stub.

### Root screens (`type Screen`, `App.tsx:27-40`)

| Screen | Purpose | Defined at |
|---|---|---|
| `research` | Internal governance dashboard — **the default boot screen** | `App.tsx:515` |
| `onboarding` | 13-step wizard | `App.tsx:2379` |
| `home` | Today hero, quick scan, recovery, weekly stats | `App.tsx:2441` |
| `scan` | Equipment recognition | `App.tsx:2555` |
| `equipment` | Equipment detail | `App.tsx:3009` |
| `exercise` | Exercise detail | `App.tsx:2781` |
| `workout-player` | Active set logging, rest timer as overlay | `App.tsx:3162` |
| `rest-timer` | **Dead union member** — never routed, never assigned | `App.tsx:35` |
| `workout-done` | Renders `WorkoutSummaryScreen` | `App.tsx:4620` |
| `form-check` | `const FormCheckScreen = TechCoachScreen` — an alias | `App.tsx:4615`, real component `:4220` |
| `paywall` | Subscription | `App.tsx:4984` |
| `variants` | Internal 3-way layout comparison tool | `App.tsx:5112` |

Nested: 5 bottom-nav tabs (`App.tsx:74`), 13 onboarding steps (`App.tsx:2379-2412`),
9 progress-photo flow states (`App.tsx:3907`), 8 Tech Coach phases (`App.tsx:4194-4202`).

### Built but never mounted

`WorkoutDone` (`App.tsx:3370`), `EmptyState` (`:5070`), `ErrorState` (`:5079`),
`PermissionState` (`:5088`), `StubScreen` (`:5098`). Zero JSX instantiations each.

### Everything is mocked

No `getUserMedia`, no `fetch`, no `localStorage` anywhere in the file. The scanner
returns one fixed result after `setTimeout(…, 2200)` (`App.tsx:2559-2560`). The Tech
Coach skeleton is a static hand-authored SVG (`App.tsx:4023-4143`) driven by
`setInterval`, not a pose model. Presence of a screen in the prototype is not evidence
of backend, ML, or storage support.

---

## 4. Design tokens — exact values

All hex values live in code only; grepping `#[0-9A-Fa-f]{6}` across the five markdown
specs returns zero matches. The markdowns name token identifiers; `App.tsx` assigns them.

### Dark palette (`App.tsx:4-18`)

| Token | Value | Current app equivalent |
|---|---|---|
| `bg` | `#06060F` | `AppPalette.darkSurface #050214` — different |
| `s1` / `s2` / `s3` | `#0D0D1A` / `#141422` / `#1B1B2C` | no equivalent |
| `acc` | `#C9FF47` | seeded from `auroraViolet` — different hue entirely |
| `ok` / `warn` / `err` | `#22E87A` / `#FFAA33` / `#FF4D70` | ad-hoc `AppPalette.aurora*` per call site |
| `fg` / `fg2` / `fg3` | `#F0F0F8` / `#888898` / `#3E3E50` | `onSurface` + alpha |
| `bd` / `bd2` | `rgba(255,255,255,0.07)` / `0.13` | inline in `GlassCard` |

### Extended semantic tokens (`App.tsx:188-207`)

`accentSecondary #A8D93A`, `cameraOverlay rgba(0,0,0,0.55)`, `poseCorrect #22E87A`,
`poseWarning #FFAA33`, `poseError #FF4D70`.

**`poseCorrect/Warning/Error` and `cameraOverlay` have no source at all in the current
app** — this is the single largest genuine gap the token work closes.

### Scales

- Spacing: `[4, 8, 12, 16, 20, 24, 32, 40, 48]` (`App.tsx:223`)
- Radius: `[8, 12, 16, 20, 24]` + Full (`App.tsx:224`)
- Typography: 11 roles with exact sizes/weights (`App.tsx:209-221`) — Barlow Condensed
  (Display 48/800 … H3 20/700) + Inter (Title 16/600 … Caption 10/500) + monospace for
  numerics. Fonts loaded at `index.css:1`. The app currently ships Inter only, with no
  scale.
- Motion: `index.css:76-90` — 0.3 s fade, 0.38 s slide, 1.4 s pulse ring, 3 s breathe.
- **Not specified anywhere:** elevation/shadow scale, z-index scale, breakpoints. The
  prototype is a fixed 430×932 phone shell (`App.tsx:5448`).

### Light palette exists but is undecided

`App.tsx:790-805` defines a full light set (`bgPrimary #F2F2EE`, `accentPrimary
#4D7A00`, …) explicitly marked open. Operator decision 2026-08-05: dark first, light
behind a toggle later.

---

## 5. Screen → route → widget → provider mapping

| Design screen | Flutter route | Page | State | Classification |
|---|---|---|---|---|
| `onboarding` (13 steps) | `/onboarding` | `onboarding_page.dart` + 7 steps | profile providers | implemented, needs visual refactor |
| Body metrics pickers | — | inside `step_personal.dart` | — | **represented only in design** |
| `home` | `/home` | `home_page.dart` (656 lines) | home providers | implemented, incomplete |
| `scan` | `/scan` | `scanner_page.dart` (891) | `visual_equipment` | implemented, needs visual refactor |
| `equipment` | `/equipment/:id` | `equipment_detail_page.dart` | equipment providers | implemented and close |
| `exercise` | — | study content lives in `workout_player_page.dart` | equipment providers | **implemented in the wrong place** — see §7 |
| `workout-player` | `/workout/:id` | `workout_player_page.dart` (39 KB) | set_timer providers | implemented |
| Rest timer | — (overlay in design too) | `workouts/widgets/rest_timer.dart` | `RestTimerController` | implemented, unwired |
| `form-check` | `/form-check` | `form_check_page.dart` (1147) | `form_check_providers` | implemented, takes no exercise parameter |
| `workout-done` | — | — | — | **missing in both** (see §8, Q26) |
| `progress` | `/progress` | `progress_page.dart` | workout stats | implemented, one chart |
| Progress photos (9 states) | `/photos` | `progress_photos_page.dart` | **Mock repository** | scaffold only |
| `paywall` | `/subscription` | `subscription_page.dart` | `effectiveTierProvider` | implemented |
| `research` / `variants` | — | — | — | **internal tooling, out of product scope** |

Production routes: **28** (`path: '` in `app_router.dart`).

---

## 6. Missing states

| Surface | Design specifies | Prototype implements | App implements |
|---|---|---|---|
| Scanner | 14 (`fitness-app-redesign.md:487-500`) | 3 (`App.tsx:2553`) | rich — 9 widget classes |
| Tech Coach | ~30 (`tech-coach-module.md:723-803`) | 14 (`App.tsx:4194-4204`) | 6 gate verdicts |
| Progress photos | 13 (`progress-photo-compare.md:376-392`) | 9 (`App.tsx:3907`) | scaffold |
| Body metrics | 15 (`body-metrics-onboarding.md:212-231`) | value-only | none |

Neither design nor prototype specifies any state for `EquipmentScreen`,
`WorkoutsScreen`, `ProfileScreen`, `PaywallScreen`, or the AI Coach panel. Those must be
derived from the design system and the derivation documented, per §28 of the prompt.

**Camera permission states: specified 6, implemented 0** in the prototype.

---

## 7. Conflicts with the repository

### 7.1 Q26 is a phantom blocker

The register asks (`OPEN_DECISIONS_REGISTER_v1.3.md:144-147`) whether Workout Summary
should "Replace existing WorkoutDone" or be layered after it. Verified: **neither
`WorkoutDone` nor `WorkoutSummary` exists anywhere in `lib/` or `test/`** — zero grep
matches. And they were never two screens in the prototype either: `'workout-done'` is
the id that renders `WorkoutSummaryScreen` (`App.tsx:5465`), while the component named
`WorkoutDone` (`App.tsx:3370`) is defined and mounted nowhere, superseded per its own
comment (`App.tsx:4618`).

There is nothing to consolidate. Q26 should be closed as built on a misreading; the work
is a net-new screen.

### 7.2 There is no workout-session entity

`WorkoutLogEntry` (`workout_log.dart:30-61`) carries one exercise: no `sessionId`, no
set collection. `ScheduledSession` is likewise single-exercise. The only multi-exercise
type, `GeneratedPlan`, is computed on demand and never persisted.

The design's Home hero ("Спина и бицепс, 7 упражнений · 48 минут") and the entire
Workout Summary both require an entity that does not exist. The app is at `1.0.0+14`
with live Firestore data, so this is a migration, not a greenfield model.

**This is the finding that reorders the whole plan** — see §10.

### 7.3 Exercise Page is not missing, it is misplaced

`/workout/:id` already renders the full Exercise Page content: hero, video with poster,
muscle map, technique steps, contraindications, suggested weight
(`workout_player_page.dart:145-211`). Creating `/exercise/:id` as a *new* page while the
player keeps that content would fork "how to show an exercise" into two sources of
truth. The correct work is a **split**, not an addition.

### 7.4 Technique Coach supports one exercise, not 1,887

`enum FormExercise { squat, pushup, deadlift }` (`form_check_providers.dart:18`).
`deadlift` has no pose target; push-up rep counting does not work
(`pose_target.dart:172-177`). Effectively one exercise works. The catalog holds 1,887.

### 7.5 `pose[pixels]` ships in release, and the design calls it a defect

`form_check_page.dart:340-351` renders the diagnostic unconditionally; the string is
built at `pose_unit_probe.dart:66`. The comment at `:335-339` says this is deliberate
until a measurement is taken. **The measurement has been taken** — the operator's own
recording shows `pose[pixels] n=807 x -0.466..1.968 (bound 0.667) y -2.173..3.015`,
i.e. 807 frames, with landmark coordinates far outside the normalised `0..1` range. That
is a coordinate-projection defect, and it explains overlay misalignment (§18.10). The
design spec quotes the string verbatim as a defect (`tech-coach-module.md:307`).

**CLOSED 2026-08-06 (gate F4).** The line is now behind `poseDebugOverlayProvider`,
which defaults to `kDebugMode`; the probe no longer even measures in release.
`test/features/form_check/debug_overlay_release_test.dart` is the test the master
prompt §18.5 asks for by name, with a positive control on each half so neither
assertion can pass by the page failing to build.

The *measurement* it produced is a separate, still-open defect: those extents are
outside the contract `pose_coordinate_space.dart` declares (`y ∈ [0,1]`,
`x ∈ [0, aspectRatio]`), which is why the instrument was kept rather than deleted.
Tracked under §18.10 overlay work, not under F4.

### 7.6 The app makes a cryptographic promise it does not keep

`app_en.arb:194`: *"Photos are encrypted on your device with a key that never leaves the
phone. We never sell health data."* Also `:174`, `:193`.

- `_PrivacyStrip()` renders **unconditionally** — `progress_photos_page.dart:39`.
- `AesPhotoCipher` (real AES-256-GCM) has **zero call sites** in `lib/`.
- The bound repository is `MockProgressPhotosRepository`, writing
  `storagePath: 'mock://…'` and `keyFingerprint: 'mockfp'` with no cipher invocation.

Same class of defect as S0b and P0, applied to health data and to a cryptographic claim.
**Operator decision 2026-08-05: remove the claim now, keep the capability in the
backlog.** This is independent of the refactor and should not wait for it.

### 7.7 Rest timer cannot notify

`RestTimerController` is instantiated inside `_RestTimerState` (`rest_timer.dart:90-91`),
so it dies on unmount. The spec's "notification/haptic on completion" is structurally
impossible today. `flutter_local_notifications` and `timezone` are already in
`pubspec.yaml` and unused for rest.

### 7.8 Reference screenshots are already stale

The nine JPGs in the reference repo are phone captures, six taken 2026-08-05 at 14:20.
One of them shows the day-3 modal still claiming nonprofit status and physiotherapist
review — both removed by S0b later the same day. Do not treat them as current app state.

---

## 8. Decision register

44 questions, split 22 (D1–D5 + D7) / 8 (D6) / 14 (D8–D9). Independently recounted; the
register and the master prompt agree, and the file itself records that an earlier
26/8/10 split was wrong (`OPEN_DECISIONS_REGISTER_v1.3.md:12`).

**Only one question is actually decided**: Q39 = `LOCKED — Flutter` (`:203-206`).
Three carry provisional defaults (Q22, Q24, Q25). The remaining 40 are open.

Five are labelled HARD BLOCKER — Q19, Q20, Q21, Q23, Q26 — but two of those do not
survive contact with the code:

- **Q19** ("real on-device ML or demo prototype?") is already answered by the code:
  `google_mlkit_pose_detection`, 16 modules, 19 test files. The question is stale.
- **Q26** is a phantom (§7.1).
- **Q21** is mis-owned to Sport Science. The code supports exactly one camera angle
  (`pose_target.dart:107-113`), so the exercise→angle matrix is an ML capacity question
  first and a sports-science document second.

Decisions recorded from the operator on 2026-08-05:

| Question | Decision |
|---|---|
| Q27 photo storage | **A — local only** |
| Q1 / Q41 light theme | Dark first, matching the new screens; light later behind a toggle |
| False encryption claim | Remove now, keep capability in backlog |

Decisions the register does not contain but the work needs: chart library; whether
`/exercise/:id` and `/workout/:id` coexist; Firestore migration strategy for existing
`WorkoutLogEntry` rows; catalog-exercise → `FormExercise` mapping.

---

## 9. Reusable tokens and components

The current theme is a better substrate than the plan assumes:

- `ColorScheme.fromSeed` Material 3 base (`app_theme.dart:12-17`) — correct foundation
  for a `ThemeExtension` token layer.
- `withOpacity` fully migrated to `.withValues` — 0 vs 193 occurrences.
- No `Widget _build*()` anti-pattern anywhere — 0 matches across `lib/`.
- `core/CONVENTIONS.md:50-52` already states the rule the plan wants to enforce.

Roughly **10 of the ~37 planned components already exist** as clean widgets:
`GlassCard`, `GlassAppBar`, `FrostedScaffold`, `GlassNavBar`, `AuroraBackground`,
`SmoothScrollList`, `DemoDataBanner`, `SetTimerCard`, `RestTimer`, `ExerciseThumb`,
`MuscleMap`, `HealthSyncCard`. Three more are duplicated private classes awaiting
extraction rather than construction: gradient tile, pill/chip (three implementations),
stat card (two).

Two things must be preserved as behaviour, not flattened into tokens: `GlassCard`'s
`blur: false` default and its `floating` opacity math (`glass.dart:25-50`) each encode a
shipped, operator-reported bug fix, and neither has a dedicated test.

`CustomPainter` cannot read `Theme.of(context)` inside `paint()`. `_SkeletonPainter`
(`form_check_page.dart:455`) and `_SilhouettePainter` bake palette colours in directly;
tokens must be threaded through their constructors. Non-obvious migration cost on the
most safety-relevant surface in the app.

---

## 10. Recommended gate sequence

The prompt's stated order (R1 Home → … → R9 theme) is wrong in four places given §7.2,
§7.3 and §9. Proposed order:

**Foundation — no user-visible change**

- **F1** Semantic token layer as `ThemeExtension`, values initially mapped to today's
  palette so the visual diff is nil. Exit criterion is falsifiable: zero visual change,
  suite green. Token *names* are fully enumerated by the design, so this is
  transcription, not speculative design.
- **F2** `AiCoachContext` type; migrate the single existing call site
  (`equipment_detail_page.dart:116`). ~30 lines, prevents rework in three later gates.
- **F3** Workout-session entity + repository + Firestore migration + aggregate providers.
- **F4** Delete `form_check_page.dart:340-351`. One line, unblocked, live defect.
- **F5** Remove the false encryption strings (operator decision, §7.6).

**Feature gates**

R1 Rest Timer → R2 Scanner → R3 Exercise/Player split → R4 Home → R5 Workout Summary →
R6 Progress charts → R7 Progress Photos → R8 Technique Coach → R9 light theme, platform,
accessibility.

Rationale for the moves:

- **Home is not first.** It is the gate most dependent on the missing session entity;
  building the hero against a single-exercise model means building it twice.
- **Tokens are not last.** 194 uses of `GlassCard`/`FrostedScaffold`/`GlassAppBar` across
  41 files, and the target changes the seed from violet to lime `#C9FF47`, which moves
  every derived Material role at once. Splitting the token layer (F1) from the re-skin
  (R9) turns R9 into a value change in one file.
- **Rest Timer is first among features.** Zero dependencies, and it is the cheapest
  end-to-end proof of the token layer plus the notification plumbing on a real device.
- **Technique Coach is last.** It needs the exercise identity R3 produces (`/form-check`
  takes no parameter today) and carries the largest engineering unknown.

---

## 11. Corrections to earlier claims in this audit

Recorded because a claim that was wrong once will be repeated unless it is named.

1. **"Route count is 33."** Wrong — 28. I counted `GoRoute(` including nesting instead
   of `path: '`.
2. **"The design accent matches `auroraLime #C2F562`."** Wrong. That was measured from a
   compressed 800×675 thumbnail, which is not evidence. The real token is `#C9FF47` on
   `#06060F`; the design defines its own palette rather than reusing the app's.
3. **"A token migration will mass-break golden tests."** Wrong — there are **zero**
   golden tests (`matchesGoldenFile`: 0 matches; no reference PNGs). The real risk is
   the inverse and worse: `flutter test` will stay green regardless of what happens
   visually, so the screenshot comparison the prompt mandates is the only visual control
   that will exist.
4. **"Form Check and subscriptions are thin-coverage risk areas."** Wrong on both. Form
   Check is the best-covered area in the app (19 test files, including
   `pose_coordinate_space_test.dart` and `pose_projection_test.dart`); `effectiveTier`
   has a full edge-case table. The real gaps are `RestTimer` and `SetTimerCard` (zero
   widget tests despite covered controllers), set-logging integration
   (`workout_player_page.dart:650-718`), and scanner fallback paths.
5. **CODEMAP is stale** in four places: router 296 vs 372 lines; Home 594 vs 656; tests
   131 files/1002 vs 153/1275; and it states the injury filter gates nothing (0 of 1,887
   tagged). That last one is materially wrong now — 1,435 of 1,887 exercises carry
   contraindications, covering all eight screened regions (neck 117, shoulder 486,
   elbow 371, wrist 188, lower_back 312, hip 404, knee 362, ankle 229), with zero tags
   outside the vocabulary. The published Terms' wording remains accurate.

---

## 12. Risks, ranked

1. **Session entity assumed by two gates but absent.** Building Home and Summary before
   F3 means writing new data in the old shape and migrating afterwards — the expensive
   order.
2. **Quality gates that the pipeline cannot produce.** The design wants 11 gate states;
   `PoseGateVerdict` has 6 (`pose_gate.dart:39-67`). Luminance and blur need raw frame
   bytes; "multiple people" needs a detector-mode change. The failure mode is inferring
   the missing states from landmark likelihood and telling the user "add light" when the
   real problem is angle — regression into precisely the failure `pose_gate.dart:1-18`
   was written to eliminate.
3. **A "Check technique" CTA on unmapped exercises.** With one working exercise, putting
   the button on every exercise page scores 1,886 of them against a squat target.
   Confidently wrong feedback is worse than no feature.
4. **No visual safety net.** See §11.3.
5. **Guard tests will go red and the pressure will be to weaken them.**
   `reachability_test.dart` fails any route without a navigator — correct, and it means
   R3 cannot land `/exercise/:id` unlinked. `no_untranslated_strings_test.dart` bans
   hardcoded English, but its regex misses the ternary form, and `rest_timer.dart:163-176`
   is live proof: three English sentences shipping past a green suite. If R1 touches the
   timer, fix the regex in the same commit.
6. **Web idioms crossing into Flutter.** The four concrete temptations: the `Screen`
   union as a router (would abandon `resolveRedirect` and deep links); inline
   `CSSProperties` threading (bypasses `ThemeData`, the thing that makes R9 possible);
   the pixel-math wheel/ruler pickers (`App.tsx:1633, 1712, 1850` — Flutter has
   `ListWheelScrollView` with real physics, and a ported DOM-scroll picker breaks at the
   text scales §25 mandates); and prototype fixtures becoming a second source of truth.
7. **`ResearchScreen` + `DecisionRegistry` are ~30% of `App.tsx`** and boot first.
   Anyone reading the reference top-to-bottom hits internal tooling before the product.

---

## 13. Status

`STOP — no production file modified.` This document is the only file written, under an
explicit operator GO. Both repositories are unmodified; the reference clone lives in a
scratch directory outside either tree.

Next action requires a separate GO per gate.

---

## 14. What changed after this snapshot (added 2026-08-06 on commit)

This document was written on 2026-08-05 and committed a day later, after several of its
own findings had been acted on. The body above is deliberately **not** rewritten: it is
evidence of what was true when the audit ran, and editing it in place would destroy the
only record of that. This section is the delta, so nobody reads a stale finding as
current.

| Section | Then | Now |
|---|---|---|
| §7.4 Technique Coach supports one exercise | one movement works, catalog holds 1,887, nothing connects them | `poseTargetId` tags **540** rows across 8 patterns (`scripts/catalog/tag_pose_targets.py`); `formCoachSupports` (`form_check_providers.dart`) gates the entry on authored targets **and** a rep signal, so exactly **one** pattern — squat, 37 rows — offers the coach. The gap between 540 and 37 is now explicit in code rather than absent from it. Commits `6a55fa0`, `0d0bc27`. |
| §7.6 cryptographic promise not kept | `_PrivacyStrip()` rendered unconditionally; `AesPhotoCipher` had zero call sites | The claim is gated on `progressPhotosAreDemoProvider` in all **five** places it appeared — the audit found three, a full grep found five, including one written into the user's own downloaded export file. `AesPhotoCipher` now has a real caller: the passphrase-encrypted transfer backup. Commits `7a878da`, `108d6df`, `532fd28`, `10ff4f6`. |
| not in this audit | — | The health questionnaire no longer reaches the server at all. Nothing server-side ever read it; 14 documents that already held it (in the pre-move Firebase project) were cleared, verified by a read-only query returning 0. Privacy Policy and the Play Data safety answers follow. Commits `b5e2e11`, `2f206b1`, `7deca06`. |

**Unchanged and still open:** §7.1 (Q26 is a phantom blocker), §7.2 (no workout-session
entity), §7.3 (Exercise Page misplaced), §7.5 (`pose[pixels]` ships in release, and the
measurement that justified removing it has been taken), §7.7 (rest timer cannot notify),
§7.8 (reference screenshots stale). The gate sequence in §10 stands.

**One correction to §10's ordering, from the operator, 2026-08-06:** device-level
verification that asserts on the *shape* of a current screen — widget keys, card
placement, scroll behaviour — is not worth writing before the refactor replaces that
screen. Verification that survives it is: that an asset really reaches the APK, that a
background isolate really performs the work. Both kinds were written on 2026-08-06; only
the second kind was kept (`integration_test/app_test.dart`).
