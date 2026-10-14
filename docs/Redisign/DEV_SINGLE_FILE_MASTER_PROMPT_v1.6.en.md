# Fitness App — Single-File Development Master Prompt v1.6 (English Historical Companion)

**Original:** [`DEV_SINGLE_FILE_MASTER_PROMPT_v1.6.md`](DEV_SINGLE_FILE_MASTER_PROMPT_v1.6.md), immutable original blob `d3b5e7702a2cfbbe0c53c32d8abfd5784f05d0ff`. This document translates the **35 numbered implementation sections** plus the subsequent original **v1.3 governance update**, **v1.6 Figma Make handoff protocol**, **incomplete-prototype policy**, **embedded R0–R9 completion scope**, provisional product choices and required test matrix.

**Status and precedence:** Historic engineering handoff, **not** the latest approved v2.0 specification, a grant of push permission, proof of a working application or authorization to change code. All original programmatic names, source-code paths, section/gate identities and scope/decision boundaries remain intact. When newer approved documents and operator permissions supersede this snapshot, the current exact Git HEAD and owner-held decisions prevail. No production change is made by creating the English counterpart.

## Primary sources and precedence

**Role:** Senior Flutter engineer, mobile UI architect, product engineer and fitness/health implementation specialist.

**Target project:** [Fitness-App GitHub](https://github.com/xLZDx/Fitness-App).  
**Original Figma Make reference:** [Review Existing Examples](https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples?t=PknUCnJWYLxe5itJ-1).  
**Historical handoff version:** v1.6.

Implement a staged, safe UI refactor of the existing Flutter app using **Figma Make for approved visual/interaction intent** and **the exact repository and tests for actual behavior, data, persistence, security, backend contracts and available features**. Existing Flutter theme/components determine token implementation until an explicit mapping is approved. This prompt governs its historic scope, gates, invariants and execution discipline.

When sources conflict:

- Do not reproduce impossible or mock-only Figma behavior as a real feature.
- Do not remove working application capabilities because a prototype frame omits them.
- Do not fabricate data, confidence scores or AI.
- Record discrepancies in the **Gate 0 audit** and propose a conservative resolution.
- **STOP for operator GO before modifying schema, privacy, billing, ML pipeline or user data**.

At G0 inspect which Figma materials are really accessible: preview, screens, interactions, conversation history and generated project files when permissions allow. If inaccessible, name missing inputs, continue read-only code inspection, use available exports/screenshots and **STOP before visual implementation requiring unverified references**. Figma-generated React/CSS/HTML/router/browser-storage must **not** be transferred into Flutter production. Do not start a new Flutter project, migrate to FlutterFlow, or rewrite the architecture. First fetch/pull and pin the exact branch HEAD.

## 1. Objective

Transform the existing tile-heavy interface into a modern, goal-driven, context-aware exercise assistant while preserving business logic, user data, machine recognition, workout lifecycle and privacy invariants.

Required end-to-end journey:

`Onboarding → Body Metrics → Plan Preview → Home → Scan → Equipment → Exercise → Workout Player → Rest Timer → Form Check → Summary → Progress → Progress Photo Comparison`.

Figma is the design reference; repository/code is the actual feature source. Report a conflict rather than guessing missing behavior.

## 2. Preserve the existing stack

Keep **Flutter/Dart, Riverpod, go_router, feature-first architecture, Firebase Auth, Firestore, Firebase Functions, current camera and ML services, catalog loaders, workout services, localization and tests**.

Without a separate architecture GO, **do not** introduce Bloc/GetX/MobX, another router, parallel state framework, new backend schema, a second recognition pipeline, FlutterFlow or a complete feature rewrite.

## 3. Gate 0 — mandatory READ-ONLY audit

Before any changes:

**Git:** branch, HEAD, upstream, status, unpushed commits, untracked files and concurrent changes.

**Documentation:** `CLAUDE.md`, `core/TECHSTACK.md`, `core/CODEMAP.md`, current state/gate records, changelog and current theme/routing documents.

**Code inventory:** theme/tokens, navigation shell, onboarding/auth, profile models, Body Metrics, Home, Scanner, Equipment, Exercise, Workout Player, Rest Timer, Form Check, Progress, Progress Photos/media, Programs, AI Coach, subscription, Health Connect, storage/share/permissions and tests.

Map **Figma screen → actual route → widget → provider/service → model → missing capability → risk → test → planned gate**.

Report hardcoded colors/strings, repeated cards, oversized widgets, business logic in presentation, expensive rebuilds, lifecycle risks, missing states and schema/privacy conflicts.

**After G0 submit a detailed implementation plan, then STOP. No files changed, no commit, no push.**

## 4. Architecture rules — all fifteen

1. UI does not own business rules.
2. Do not duplicate sources of truth.
3. Keep providers/services responsible for domain behavior.
4. Do not add a repository layer merely to style presentation.
5. Change models only for proven necessity.
6. Backend schema requires a separate operator GO.
7. Recognition pipeline is out of scope of a UI gate.
8. Workout calculations need separately approved scope.
9. Injury filtering is not changed during visual refactor.
10. Do not invent subscription products.
11. Never use fake production data.
12. Route user strings through localization.
13. Never expose internal exceptions to users.
14. Leave unrelated files unchanged.
15. Do not silently widen scope.

## 5. Design system refactor

Order of work: **tokens → components → screens**, adapted to the actual repository. Suggested theme files in `lib/core/theme/`:

`app_theme.dart`, `app_palette.dart`, `app_semantic_colors.dart`, `app_typography.dart`, `app_spacing.dart`, `app_radius.dart`, `app_elevation.dart`, `app_motion.dart`, `app_component_sizes.dart` and `app_breakpoints.dart`.

Required exact semantic names: `backgroundPrimary`, `backgroundSecondary`, `surfacePrimary`, `surfaceElevated`, `surfaceInteractive`, `textPrimary`, `textSecondary`, `textDisabled`, `accentPrimary`, `accentSecondary`, `success`, `warning`, `danger`, `outline`, `cameraOverlay`, `poseCorrect`, `poseWarning` and `poseError`.

Avoid arbitrary Color values, EdgeInsets, TextStyles and corner radii scattered across feature widgets. Dark and light are distinct **semantic configurations**, not theme inversion.

## 6. Component library

Minimum reusable presentation components — preserve exact proposed identifiers:

`AppPrimaryButton`, `AppSecondaryButton`, `AppTertiaryButton`, `AppIconButton`, `AppTopBar`, `AppNavigationBar`, `AppChoiceCard`, `AppMultiSelectCard`, `AppChip`, `MuscleChip`, `EquipmentChip`, `RecommendationHero`, `GoalProgressCard`, `RecoveryStatus`, `WorkoutCard`, `ProgramCard`, `ExerciseMediaCard`, `EquipmentMediaCard`, `AIInsightCard`, `BodyMetricPicker`, `SetLogger`, `WeightInput`, `RepsInput`, `RestTimerCard`, `CameraTargetOverlay`, `RecognitionResultSheet`, `ConfidenceIndicator`, `EmptyState`, `ErrorState`, `OfflineState`, `PermissionState`, `LoadingSkeleton`, `WorkoutBottomControls`, `FormCheckCue`, `WorkoutSummaryMetric`, `ProgressPhotoCard`, `ProgressPhotoTimelineItem`, `ProgressPhotoCompareView`.

Do not build a giant `AppCard` with dozens of optional arguments. Pure presentation components should not depend directly on feature providers.

## 7. Localization and units

Route all new text through existing localization, including **RU/EN**, pluralization, kg/lb, cm/ft, date/time, long Russian labels, accessibility names, permission explanations and errors.

No hardcoded English in the Russian app UI. Unit conversions must preserve precision and avoid repeated conversion drift. Find canonical stored units from current models. If missing, **propose a unit policy and STOP for GO**.

## 8. Onboarding refactor

The eighteen stages, in source order:

1. Value proposition
2. Goal
3. Experience
4. Location
5. Equipment
6. Schedule
7. Limitations
8. Target muscle areas
9. Main obstacle
10. Birth year
11. Height
12. Current weight
13. Target weight
14. Health Connect
15. Generating
16. Plan preview
17. Account
18. Contextual notification permission

One primary question per screen, progress indicator, back navigation, resumable draft, optional-only skip, useful **plan preview before account/paywall**, no fake progress/goal forecasts, and no push permission before it is relevant. Reuse current onboarding/profile models; missing persistent fields require a **minimal schema proposal then STOP for GO**. Plan preview must use the real generator/fallback, not a fake production fixture.

## 9. Body Metrics

### 9.1 Reusable BodyMetricPicker

Variants `birthYear`, `height`, `currentWeight` and `targetWeight`; wheel/ruler, direct input, haptics, accessible minus/plus, kg/lb, cm/ft, light/dark, large text, persisted draft/resume.

### 9.2 Pure calculations

**Do not store derived values as independently persisted facts in Firestore.** Preserve the original formulas and denominators:

```text
bmi = currentWeightKg / (heightMeters * heightMeters)

adultReferenceMinKg = 18.5 * heightMeters * heightMeters
adultReferenceMaxKg = 24.9 * heightMeters * heightMeters

targetDeltaKg = targetWeightKg - currentWeightKg
targetDeltaPercent = targetDeltaKg / currentWeightKg * 100

aboveRangePercent =
  (currentWeightKg - adultReferenceMaxKg) / adultReferenceMaxKg * 100

belowRangePercent =
  (adultReferenceMinKg - currentWeightKg) / adultReferenceMinKg * 100
```

Document every percentage's denominator. **Adult BMI categories only for age 20+**. Under-20 users do not see adult classifications. Derived formulas must handle missing/zero height/current weight safely.

### 9.3 Neutral feedback

Inside-range, below-range, above-range, height missing, age missing, under 20, muscular-body limitation, target outside reference range, or target absent. **No diagnosis or body shaming.**

## 10. Health Connect

Request permission **only after explicit CTA**; preserve existing integration contracts. Do not promise recovery functions without evidence. Handle unsupported device, denied/permanently denied, partial permissions, disconnected, stale data and reconnection.

## 11. Navigation

Five tabs: **Home, Scan, Workouts, Progress, Profile**. Preserve existing route names and deep links where possible. Verify Android system/predictive back, iOS swipe-back, restoration, preserved tab/scroll state, safe areas, edge-to-edge and keyboard insets.

## 12. Home

Order **Greeting → Program progress → Today hero → Start/Continue → Quick Scan → Recovery → Weekly progress → Last achievement → Progress Photo card if applicable**.

Every unit needs loading/data/empty/error states. Avoid watching all providers, and do not rebuild the entire page each second. Show progress photos only with **at least two compatible images**.

## 13. Scanner

No recognition-service rewrite as part of visual work. Preserve cloud recognition, timeout, local fallback, aliases, unknown handling and history.

UI states: permission, ready, analyzing, success, alternatives, unknown, timeout, offline fallback and actionable error. No infinite spinner or fake confidence. Never replace unknown equipment with the closest incorrect catalog match. Respect actual frame privacy policy.

## 14. Equipment page

Reuse `equipmentHeroImageProvider` or the current equivalent. Hero uses a **licensed, truly linked exercise poster**, never arbitrary stock photos. Include hero, name/category, purpose, muscles, suitability, safety, featured exercise, compatible exercises, AI Coach and add-to-workout. Lazy media, stable keys, thumbnail-first; do not change equipment mapping in a UI gate.

## 15. Exercise page

Use **real** posters/clips, muscles, equipment, instructions, restrictions, history and existing AI service. Poster before video playback. Correctly pause playback on background, dispose controllers, prevent audio leaks and restore orientation.

## 16. Workout Player and set logger

Presentation of current exercise/set, total sets, weight/reps, previous result, timer/rest and duration must reflect persisted authority.

On **Complete Set**:

1. Persist through the current domain source of truth.
2. Show confirmation.
3. Offer Undo.
4. Start Rest Timer once.
5. Advance using current domain rules.

Do not create ephemeral presentation state diverging from persistence. Timer isolated from whole-page rebuild. Guard finish action.

## 17. Rest Timer

Remaining time, next target, skip, +30 seconds, pause/resume, completion haptic/notification and background lifecycle.

Test **start once**, no duplicate clocks, add time, skip, pause/resume, background/foreground and completion.

## 18. Technique Coach / Live Form Check — safety-critical subsystem

This is **not simply a camera widget**. Do not rewrite pose detector, classifiers, thresholds, camera/ML pipeline or underlying models in a visual gate without explicit separate GO.

### 18.1 Required read-only Form Check audit

Discover and record supported exercises and angles; detector and runtime; landmark coordinate space; required joints by rule/classifier; in-frame/visibility, light/blur, angle gating; rep counter state machine, thresholds/hysteresis; cue priority/cooldown; TTS; camera lifecycle and frame rate; actual privacy/frame retention; debug overlays exposed to UI.

The original identified literal debug strings like `pose[pixels]...` in production presentation. Remove such copy **only through properly scoped changes**, retaining optional explicit non-release debug mode.

Record the required pipeline:

`Camera Frame → Pose Detector → Frame Quality Gate → Required-Joint Visibility Gate → Angle Gate → Exercise Classifier/Rule Engine → Rep Counter → Cue Gate → UI State → TTS`.

Never fuse all these into one giant widget.

### 18.2 Architecture contracts

Prefer/reuse existing equivalents for `PoseFrameResult`, `FrameQualityResult`, `VisibilityGateResult`, `AngleGateResult`, `MovementPhase`, `RepEvent`, `TechniqueCue` and `TechniqueCoachState`. Do not duplicate models. The UI **does not compute joint angles or decide whether a repetition counts**; it only renders domain/application state.

### 18.3 Contextual entry

Require `exerciseId`, supported/required angle, workout/session ID where relevant, expected orientation and actual supported capability. Entries: Exercise Page; Workout Player; optionally pre-set setup. Unsupported exercises have a frank "not supported" state, not a generic classifier.

### 18.4 Precheck

Use real exercise title, angle, camera placement, visibility requirements, privacy statement grounded in actual implementation and camera CTA. **Never claim on-device processing without evidence.**

### 18.5 Camera presentation

Top bar back/title/flash/sound/help; dominant camera; silhouette; landmarks/skeleton; segment state; quality banner; repetitions; movement phase; one current cue; pause/finish.

Forbidden user-visible text: raw landmark arrays, `pose[pixels]`, raw model confidence, rule IDs, stack traces, classifier names or logs. Debug overlays only with explicit flag in **non-release builds**. Add release UI test rejecting debug text.

### 18.6 Frame quality gates

Before rep counting, verify supported preconditions: initialized camera, enough light, blur/stability, exactly one person **if detector supports that**, acceptable scale/distance, required visible joints/body regions, required angle, pose confidence and completed calibration.

Every gate returns a machine-readable reason, localized user message, severity and recoverability flag.

While any required gate fails: **rep counter frozen; no rep event; no score; no positive/negative form verdict; no misleading positive TTS**.

### 18.7 Rep counting invariants

Run only after ready/calibrated; reuse movement state machine; hysteresis/debounce; never double-count, count during invalid frames or count a partial repetition after pose loss. Recover from short landmark interruptions without fabricated reps. Distinguish **detected versus reliably evaluated** counts. Test deterministic landmark/angle sequences.

If counting starts at the top position, explain this in normal UI/voice terms, not by publishing detector thresholds.

### 18.8 Live cue gate

At most **one primary cue**, with priority, cooldown, duplicate suppression, no overlapping TTS, and a shared localization key for spoken and visible text. Visibility loss outranks technique correction; do not repeat cues each frame; clear when corrected/timed out; keep cue history bounded.

### 18.9 Pose loss during a set

Enter paused/cannotEvaluate state; freeze count; reject incomplete rep; suspend technique scoring; offer actionable localized recovery; recalibrate/resume safely. Do not discard previously completed set results.

### 18.10 Overlay alignment

Use one camera-preview coordinate system, explicitly transforming for crop/fit, rotation, mirrored front camera, device orientation, aspect ratio, letterboxing and resized viewport. Test transforms deterministically or via widget/golden cases; skeleton must not drift away from the subject.

States `neutral`, `correct`, `warning`, `error` and `unavailable` require text/icon meanings, not color alone.

### 18.11 TTS/audio

Voice-off must leave visual feedback intact. Avoid overlapping utterances; handle lifecycle interruption, audio route/Bluetooth interruption, speech rate and TTS failure without blocking visual coaching. One localization source for spoken and displayed cues.

### 18.12 Privacy and recording

Preserve existing privacy architecture. The claim "on-device and no uploaded frames" requires code/network verification before display.

Default: **do not save raw frames or record video**, attach images to crash analytics, log user-linked landmarks, or implement video replay absent an explicitly approved opt-in feature.

### 18.13 Lifecycle/performance

Test permission flow, camera init failure, background/foreground, route pop/controller disposal, rotation, camera switching, wake-lock policy, thermal warning, frame backpressure, detector concurrency, queue bound, UI isolate responsiveness, overlay repaint isolation and sustained FPS on mid-tier Android hardware.

If processing lags, **drop stale frames**, not build an unbounded queue.

### 18.14 Summary

Use actual session events only: detected, evaluated, unevaluated reps; one/two defensible positive observations; one/two correction priorities; insufficient-data state; return/retry. No aggregate form score from too few reliable reps or promised replay without actual recording.

### 18.15 Required UI states

Unsupported exercise, angle selection, permission explanation/denial/permanent denial, unavailable camera, initialization, dark, blurred, too near/far, partial body, missing joints, wrong angle, multiple people, calibration, ready, countdown, live counting, warning/error cue, pose lost, paused, unevaluable rep, detector error, thermal warning, completed and insufficient-data summary.

### 18.16 Tests and critical invariant

**Unit/domain:** Each gate and precedence, angle/visibility, rep state machine, hysteresis, no double-count, invalid frames, pose loss/restore, cue priority/cooldown/dedupe, detected-vs-evaluated count, insufficient summary.

**Widget/golden:** All camera states with fake **UI-only** camera surface, overlay alignment, rep display, cues and quality banners, audio toggle, large text, RU/EN, high contrast, no debug strings.

**Device/integration:** Permission/lifecycle, camera start/stop, app restart/resume, rotation/mirroring, TTS interruption, processing soak, memory/controller leaks, thermal degrade.

**Absolute invariant:** **Never score or count a rep unless all required visibility/quality/angle gates pass.**

## 19. Workout Summary

Use recorded duration, sets, volume, personal records, subjective difficulty, real form feedback, recovery and next workout. No fake achievements. Progress-photo milestone prompt only when a real milestone condition is met, not after every workout.

## 20. Progress

Sections: consistency, workout count, volume, key exercise progression, goal progress, muscle load, recovery, measurements, Progress Photos, achievements.

No fake percentages; honest recovery labels. Charts have accessible descriptions, accurate axes/time periods, no misleading smoothing, true empty states and efficient repaints.

## 21. Progress Photos — private data subsystem

### 21.1 P0 storage/privacy audit

Inspect current camera/photo picker, local/cloud storage, Firestore metadata, encryption/access rules, account deletion, export, notifications, EXIF and source privacy claims. The storage policy requires a **separate explicit decision**, not silent choice:

**A Local-only** / **B Local-first plus opt-in backup** / **C Cloud-synced**.

### 21.2 Proposed model fields

`id`, `userId`, `capturedAt`, `angle`, `localPath`, optional `remotePath`, `thumbnailPath`, `weightKg`, `note`, `milestoneTag`, `createdAt`, `updatedAt`, `syncState`.

Angles: `front`, `sideLeft`/`sideRight` or canonical side per actual model, `back`, `custom/free`. No body-fat, body score or beauty score.

### 21.3 Privacy invariants

Private by default; no public URLs; no AI image analysis without explicit scoped opt-in; no photo data in analytics; deletion removes bytes **and** metadata; account deletion handles every image; export strips location EXIF; no sensitive file paths/tokens in logs; a failed sync never destroys the local original.

### 21.4 Capture

Select angle, silhouette, camera, timer, flash, switch, preview, retake/save, orientation normalization and optional metadata. **No saving before explicit confirmation**.

### 21.5 Timeline

Thumbnails, date, angle, optional weight, notes/tags, filters, multi-select, edit/delete/compare. Do not decode full originals in scrolling lists.

### 21.6 Compare

Side-by-side and overlay slider; swap, hide weight/date, fit/fill, select another pair, manual zoom/x/y/rotation/reset. **Original photos remain immutable. No body morphing.** Auto-align is a separate opt-in implementation gate after on-device feasibility check.

### 21.7 Export

Dedicated preview; deliberate hide/show weight/date, optional face blur, watermark, save/share, strip EXIF, **no automatic social publishing**.

### 21.8 Home card

Show only when at least **two compatible photos** exist, never above Today/Scan, and no empty card.

### 21.9 Reminder

Optional 2/4/8-week reminder or none. Request notification permission only after user agreement.

## 22. Workout library and programs

Filter/search/sort by goal, level, location, equipment, duration, muscles and physical limitations. No imaginary compatibility percentage or precision; use honest suitability labels.

## 23. AI Coach

Reuse existing AI service/cache with contextual entry from Equipment, Exercise, Workout, Summary, Recovery and Plan. States loading, cached, timeout, retry, offline fallback and appropriate safety notice.

Minimize shared personal data; changing server prompt/API contract needs separate approval.

## 24. Profile, settings and subscription

Profile/settings: personal data, goals, units, Health Connect, notifications, privacy, Progress Photo sync/storage only if approved, subscription and help.

**Do not change billing logic**. Display only real subscription products. Test product loading, none available, pending, success, error, cancelled, restore, already subscribed and offline.

## 25. Accessibility

Screen reader semantics/order, **44–48dp** controls, Dynamic Type scales **1.0/1.3/1.6/2.0**, contrast, non-color-only states, reduced motion, chart alternatives, non-drag controls, long Russian strings and safe areas. Avoid fixed-height cards for scalable user text.

## 26. Responsive and platforms

Test small/common/large Android, iPhone safe areas, landscape workout, usable tablets, keyboard insets, display cutouts and gesture navigation. **No separate pixel-perfect copy for every device.**

## 27. Performance

Historical target: **60 FPS** on mid-tier Android. Avoid whole-page timer rebuild, BackdropFilter on scrolling lists, eagerly decoding media, repeated parsing, unstable keys, leaked controllers and out-of-memory photo compare/export. Display poster before video, thumbnails in photo timeline and bounded decode/cache sizes.

Measure before optimizing: rebuild counts, frame times, memory, image decode, camera CPU, video lifecycle, export memory.

## 28. Universal error/empty/loading states

Every feature handles loading, empty, partial data, stale data, retryable error, terminal error, offline, denied/permanently denied and interrupted session. **No infinite spinner**.

## 29. Testing strategy

After **each approved gate**, run unit, widget, goldens/screenshots, integration when needed, existing regression suites, `flutter analyze`, real emulator, dark/light, RU/EN, large text and small/large viewport checks.

Critical flows: onboarding resume; body metrics math; plan preview; Home; all scanning outcomes; equipment/exercise media lifecycle; log/undo/rest; interrupted workout; Technique Coach gates/alignment/count/cue/visibility; summary; charts; photo capture/save/compare/delete/export; subscription.

**Do not update goldens without visual diff review.**

## 30. Screenshot comparison

For each approved Figma frame: match viewport; capture emulator/device screenshot; compare with reference; record spacing/type/color/alignment/state differences; fix proven deviations; never insert fake production data.

## 31. Gate sequence — preserve source identifiers

| Gate | Exact original scope |
| --- | --- |
| G0 | Read-only audit and Figma/code mapping |
| G1 | Design tokens |
| G2 | Core components and states |
| G3 | Navigation shell |
| G4 | Onboarding core |
| G5 | Body Metrics and Health Connect presentation |
| G6 | Plan preview and account flow |
| G7 | Home |
| G8 | Scanner |
| G9 | Equipment |
| G10 | Exercise |
| G11 | Workout Player / Set Logger |
| G12 | Rest Timer / workout lifecycle |
| G13A | Form Check read-only audit and contracts |
| G13B | Technique Coach precheck, permissions and quality presentation |
| G13C | Overlay, counting, movement phase and cue gate |
| G13D | Form Check summary, accessibility, lifecycle and performance |
| G14 | Workout Summary |
| G15 | Progress and Recovery |
| G16 | Progress Photos audit/storage decision |
| G17 | Photo capture/timeline |
| G18 | Photo compare/export/Home |
| G19 | Programs and library |
| G20 | AI Coach integration |
| G21 | Profile/settings/subscription presentation |
| G22 | Dark/light finalization |
| G23 | Accessibility/responsive audit |
| G24 | Performance audit |
| G25 | Screenshot regression and final polish |

A gate requires fresh operator GO after the prior report when the scope or risk changes. Translation does not supply such GO.

## 32. Gate report format — exact fifteen fields

1. Goal
2. Files inspected
3. Files modified
4. Behavior preserved
5. Behavior changed
6. Data/schema impact
7. Privacy impact
8. Risks
9. Tests added
10. Tests actually executed and results
11. `flutter analyze` results
12. Screenshot comparison
13. Remaining findings
14. Commit SHA
15. Push status

Never write "everything works" without evidence.

## 33. Git discipline — explicit original authority

Before every gate inspect Git status, branch, upstream, unpushed commits and concurrent changes. Stage only files in approved scope, do not touch unrelated untracked data.

**One gate → one local commit → STOP.**

**Push only with separately given push-GO.** The source expressly states that this rule **overrides any auto-push instructions** in that historical handoff. English translation of this rule is not new permission to commit, push or merge code.

## 34. Prohibitions

No app rewrite, needless Riverpod/router replacement, unapproved backend/ML/billing changes, function deletion, fake confidence/recovery/body analysis, public Progress Photo URLs, hardcoded English app strings, scattered arbitrary styles, giant widgets, heavy scrolling blur, silent scope expansion or push without push-GO.

## 35. Definition of Done — twenty source criteria

1. Goal-driven Home.
2. Scanner visibly differentiated.
3. Onboarding shows real value before account/paywall.
4. Correct/neutral BodyMetricPicker and calculations.
5. Reliable workout logging and Rest Timer.
6. Technique Coach with audited visibility/angle/quality gates, aligned overlays, deterministic counting, gated cues and **no invalid-frame scoring**.
7. Equipment uses licensed posters.
8. Progress uses real data.
9. Photos private, deletable, comparable, safely exportable.
10. AI contextual.
11. All relevant states implemented.
12. Dark/light match approved Figma.
13. Android/iOS safe areas and native behavior correct.
14. Accessibility verified.
15. Regression tests green.
16. No new analyzer issues.
17. Screenshots match approved reference.
18. Performance not degraded.
19. Per-gate scoped commit.
20. No push without push-GO.

**Start only at G0, output plan, STOP without modifying files.**

---

# Historical UPDATE v1.3 — Decision Governance and Architecture Locks

This section appears **inside the original v1.6 file** but is labeled a retained earlier governance update. Do not treat the date/version marker as a separate latest release.

## Complete decision register and totals

Maintain all **44** decision records with ID, gate, status, owner, blocking severity, context, alternatives, recommendation, final decision (only when actually made), rationale, dependencies, affected code/features, deadline gate and decision date.

The Figma ResearchScreen is an **internal stakeholder governance artifact**, not necessarily a production app screen.

Correct totals: **22** questions from D1–D5 + D7 completed-gate debt, **8** D6 items, **14** future D8–D9 items, total **44**. The old 26/8/10 grouping was wrong.

## Architecture locks and corrected questions

- **Q39:** Flutter/Dart, Riverpod, go_router, feature-first locked. No React Native rewrite, parallel native app or RN-based Form Check proposal.
- **Q19:** "Real on-device ML within the current Flutter stack, or demo/prototype mode?" Audit ML Kit/MediaPipe detector, TFLite, classifiers, camera and supported exercise rules before deciding.
- **Q1/Q41:** One Light Theme decision, two traceable IDs. Close via a single ADR/Product Decision Record, not separate conflicting implementations.
- **Q4:** Real Android and separately scoped iOS health integration; no fake "iOS coming soon" card without product GO. Define actual availability and avoid dead CTAs.

## Blocking and provisional policy

**D6 hard blockers:** Q19 ML scope, Q20 supported exercise list, Q21 exercise-angle matrix, Q23 TTS strategy, Q26 Workout Summary canonical route.

**Provisional defaults, not approved facts:** Q22 summary metadata only/no video or frames; Q24 app/system locale; Q25 human-readable confidence/reliability state, no raw percent. Each needs owner, expiry/review gate and explicit registry status.

For a blocker, **STOP, show impact/recommendation, await Product/Tech GO**. For deferred/nonblocking items, keep current behavior and record deferral, no scope creep. Each gate report lists decisions consumed/open, provisional defaults, architecture locks and newly found decisions. New decisions receive new IDs; do not overwrite Q1–Q44.

# Figma Make Handoff Ingestion Protocol — v1.6

Before G0, collect one coherent handoff package:

1. Figma file link with View/Dev Mode access
2. Approved page/section and version
3. Prototype link
4. Ready-for-development focus links
5. Exported Figma variables JSON
6. Exportable SVG/PNG/JPG assets
7. PNG/PDF reference screens
8. Screen-to-code mapping
9. Open Decisions Register
10. Approved Figma prompt and version

**Screenshots alone, without states, tokens or behavior annotations, are insufficient for implementation.**

Prefer Figma Dev Mode, Figma for VS Code or Figma MCP where genuinely accessible: inspect real frames, spacing, variables, variants and notes; **do not paste Figma CSS/React into Flutter**. Map variables deliberately to the current Flutter semantic theme and export only actual assets.

If direct Figma access fails, list unavailable details rather than inventing dimensions or transitions; require exact missing specs before visual implementation.

G0 audit file name: `core/plans/FIGMA_HANDOFF_AUDIT_<DATE>.md`. Record version, received files, accessible links, variables, assets, missing states, repo conflicts, route/provider mapping, open blockers and recommended gate order. **STOP after audit.**

Assets: SVG for icons, PNG/JPG for raster, no screenshots masquerading as production UI or baked-in labels; avoid duplicate media, check licences/privacy, stable names, optimize without visual loss.

Tokens: Figma variables are the **design source**, Flutter semantic theme the **code source**; create an explicit mapping table, do not scatter raw hex/spacing values and stop on unreconciled conflicts.

For every implemented screen: actual viewport, emulator/device screenshot, Figma comparison, logged deviations, **light/dark, RU/EN, large text and states**, and **no auto-accepting updated goldens without review**.

# v1.6 Policy — Incomplete Figma Make Prototype

Missing end-to-end wiring or omitted error/offline/device variants in the Figma Make prototype **do not automatically block engineering** when approved visual patterns and real source code establish the behavior. Equally, an attractive demo frame is **not** proof of working backend/ML/data. Inspect the active branch for each gap first.

The original embeds its remaining implementation scope in this single file; no external prompts are required for that historical handoff.

# Remaining Implementation Scope — Embedded R0–R9

## R0 — Mapping audit only

Create `core/plans/FIGMA_MAKE_REFACTOR_AUDIT_<DATE>.md` with exact Git branch/HEAD/upstream/status/unpushed/untracked; accessible Figma screens/states/transitions; mapping `screen → Flutter route → widget → provider → repository/service`; classification (implemented/aligned, implemented-needs-refactor, code-only, Figma-only, missing in both, decision-blocked or external-data/asset-blocked); reusable tokens; safely derived states; privacy/ML/storage/billing/schema risks; and exact R1–R9 file/test plan.

**STOP after report. No change, commit or push.**

## R1 — Home completion

Weekly calendar, milestones, horizontally scrolling recovery with obvious affordance/partial preview, loading/empty/error/offline, safe areas/responsiveness, and visual hierarchy **Today Workout → Scan → weekly/recovery → milestones/secondary**. Reuse approved components.

## R2 — Scanner and Equipment completion

Preserve scan history, saved machines, camera permission, analyzing/results/retry, unknown, offline/on-device fallback, network failure, low confidence, optional truly supported manual search, Scan→Equipment navigation and contextual AI Coach. **Never substitute the wrong nearby machine.** Reuse existing cloud/local recognition; ML architecture changes require GO.

## R3 — Dedicated Exercise Page

A separate route/page with stable `exerciseId` if missing, real licensed poster/animation, muscles, equipment/level, suitability rationale, technique/expanded guidance, mistakes, real contraindications, history/last performance, genuine record, Start/Add to Workout, Technique Coach, AI Coach and loading/media/no-history/unsupported/restricted/RU-EN/accessible states.

Keep workout state and logging **in Workout Player**, passing context rather than duplicating business logic.

## R4 — Technique Coach contextual entry

Reuse existing `/form-check` and real on-device pipeline **only if audit confirms them**. Add Exercise Page/Workout Player entries and optional supported summary retry, passing `exerciseId`, exercise name, supported classifier/rules, required angle, workout/session ID, target reps, locale/voice settings. No raw debug/landmark/confidence. No frame/video persistence by default.

## R5 — WorkoutDone/WorkoutSummary consolidation

**Q26 must be approved before destructive routing change.** Proposed: `WorkoutSummary` as single canonical screen; migrate/reuse old `WorkoutDone` functionality, leave temporary compatibility wrapper only as required; one persisted completion path, one analytics event family and one navigation destination. If owner has not decided, provide exact migration plan and **STOP**.

## R6 — Rest Timer wiring

`Complete Set → Persist Set → Rest Timer → Ready/Skip/+Time → Next Set`.

Single authoritative clock; no duplicate timers; correct lifecycle/app-pause restore, settings-driven sound/haptics, Skip/+30 seconds/Pause/Resume and unit/widget/integration tests. Existing saved sets must never disappear when timer is interrupted.

## R7 — Real Progress charts

- **Strength:** Selected exercise/period, data-backed line chart for a valid metric (best weight or **estimated 1RM only if formula approved**) and insufficient-data state.
- **Volume:** Weekly bar chart; calculate using actual workout-domain formula, never fabricate values.
- **Consistency:** Weekly/monthly workout frequency with timezone-safe calendar/bar dates.
- **Muscle load:** Anatomical map **only with trustworthy muscle mapping**; otherwise ranked group bars, explicitly labeled training distribution **not medical assessment**.

All charts: loading/empty/error/offline, period selection, accessibility summaries, large text and screenshot review.

## R8 — Contextual AI Coach

Reuse existing AI Coach service/UI/cache — no second chat backend. Entry from Scan, Equipment, Exercise, Recovery and Workout Summary. Pass **structured minimal context**, including source screen, exercise/equipment, actual workout state, privacy-limited history/recovery and locale, not a long unstructured string. No invented sensor/body/medical facts.

## R9 — Theme, platform, accessibility, offline, E2E

**Light theme:** Derive semantic palette from approved tokens if Figma lacks full coverage; not simple color inversion. Check Home, Scanner, Exercise, Workout Player, Progress, dialogs; require screenshot approval before broad rollout; preserve dark theme.

**Platforms:** Safe areas/system bars, Android predictive back, iOS swipe-back where applicable, keyboard insets, camera lifecycle/permissions, native pickers, no clipped content.

**Accessibility:** Approximately **48 logical px** controls where applicable, Semantics labels/order, color-independent states, 1.0/1.3/1.6/2.0 text scales, reduced motion, accessible chart/camera/timer controls.

**Offline:** Home cached/limited, Scanner local fallback, Workout Player/set logging, Rest Timer, cached/empty Progress, retry/sync states.

**E2E path:** `Onboarding → Home → Scan → Result → Equipment → Exercise Page → Workout Player → Complete Set → Rest Timer → Next Set → Technique Coach → Workout Summary → Progress → Progress Photos`.

No dead routes, dead CTAs or enum states without reachable navigation.

# Provisional Planning Decisions — NOT FINAL

- Flutter/Riverpod/go_router remain locked.
- Figma Make code never pasted into production.
- Reuse audited existing ML pipeline.
- Technique Coach shows reliability labels, not raw model confidence.
- Store only summary metadata for Form Check; not camera frames/video unless separate policy approved.
- Voice language follows app/system locale, using existing on-device TTS **only if verified**.
- Progress Photos private by default; warn on mismatched angles.
- Lack of a complete light-theme prototype need not halt earlier dark-theme gates.
- WorkoutSummary consolidation requires a confirmed Q26 owner decision before mutation.

These defaults are for planning/non-destructive scope, need owners and review deadlines, and are not new operator approvals.

# Required Test Matrix — Original v1.6 Remaining Scope

**Unit:** Derived calculations/aggregations; chart series; timer lifecycle; route/context; exercise history; AI context; pure theme mappings; offline/sync transitions.

**Widget:** Home calendar/milestones/recovery scroll; scanner saved/unknown/offline; Exercise Page normal/no-history/media-error/restricted; Technique Coach entry unsupported/available; timer controls; canonical Summary; chart states; AI context CTA; dark/light, large text and Semantics.

**Integration:** Scan→Equipment→Exercise; Exercise→Workout and Technique Coach; set→timer→next set; completed workout→one Summary→Progress; offline logging then sync; restart restoration; **real camera/ML smoke on authorized hardware**.

**Visual:** Representative emulator/device screenshot for key screens; Figma comparison, documented deviations, Android/iOS sizes, RU/EN, dark/light, large text.

# Required Execution Order and First Response

1. **R0 only:** Read-only audit, written report, STOP.
2. After explicit audit GO: semantic theme token gate when needed.
3. R1 Home.
4. R2 Scanner/Equipment.
5. R3 Exercise Page.
6. R4 Technique Coach entries.
7. R5 Summary consolidation **only after Q26**.
8. R6 Rest Timer.
9. R7 Progress charts.
10. R8 AI Coach contexts.
11. R9 theme/platform/accessibility/offline/E2E.
12. Final regression and handoff.

**Never combine everything into one giant commit.** Each implementation gate needs scoped diff review, targeted tests, broader regression, `flutter analyze`, emulator/device screenshots, state/evidence docs, one **local** commit, STOP, and **separate push-GO**. This is the v1.6 historical engineering contract.

The development agent's **first response** to this handoff must contain:

1. Git baseline.
2. Whether the exact Figma Make URL is accessible.
3. Which screens/states/transitions are actually visible.
4. Real repository feature inventory.
5. Screen-to-code mapping.
6. Figma-vs-code gap classifications.
7. Unresolved decisions/blockers.
8. File-and-test-specific gate plan.
9. Risks.
10. Explicit `STOP — no files modified`.

**Do not edit code, commit or push before separate owner GO.**

---

## Translation scope / independent review limits

This English version reproduces the full original **35 numbered implementation sections**, original appendix/update structures, v1.6 R0–R9 remaining scope and negative gates as a detailed source-structured companion; it is **not claimed as a certified line-by-line linguistic copy** or revalidated modern development plan.

The original Russian/English mixed-language source is retained unchanged. No real-user health data or photo was read; no Flutter code, Figma frames, mobile camera, ML, backend, billing, test suite, local Git worktree, owner permission or release gate was changed through this documentation PR.

**Status: English explanatory development contract prepared for independent review; no implementation or authorization implied.**
