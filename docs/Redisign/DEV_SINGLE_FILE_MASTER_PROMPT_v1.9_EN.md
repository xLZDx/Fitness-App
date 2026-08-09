# FITNESS APP — SINGLE-FILE DEVELOPMENT MASTER PROMPT v1.9 (ENGLISH)

You are a Senior Flutter Engineer, Mobile UI Architect, Product Engineer, and implementation specialist for complex fitness and health applications.

Your task is to implement the approved Figma redesign and perform a safe, staged refactor of the existing Fitness App.

Repository:
https://github.com/xLZDx/Fitness-App

Figma Make — the primary UX, visual, and interaction reference:
https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples?t=PknUCnJWYLxe5itJ-1

Approved handoff version:
v1.9

Important: the link points to a Figma Make functional prototype. Use it to understand screens, visual hierarchy, copy, states, transitions, and interaction behaviour. Do not port generated web or React code from Figma Make into the application. The production implementation must remain in the existing Flutter/Dart repository.

---

## PRIMARY SOURCES AND PRECEDENCE

Use the following precedence order:

1. The current repository and its tests are the source of truth for real capabilities, data, lifecycle, persistence, security, and backend contracts.
2. The Figma Make link above is the source of truth for the approved UX, visual language, and interaction intent.
3. Existing Flutter themes and components are the implementation source of truth for semantic tokens until the token mapping is complete.
4. This prompt is the source of truth for scope, gates, invariants, and execution discipline.

When sources conflict:

- do not copy impossible or fake behaviour from the prototype;
- do not remove a working capability merely because it is absent from Figma Make;
- do not add fake data, fake AI, fake sensor results, or fake analytics;
- document the conflict in the Gate 0 report;
- propose a safe resolution;
- STOP and wait for operator GO if the conflict affects schema, privacy, billing, the ML pipeline, or user data.

### Figma Make access

At the beginning of Gate 0, verify whether the exact Figma Make link opens and what is accessible:

- preview;
- screens;
- interactions;
- prompt and conversation history, if permissions allow it;
- generated project files, if permissions allow it.

If Figma Make is unavailable:

- do not claim that the design was reviewed;
- list every unavailable artifact;
- continue the repository audit;
- use attached screenshots or exports if available;
- STOP before visual implementation when the required reference is missing.

If Figma Make is accessible, treat its generated code only as a behavioural reference. Do not port React, CSS, HTML, browser routing, browser storage, or web-specific state management into Flutter.

This is an existing working project. Do not create a new Flutter project, migrate it to FlutterFlow, or rewrite the architecture from scratch.

Work only against the current repository state after fetch/pull and verification of branch and HEAD. Older documents and previous reports may be historical. Current code, tests, and active state/gate documents take precedence.

---

## 1. GOAL

Transform the application from a conventional tile-based interface into a modern, goal-driven, context-aware product while preserving existing business logic, data, recognition pipelines, workout lifecycle, and privacy guarantees.

Primary product flow:

Onboarding
→ Body Metrics
→ Plan Preview
→ Home
→ Scan
→ Equipment
→ Exercise
→ Workout Player
→ Rest Timer
→ Form Check
→ Workout Summary
→ Progress
→ Progress Photo Comparison

Figma Make is the source of truth for UI and UX intent.
The repository is the source of truth for business logic and real capabilities.

When they conflict, stop and report. Do not invent behaviour.

---

## 2. STACK THAT MUST BE PRESERVED

Preserve:

- Flutter / Dart;
- Riverpod;
- go_router;
- feature-first architecture;
- Firebase Auth;
- Firestore;
- Firebase Functions;
- existing camera and ML services;
- existing catalogue loaders;
- workout services;
- localisation;
- test architecture.

Forbidden without a separate architecture-GO:

- Bloc, GetX, MobX, or another parallel state-management system;
- a new router;
- a second parallel state source of truth;
- a new backend schema;
- a new recognition pipeline;
- migration to FlutterFlow;
- a full rewrite of any feature.

---

## 3. GATE 0 — MANDATORY READ-ONLY AUDIT

Do not modify files before completing this gate.

### Git baseline

Verify and report:

- current branch;
- HEAD SHA;
- upstream;
- git status;
- unpushed commits;
- untracked files;
- concurrent or unrelated changes.

### Documents

Read:

- `CLAUDE.md` and all applicable repository instructions;
- `core/TECHSTACK.md`;
- `core/CODEMAP.md`;
- active state and gate documents;
- changelog;
- current theme documentation;
- current routing documentation.

### Code inventory

Locate and map:

- theme and tokens;
- navigation shell;
- onboarding and authentication;
- profile models;
- body metrics logic;
- Home;
- Scanner;
- Equipment;
- Exercise;
- Workout Player;
- Rest Timer;
- Form Check / Technique Coach;
- Progress;
- Progress Photos or related media features;
- Programs;
- AI Coach;
- Subscription;
- Health Connect / HealthKit abstraction;
- storage, sharing, and permissions;
- tests.

### Required audit output

Create a mapping:

Figma screen
→ existing route
→ existing widget/page
→ providers/services
→ existing models
→ missing capabilities
→ risks
→ tests
→ assigned implementation gate

List separately:

- hardcoded colours;
- hardcoded strings;
- duplicate cards;
- oversized widgets;
- business logic inside UI code;
- expensive rebuilds;
- lifecycle risks;
- missing states;
- schema conflicts;
- privacy conflicts.

After Gate 0, provide the implementation plan and STOP with no modifications.

---

## 4. ARCHITECTURE RULES

1. UI must not contain business logic.
2. Do not duplicate a source of truth.
3. Providers and services keep their current responsibilities unless a proven issue requires change.
4. Do not create repositories only for presentation convenience.
5. Change models only when necessity is demonstrated.
6. Backend schema changes require a separate GO.
7. Do not change the recognition pipeline in a UI gate.
8. Do not change workout calculations without a separate scope.
9. Do not change injury filtering in a visual gate.
10. Do not invent subscription products or limits.
11. Production code must not contain fake data.
12. All user-facing strings must use localisation.
13. Internal exceptions must never be shown to users.
14. Do not touch unrelated files.
15. Never expand scope silently.

---

## 5. DESIGN SYSTEM REFACTOR

Refactor in this order:

1. semantic tokens;
2. reusable components;
3. feature screens.

Adapt to the existing repository structure. A possible target structure is:

```text
lib/core/theme/
  app_theme.dart
  app_palette.dart
  app_semantic_colors.dart
  app_typography.dart
  app_spacing.dart
  app_radius.dart
  app_elevation.dart
  app_motion.dart
  app_component_sizes.dart
  app_breakpoints.dart
```

Semantic colour tokens should include or map to:

- `backgroundPrimary`;
- `backgroundSecondary`;
- `surfacePrimary`;
- `surfaceElevated`;
- `surfaceInteractive`;
- `textPrimary`;
- `textSecondary`;
- `textDisabled`;
- `accentPrimary`;
- `accentSecondary`;
- `success`;
- `warning`;
- `danger`;
- `outline`;
- `cameraOverlay`;
- `poseCorrect`;
- `poseWarning`;
- `poseError`.

Do not spread the following through feature widgets:

- random `Color` literals;
- arbitrary `EdgeInsets`;
- local one-off `TextStyle` values;
- hardcoded radii.

Light and dark modes must be separate semantic configurations rather than mechanical colour inversion.

---

## 6. COMPONENT LIBRARY

Minimum reusable component set:

- `AppPrimaryButton`;
- `AppSecondaryButton`;
- `AppTertiaryButton`;
- `AppIconButton`;
- `AppTopBar`;
- `AppNavigationBar`;
- `AppChoiceCard`;
- `AppMultiSelectCard`;
- `AppChip`;
- `MuscleChip`;
- `EquipmentChip`;
- `RecommendationHero`;
- `GoalProgressCard`;
- `RecoveryStatus`;
- `WorkoutCard`;
- `ProgramCard`;
- `ExerciseMediaCard`;
- `EquipmentMediaCard`;
- `AIInsightCard`;
- `BodyMetricPicker`;
- `SetLogger`;
- `WeightInput`;
- `RepsInput`;
- `RestTimerCard`;
- `CameraTargetOverlay`;
- `RecognitionResultSheet`;
- `ConfidenceIndicator`;
- `EmptyState`;
- `ErrorState`;
- `OfflineState`;
- `PermissionState`;
- `LoadingSkeleton`;
- `WorkoutBottomControls`;
- `FormCheckCue`;
- `WorkoutSummaryMetric`;
- `ProgressPhotoCard`;
- `ProgressPhotoTimelineItem`;
- `ProgressPhotoCompareView`.

Do not create a giant `AppCard` with dozens of optional arguments.

Presentational components must not directly depend on feature providers.

---

## 7. LOCALISATION AND UNITS

All new user-facing text must go through the existing localisation pipeline.

Verify:

- Russian and English;
- plural rules;
- kg/lb;
- cm/ft;
- date and time formatting;
- long Russian strings;
- accessibility labels;
- permission explanations;
- error messages.

Do not allow hardcoded English to appear in the Russian UI.

Unit conversion must preserve precision and must not accumulate drift. Determine canonical storage units from the current model. If the model does not define them, propose a decision and STOP before implementation.

---

## 8. ONBOARDING REFACTOR

Target flow:

1. Value proposition.
2. Goal.
3. Experience.
4. Training location.
5. Available equipment.
6. Schedule.
7. Limitations.
8. Target areas.
9. Main obstacle.
10. Birth year.
11. Height.
12. Current weight.
13. Target weight.
14. Health Connect.
15. Generating.
16. Plan Preview.
17. Account.
18. Contextual notification permission.

Requirements:

- one primary question per screen;
- progress indicator;
- back navigation;
- resumable draft;
- only optional steps may be skipped;
- preview before account or paywall;
- no fake progress;
- no fake goal forecast;
- no notification permission before contextual explanation.

Use existing profile and onboarding models. If required fields are absent, provide a minimal schema proposal and STOP until GO.

Plan Preview must use the real generator or approved fallback, not a production fake fixture.

---

## 9. BODY METRICS

### 9.1 BodyMetricPicker

Required variants:

- birth year;
- height;
- current weight;
- target weight.

Required capabilities:

- wheel or ruler interaction;
- direct input;
- haptic ticks;
- minus and plus accessibility controls;
- kg/lb;
- cm/ft;
- light and dark modes;
- large text;
- state restoration and onboarding resume.

### 9.2 Pure calculator

Derived values must not be stored in Firestore.

Use these formulas:

```text
bmi = currentWeightKg / (heightMeters * heightMeters)

adultReferenceMinKg =
18.5 * heightMeters * heightMeters

adultReferenceMaxKg =
24.9 * heightMeters * heightMeters

targetDeltaKg =
targetWeightKg - currentWeightKg

targetDeltaPercent =
targetDeltaKg / currentWeightKg * 100

aboveRangePercent =
(currentWeightKg - adultReferenceMaxKg)
    / adultReferenceMaxKg
    * 100

belowRangePercent =
(adultReferenceMinKg - currentWeightKg)
    / adultReferenceMinKg
    * 100
```

Every percentage must document its denominator.

Adult classification may only be shown for users aged 20 or older. Do not show adult BMI classification to younger users.

### 9.3 Feedback states

Support:

- inside reference range;
- below reference range;
- above reference range;
- missing height;
- missing age;
- under 20;
- muscular-body limitation note;
- target outside reference range;
- no target set.

Use neutral language. Do not diagnose, shame, or command the user to lose or gain weight.

---

## 10. HEALTH CONNECT / HEALTH DATA

Request permission only after an explicit user action.

Preserve current integrations and contracts. Do not promise recovery capabilities that do not exist.

Handle:

- unsupported device;
- denied permission;
- permanently denied permission;
- partial permission;
- disconnected integration;
- stale data;
- reconnect.

Do not create a dead iOS “coming soon” action without explicit Product GO.

---

## 11. NAVIGATION

Primary tabs:

- Home;
- Scan;
- Workouts;
- Progress;
- Profile.

Preserve existing deep links and route names wherever practical.

Required behaviour:

- Android back;
- Android predictive back;
- iOS swipe-back where appropriate;
- state restoration;
- tab-state preservation;
- scroll-state preservation;
- safe areas;
- edge-to-edge layout;
- keyboard insets.

---

## 12. HOME REFACTOR

Content priority:

1. Greeting.
2. Program progress.
3. Today hero.
4. Start or Continue action.
5. Quick Scan.
6. Recovery.
7. Weekly progress.
8. Latest achievement.
9. Conditional progress-photo card.

Every data block must have:

- loading;
- data;
- empty;
- error;
- offline or stale state where applicable.

Do not watch all providers unnecessarily. Do not rebuild the entire Home page every second.

The progress-photo card may appear only when at least two compatible photos exist.

The Home page must also include or complete:

- weekly calendar;
- milestones block;
- horizontal recovery scroll;
- a visible affordance that the recovery list is horizontally scrollable;
- correct safe-area behaviour;
- responsive card widths.

Priority must remain:

1. Today Workout;
2. Scan;
3. weekly progress and recovery;
4. milestones and secondary content.

---

## 13. SCANNER REFACTOR

Do not change the recognition service in a UI gate.

Preserve:

- cloud recognition;
- timeout handling;
- local fallback;
- alias resolution;
- unknown-equipment handling;
- recognition history;
- saved machines / My Machines if already present.

Required UI states:

- permission explanation;
- ready;
- analysing;
- success;
- alternatives;
- unknown;
- timeout;
- offline or on-device fallback;
- low confidence;
- actionable error;
- retry;
- network failure.

There must be no infinite spinner and no fake confidence value.

Do not convert an unknown machine into the nearest incorrect catalogue result.

Preserve the existing frame-processing privacy policy.

Provide a manual search fallback only if approved and supported by real catalogue data.

---

## 14. EQUIPMENT PAGE

Use the existing equipment hero provider or its current equivalent.

The hero should use a poster from a linked licensed exercise. Do not reintroduce generic stock photography.

Structure:

- hero media;
- name and category;
- purpose;
- muscles;
- suitability;
- safety;
- featured exercise;
- compatible exercises;
- AI Coach entry;
- add to workout.

Use lazy media loading, stable keys, and thumbnails before full media.

Do not change equipment-linking logic in a UI gate.

---

## 15. DEDICATED EXERCISE PAGE

The Exercise Page is a required dedicated screen. It must not be reduced to Equipment or Workout Player content.

If no dedicated route exists, add one using a stable exercise ID.

Use real catalogue, media, history, and restriction data.

Required content:

- licensed anatomical animation or poster fallback;
- exercise name;
- equipment;
- level;
- primary muscles;
- secondary muscles;
- suitability or personalisation explanation;
- short technique steps;
- expandable full instructions;
- common mistakes;
- restrictions and contraindications only when real data exists;
- personal history;
- last performance;
- personal record only when calculated honestly;
- Start Exercise;
- Add to Workout;
- Technique Coach;
- AI Coach.

Required states:

- loading;
- loaded;
- media unavailable;
- no history;
- unsupported or restricted;
- long Russian and English content;
- large text;
- offline where possible.

Media lifecycle:

- show poster first;
- play video only after interaction;
- pause on app background;
- dispose controllers;
- prevent audio leaks;
- restore orientation.

Do not copy workout logging business state into the Exercise Page. Pass context to Workout Player instead.

---

## 16. WORKOUT PLAYER AND SET LOGGER

Display real data:

- current exercise;
- current set;
- total sets;
- weight;
- repetitions;
- previous result;
- active timer;
- rest status;
- workout duration.

After a set is completed:

1. Persist through the existing authoritative source.
2. Show confirmation.
3. Allow undo.
4. Start Rest Timer when appropriate.
5. Advance according to existing workout rules.

Do not create presentation state that diverges from persisted state.

Isolate timer updates so they do not rebuild the entire screen.

Guard workout completion and destructive finish actions.

---

## 17. REST TIMER

Required capabilities:

- remaining time;
- next target;
- Skip;
- add 30 seconds;
- pause and resume;
- completion haptic and/or notification according to settings;
- background lifecycle;
- foreground restoration;
- exactly one authoritative timer state.

Required flow:

Complete Set
→ Persist Set
→ Rest Timer
→ Ready / Skip / Add Time
→ Next Set

Required tests:

- starts exactly once;
- no duplicate clocks;
- add time;
- skip;
- pause and resume;
- background and foreground;
- completion;
- persisted set is never lost because of timer behaviour.

---

## 18. TECHNIQUE COACH / LIVE FORM CHECK

This is a technical subsystem, not merely a camera widget.

Do not rewrite detectors or classifiers in a visual gate. Do not change the ML pipeline without separate GO.

### 18.1 Mandatory read-only Form Check audit

Before modifying it, identify and document:

- supported exercises;
- supported camera angle for each exercise;
- actual pose detector and runtime;
- landmark coordinate space;
- mandatory landmarks for every rule or classifier;
- body-in-frame and visibility logic;
- low-light detection;
- blur or stability detection;
- angle validation;
- repetition counter state machine;
- top and bottom thresholds;
- hysteresis and debounce;
- cue gating and cooldown;
- TTS implementation;
- camera lifecycle;
- frame sampling rate;
- current privacy behaviour;
- whether frames or video are stored;
- debug overlays or developer strings currently visible in production UI.

Explicitly document any user-visible string similar to `pose[pixels]...`. It is debug output and must be removed from production presentation. It may remain only behind an explicit debug flag in non-release builds.

After the audit, document this contract:

Camera Frame
→ Pose Detector
→ Frame Quality Gate
→ Required-Joint Visibility Gate
→ Angle Gate
→ Exercise Classifier / Rule Engine
→ Rep Counter
→ Cue Gate
→ UI State
→ TTS

Do not merge these layers into one giant widget.

### 18.2 Architecture boundaries

Prefer to preserve or introduce clear independent contracts such as:

- `PoseFrameResult`;
- `FrameQualityResult`;
- `VisibilityGateResult`;
- `AngleGateResult`;
- `MovementPhase`;
- `RepEvent`;
- `TechniqueCue`;
- `TechniqueCoachState`.

Adapt names to the existing codebase. Do not create parallel models when equivalents already exist.

The UI must not calculate joint angles or decide whether a repetition counts. It only renders domain/application state.

### 18.3 Entry points and session context

Form Check must start only with known context:

- `exerciseId`;
- exercise name;
- required or supported angle;
- active workout or session ID when started from Workout Player;
- expected camera orientation;
- supported classifier or rule set;
- target repetitions when applicable;
- language and voice preference.

Required entry points:

1. Exercise Page.
2. Workout Player.
3. Optional pre-set setup.

For unsupported exercises, show an honest unsupported state. Do not run a generic classifier.

### 18.4 Pre-check screen

Show real information:

- exercise title;
- required angle;
- camera placement;
- body visibility requirements;
- privacy copy consistent with the real implementation;
- CTA to start the camera.

Do not claim on-device processing unless the audit confirms it.

### 18.5 Camera presentation

Production screen must include:

- top bar with back, title, flash, sound, and help;
- camera as the dominant content;
- silhouette or angle guide;
- landmark or skeleton overlay;
- body-segment states;
- quality banner;
- repetition counter;
- movement phase;
- one live cue;
- pause and finish.

Never show users:

- raw landmark arrays;
- `pose[pixels]` coordinates;
- raw model-confidence dumps;
- internal rule IDs;
- stack traces;
- classifier names;
- developer logs.

Debug overlay is permitted only behind an explicit debug flag and only in non-release builds.

Add a test that release and production presentation contain no debug copy.

### 18.6 Frame quality gates

Before counting repetitions, apply the gates supported by the audited architecture:

- camera initialised;
- minimum light or brightness;
- blur or stability;
- exactly one person when detector support exists;
- acceptable body scale or distance;
- required joints visible;
- full body or required body region in frame;
- required camera angle;
- pose confidence threshold;
- calibration complete.

Every gate result should expose:

- machine-readable reason;
- localised user message;
- severity;
- recoverable flag.

Until all required gates pass:

- freeze the rep counter;
- emit no rep event;
- show no score;
- show no positive or negative form verdict;
- produce no misleading success TTS.

### 18.7 Rep counter invariants

The counter must:

- run only after ready/calibrated state;
- use the existing movement state machine;
- use hysteresis and debounce;
- never count one movement cycle twice;
- never convert a partial repetition into a complete repetition after pose loss;
- never count during low quality or wrong angle;
- recover safely after short landmark loss;
- distinguish detected repetitions from evaluated repetitions;
- have deterministic tests using landmark or angle sequences.

If the current implementation starts counting from a specific top or bottom phase, explain this in plain user language without exposing internal thresholds.

### 18.8 Live cue gate

At most one primary cue may be active at a time.

Requirements:

- priority ordering;
- cooldown;
- duplicate suppression;
- no overlapping TTS;
- visible and spoken cues use the same localisation key;
- visibility loss takes priority over technique correction;
- do not repeat the same error every frame;
- clear a cue when corrected or after timeout;
- cue history must not grow without bounds.

### 18.9 Pose loss or quality degradation during a set

When pose tracking or a mandatory gate is lost:

- enter paused or cannot-evaluate state;
- freeze the rep counter;
- do not count the incomplete repetition;
- stop technique scoring;
- show an actionable localised message;
- resume safely after recovery and recalibration when required.

Do not reset all completed work without a valid reason.

### 18.10 Overlay rendering

The skeleton overlay must use the same coordinate system as the camera preview and correctly account for:

- crop and fit mode;
- rotation;
- front-camera mirroring;
- device orientation;
- preview aspect ratio;
- letterboxing;
- viewport resize.

Add golden, widget, or deterministic transform tests so landmarks do not drift away from the body at different aspect ratios.

Segment states:

- neutral;
- correct;
- warning;
- error;
- unavailable.

Do not rely on colour alone. Pair colour with icon and/or text semantics.

### 18.11 TTS and audio

- sound toggle must not disable visual cues;
- no overlapping utterances;
- lifecycle pause must stop or safely resume speech;
- text and TTS use the same localisation source;
- rate-limit speech;
- TTS errors must not block visual coaching;
- Bluetooth or audio interruptions must not corrupt session state.

### 18.12 Privacy and recording

Preserve the current privacy architecture.

If processing is on-device and frames are not transmitted, confirm it through code and network audit before displaying that promise.

Default rules:

- do not save raw frames;
- do not record video;
- do not attach camera images to analytics or crash reports;
- do not log landmark payloads with user identifiers;
- do not build replay UI without a separate recording feature and explicit opt-in.

### 18.13 Lifecycle and performance

Verify:

- permission flow;
- camera initialisation failure;
- app background and foreground;
- route pop;
- controller disposal;
- orientation changes;
- front and back camera switching;
- screen wake-lock policy;
- thermal warnings;
- frame backpressure;
- detector concurrency;
- no queue growth;
- UI isolate responsiveness;
- no full-page rebuild per frame;
- isolated overlay repaint;
- target FPS on a supported mid-range Android device.

If processing cannot keep up, drop stale frames instead of building a queue.

### 18.14 Technique Coach summary

Use only real session events:

- detected repetitions;
- evaluated repetitions;
- unevaluated repetitions;
- top one or two positive observations;
- top one or two corrective priorities;
- insufficient-data state;
- return to workout;
- retry set.

Do not show an aggregate score when there are too few evaluated repetitions.

Do not promise video replay when recording does not exist.

### 18.15 Required Technique Coach UI states

Implement:

- unsupported exercise;
- angle selection;
- permission explanation;
- denied and permanently denied;
- camera unavailable;
- initialisation;
- low light;
- blur;
- too close or too far;
- partial body;
- missing joints;
- wrong angle;
- multiple people;
- calibration;
- ready;
- countdown;
- active;
- cue warning or error;
- pose lost;
- paused;
- cannot evaluate repetition;
- detector error;
- thermal or performance warning;
- completed;
- insufficient-data summary.

### 18.16 Technique Coach tests

Unit and domain tests:

- every quality gate;
- gate precedence;
- angle validation;
- visibility thresholds;
- rep state machine;
- hysteresis and debounce;
- no double count;
- no count while invalid;
- partial repetition on pose loss;
- recovery after pose restoration;
- cue priority, cooldown, and deduplication;
- detected versus evaluated counts;
- insufficient-data summary.

Widget and golden tests:

- every camera state using a fake camera surface;
- overlay alignment;
- rep counter;
- live cue;
- low-light banner;
- wrong-angle banner;
- pose-lost state;
- sound toggle;
- large text;
- Russian and English;
- high contrast;
- no debug text in production UI.

Integration and device tests:

- permission lifecycle;
- camera start and stop;
- background and foreground;
- session resume;
- orientation;
- front-camera mirroring;
- TTS interruption;
- sustained processing soak;
- memory and controller leaks;
- thermal degradation behaviour.

Critical invariant:

Do not show a score and do not count a repetition when required visibility, quality, or angle gates have not passed.

---

## 19. WORKOUT SUMMARY

Use real data only:

- duration;
- sets;
- volume;
- personal record;
- difficulty;
- form feedback;
- recovery;
- next workout.

Do not add fake achievements.

A progress-photo milestone prompt may appear only when a real milestone condition is met, not after every workout.

The application must have one canonical workout-completion destination. See the consolidation policy below.

---

## 20. PROGRESS

Sections:

- consistency;
- workout count;
- volume;
- key exercise progress;
- goal progress;
- muscle load;
- recovery;
- measurements;
- progress photos;
- achievements.

Do not show fabricated percentages. Recovery labels must be honest.

Charts must have:

- accessible labels;
- correct axes and date ranges;
- no misleading smoothing;
- empty and insufficient-data states;
- efficient repainting.

Replace placeholder charts with real data-backed visualisations:

### Strength progression

- selected exercise;
- period selector;
- line chart using an honest metric, such as best weight or estimated 1RM only when the formula is already approved;
- insufficient-data state.

### Volume

- weekly bars;
- volume formula must match the workout domain;
- no fabricated values.

### Consistency

- weekly or monthly workout frequency;
- calendar or bar view based on the closest approved pattern;
- timezone-safe dates.

### Muscle load

- use an anatomical map only when muscle mapping is reliable;
- otherwise use ranked bars by aggregated muscle group;
- label it as training distribution, not a medical assessment.

Every chart requires loading, empty, error, offline/stale, period selection, accessibility summary, large-text support, and screenshot review.

---

## 21. PROGRESS PHOTOS

This is a dedicated feature inside Progress.

### 21.1 Gate P0 audit

Before implementation, verify:

- camera and photo picker;
- local storage;
- cloud storage;
- Firestore metadata;
- encryption and access rules;
- account deletion;
- data export;
- notifications;
- EXIF handling;
- existing privacy promises.

Storage policy requires an explicit decision:

A. Local only.
B. Local first with optional backup.
C. Cloud synchronised.

Do not choose silently.

### 21.2 Model

Minimum fields:

- `id`;
- `userId`;
- `capturedAt`;
- `angle`;
- `localPath`;
- optional `remotePath`;
- optional `thumbnailPath`;
- optional `weightKg`;
- optional `note`;
- optional `milestoneTag`;
- `createdAt`;
- `updatedAt`;
- `syncState`.

Angles:

- front;
- side left and side right, or one canonical side according to the approved model;
- back;
- custom/free.

Do not store body score, estimated body-fat percentage, beauty score, or medical conclusions.

### 21.3 Privacy invariants

- private by default;
- no public URLs;
- no AI analysis without explicit opt-in and approved scope;
- no photo attachment to analytics;
- deletion removes metadata and bytes;
- account deletion handles all progress photos;
- export strips location EXIF;
- no sensitive paths or tokens in logs;
- sync failure never deletes the local original.

### 21.4 Capture

Implement:

- angle selection;
- silhouette guide;
- camera;
- timer;
- flash;
- switch camera;
- preview;
- retake and save;
- orientation normalisation;
- metadata.

Do not persist the photo before explicit confirmation.

### 21.5 Timeline

Include:

- thumbnails;
- date;
- angle;
- optional weight;
- note or milestone;
- filters;
- multi-select;
- edit;
- delete;
- compare.

Do not decode full originals in the scrolling list.

### 21.6 Comparison

Modes:

- side by side;
- overlay slider.

Controls:

- swap;
- hide or show weight;
- hide or show date;
- fit and fill;
- select another image;
- manual scale;
- x offset;
- y offset;
- small rotation;
- reset.

Original files must remain immutable.

No body morphing.

Auto-alignment is a separate optional gate only after on-device feasibility and privacy are confirmed.

### 21.7 Export

- preview is mandatory;
- hide or show weight and date;
- optional face blur;
- optional watermark;
- save or share;
- strip EXIF;
- no automatic posting.

### 21.8 Home integration

Show the Home card only when at least two compatible photos exist.

Do not show an empty progress-photo card on Home.

Do not place it above Today Workout or Scan.

### 21.9 Reminder

Offer a contextual reminder for 2, 4, or 8 weeks, or no reminder.

Request notification permission only after user agreement.

---

## 22. WORKOUT LIBRARY AND PROGRAMS

Search, filter, and sort by:

- goal;
- experience level;
- training location;
- equipment;
- duration;
- muscles;
- limitations.

Do not show a compatibility percentage unless a real, documented scoring algorithm exists.

Use honest descriptive labels instead.

Preserve real programme and workout data sources. Do not convert catalogue filters into hardcoded demo lists.

---

## 23. AI COACH

Preserve the existing AI service, cache, safety boundaries, and backend contract.

Required contextual entry points:

- Scan Result;
- Equipment;
- Exercise Page;
- Workout Player where already approved;
- Workout Summary;
- Recovery;
- Plan.

Do not create a second chat backend or a parallel AI service.

Pass structured context rather than only a long free-form string:

- source screen;
- equipment or exercise ID;
- active workout state;
- relevant history;
- relevant recovery data subject to privacy constraints;
- locale;
- supported capability flags.

Required states:

- loading;
- cached;
- timeout;
- retry;
- offline fallback;
- safety disclaimer;
- unavailable capability.

Do not send unnecessary personal data.

Do not change the server prompt, model contract, or data-retention behaviour without separate scope and GO.

AI Coach must not invent unavailable sensor data, medical analysis, body-analysis data, or recovery measurements.

---

## 24. PROFILE, SETTINGS, AND SUBSCRIPTION

Profile and Settings should expose real capabilities only:

- personal data;
- goals;
- units;
- Health Connect or platform health integration;
- notifications;
- privacy;
- progress-photo storage or sync settings only after storage policy is approved;
- subscription;
- help;
- account deletion and data export where required by existing policy.

Do not change billing logic in a presentation gate.

Build the UI only from real store products and real effective-tier logic.

Test:

- loading products;
- no products;
- pending purchase;
- success;
- failure;
- cancellation;
- restore purchases;
- already subscribed;
- offline.

Do not invent plan limits, free-tier quotas, prices, or billing periods.

---

## 25. ACCESSIBILITY

Accessibility is mandatory and must be integrated into real screens, not left only in isolated component examples.

Required:

- Flutter `Semantics`;
- logical screen-reader order;
- touch targets of approximately 44–48 logical pixels or larger;
- Dynamic Type and text scaling;
- text scale validation at 1.0, 1.3, 1.6, and 2.0;
- sufficient contrast;
- no colour-only status communication;
- reduced-motion behaviour;
- accessible chart summaries;
- alternatives to drag-only controls;
- long Russian strings;
- safe areas;
- meaningful labels for camera controls, timers, and progress-photo comparison.

Do not use fixed-height cards that clip dynamic text.

---

## 26. RESPONSIVE AND PLATFORM BEHAVIOUR

Validate:

- small Android phones;
- common Android phones;
- large Android phones;
- iPhone safe areas;
- notches and Dynamic Island areas;
- landscape workout use;
- tablets without breakage;
- keyboard insets;
- display cut-outs;
- gesture navigation.

Do not create separate pixel-perfect copies for every device.

Platform requirements:

- Android predictive back;
- iOS swipe-back where appropriate;
- native permission behaviour;
- camera lifecycle on both platforms;
- platform-appropriate date, time, and picker behaviour where practical;
- system-bar and edge-to-edge correctness;
- no clipped content on representative devices.

---

## 27. PERFORMANCE

Targets and invariants:

- aim for 60 FPS on a supported mid-range Android device;
- no full-page rebuild for timer ticks;
- no expensive `BackdropFilter` over scrolling lists;
- lazy media loading;
- poster before video;
- thumbnails in the progress-photo timeline;
- correct image-cache dimensions;
- no repeated parsing of static data;
- stable keys;
- correct controller disposal;
- no out-of-memory failure during comparison or export;
- no unbounded camera-frame queue;
- no repeated network request caused by rebuilds.

Measure before optimising:

- rebuild counts;
- frame times;
- memory;
- image decoding;
- camera CPU load;
- video lifecycle;
- export memory.

Document intentional performance trade-offs.

---

## 28. ERROR, EMPTY, LOADING, PERMISSION, AND OFFLINE STATES

Every feature must support the applicable states:

- loading;
- empty;
- partial data;
- stale data;
- retryable error;
- terminal error;
- offline;
- permission denied;
- permission permanently denied;
- interrupted session.

No infinite spinners.

Do not expose raw exceptions or backend messages.

Missing Figma frames for ordinary error and offline states do not automatically block development. Derive them from the approved design system, but document the derivation and include screenshots for review.

---

## 29. TESTING STRATEGY

After every implementation gate run the applicable set of:

- unit tests;
- widget tests;
- golden or screenshot tests;
- integration tests;
- existing regression tests;
- `flutter analyze`;
- manual emulator validation;
- dark and light mode;
- Russian and English;
- large text;
- small and large screens.

Critical flows:

- onboarding resume;
- body-metric calculations;
- Plan Preview;
- Home states;
- scan success, alternatives, unknown, timeout, and offline fallback;
- equipment and exercise media lifecycle;
- set logging, undo, and rest;
- interrupted workout;
- Technique Coach setup, quality gates, overlay alignment, repetition counting, cue gating, and visibility invariant;
- Workout Summary;
- Progress;
- progress-photo capture, save, compare, delete, and export;
- subscription.

Do not update goldens automatically without visual-diff review.

---

## 30. SCREENSHOT COMPARISON

For every approved Figma or Figma Make screen:

1. Use a matching viewport.
2. Capture a real emulator or device screenshot.
3. Compare it with the approved reference.
4. Record differences in spacing, typography, colour, alignment, state, and safe areas.
5. Fix proven mismatches.
6. Do not insert fake production data merely to make the screenshot resemble the prototype.
7. Document intentional deviations caused by real platform, data, privacy, or capability constraints.

---

## 31. FULL GATE SEQUENCE

G0 — Read-only audit and Figma-to-code mapping.
G1 — Design tokens.
G2 — Base components and common states.
G3 — Navigation shell.
G4 — Onboarding core.
G5 — Body Metrics and Health Connect presentation.
G6 — Plan Preview and account flow.
G7 — Home.
G8 — Scanner.
G9 — Equipment.
G10 — Exercise Page.
G11 — Workout Player and Set Logger.
G12 — Rest Timer and workout lifecycle.
G13A — Form Check read-only audit and state contracts.
G13B — Technique Coach setup, permissions, and quality-gate presentation.
G13C — Live skeleton overlay, rep counter, movement phase, and cue gating.
G13D — Form Check summary, accessibility, lifecycle, and performance validation.
G14 — Workout Summary.
G15 — Progress and Recovery.
G16 — Progress Photos audit and storage decision.
G17 — Progress Photos capture and timeline.
G18 — Progress Photos comparison, export, and Home integration.
G19 — Programmes and workout library.
G20 — AI Coach integration.
G21 — Profile, Settings, and Subscription presentation.
G22 — Dark and light finalisation.
G23 — Accessibility and responsive audit.
G24 — Performance audit.
G25 — Screenshot regression and final polish.

If scope or risk changes, every gate requires a separate GO after the previous gate report.

The condensed remaining-scope sequence R0–R9 later in this file takes priority for unfinished work already identified after the Figma phase.

---

## 32. GATE REPORT FORMAT

After every gate report:

1. Goal.
2. Files read.
3. Files changed.
4. Behaviour preserved.
5. Behaviour changed.
6. Data or schema impact.
7. Privacy impact.
8. Risks.
9. Tests added.
10. Tests run and exact results.
11. `flutter analyze` result.
12. Screenshot comparison.
13. Remaining issues.
14. Decision IDs consumed.
15. Open decisions.
16. Provisional defaults used.
17. Commit SHA.
18. Push status.

Do not write “everything works” without evidence.

---

## 33. GIT DISCIPLINE

Before every gate verify:

- status;
- branch;
- upstream;
- unpushed commits;
- concurrent changes.

Stage only scoped files.

Do not modify unrelated untracked files.

One gate equals one local commit.

After the commit, STOP.

Push only after a separate explicit `push-GO`.

This rule overrides any older automatic-push instruction.

---

## 34. PROHIBITIONS

Forbidden:

- rewriting the application from scratch;
- replacing Riverpod or go_router without proven necessity and separate GO;
- changing backend, ML, or billing contracts without GO;
- deleting working capabilities merely because they are absent from Figma;
- fake confidence, recovery, body, or health analysis;
- public progress-photo URLs;
- hardcoded English in localised UI;
- random styling values;
- giant widgets;
- heavy scrolling blur;
- silent scope expansion;
- copying generated React/web code into Flutter;
- screenshots used as production UI;
- push without `push-GO`.

---

## 35. DEFINITION OF DONE

The refactor is complete only when:

1. Home is goal-driven.
2. Scanner is a visible product advantage.
3. Onboarding communicates real value before account creation or paywall.
4. BodyMetricPicker and calculations are correct and honest.
5. Workout logging and Rest Timer are reliable.
6. Technique Coach has audited quality gates, aligned overlay, deterministic repetition counting, gated cues, and never evaluates invalid frames.
7. Equipment and Exercise use licensed media and real catalogue data.
8. A dedicated Exercise Page exists and is connected to Workout Player, Technique Coach, and AI Coach.
9. Progress uses real data-backed charts.
10. Progress Photos are private, deletable, comparable, and safely exportable.
11. AI Coach is contextual and reuses the existing service.
12. All relevant loading, empty, error, permission, and offline states exist.
13. Light and dark modes use semantic tokens.
14. Android and iOS safe areas and platform behaviour work.
15. Accessibility passes on real screens.
16. Regression tests are green.
17. There are no new analysis issues.
18. Screenshots match the approved design or document justified deviations.
19. Performance is not worse.
20. Every gate has a scoped local commit.
21. Nothing is pushed without explicit `push-GO`.

Start only with G0 / R0 read-only audit. After the audit, provide a detailed plan and STOP with no modifications.

---

# DECISION GOVERNANCE AND ARCHITECTURE LOCKS

## Decision Register

Maintain a decision register for the 44 identified questions.

For each question store:

- ID;
- gate;
- status;
- owner;
- blocking level;
- context;
- options;
- recommendation;
- final decision;
- rationale;
- dependencies;
- affected files or features;
- required-before gate;
- decision date.

Do not treat a Figma Research or Decision screen as a production requirement. It is an internal design-governance artifact.

## Corrected totals

- Completed-gate debt for D1–D5 and D7: 22.
- D6 blockers and questions: 8.
- Future D8–D9 questions: 14.
- Total: 44.

Do not use the incorrect 26 / 8 / 10 split.

## Architecture locks

### Mobile stack

The stack is already decided:

- Flutter / Dart;
- Riverpod;
- go_router;
- feature-first architecture.

Q39 is closed as `LOCKED: Flutter`.

Forbidden:

- starting a React Native rewrite;
- creating a parallel native application;
- treating React Native as a Form Check implementation option.

### Form Check wording

Q19 must be interpreted as:

`Real on-device ML in the current Flutter stack, or demo/prototype mode?`

Before deciding, audit existing:

- ML Kit, MediaPipe, or another pose detector;
- TFLite capabilities;
- classifiers;
- camera pipeline;
- supported exercise rules.

### Duplicate decisions

Q1 and Q41 represent one Light Theme decision.

Do not implement two independent decisions. Link both to one ADR or Product Decision Record.

### Platform health integration

Do not implement Q4 as a fake iOS “coming soon” card without Product GO.

First determine:

- Android integration scope;
- separate iOS health-integration scope;
- capability visibility by platform;
- no dead CTA.

## Gate-blocking policy

### Hard blockers for D6

- Q19 — ML scope.
- Q20 — supported exercises.
- Q21 — exercise-to-angle matrix.
- Q23 — TTS strategy.
- Q26 — Workout Summary integration route and consolidation.

### Provisional defaults allowed

Only the following documented provisional defaults may be used before final Product decisions:

- Q22: store session-summary metadata only; no frame or video persistence.
- Q24: use app or system locale.
- Q25: use human-readable reliability states; do not show raw confidence percentage.

Every provisional default must:

- be written in the decision register;
- have an owner;
- have an expiry or required review gate;
- not be treated as final.

## No silent choices from open questions

The agent must not silently choose A, B, or C.

If a question is marked Blocker:

- STOP;
- explain the impact;
- provide a recommendation;
- wait for Product or Technical GO.

If a question is future or non-blocking:

- preserve existing behaviour;
- do not expand scope;
- record it as deferred.

## Decision evidence in gate reports

Every gate report must include:

- Decision IDs consumed;
- decisions still open;
- provisional defaults used;
- architecture locks respected;
- new questions discovered.

Assign new IDs to newly discovered questions. Do not overwrite IDs 1–44.

---

# FIGMA MAKE HANDOFF INGESTION PROTOCOL — v1.9

The Figma Make link in this file is the primary currently available design reference.

## Required inputs when available

1. Exact Figma Make link.
2. Published preview link, if available.
3. Approved release version.
4. Figma Design or Dev Mode link, if available.
5. Ready-for-development focus links, if available.
6. Exported Figma variables JSON, if available.
7. Export-ready SVG, PNG, or JPG assets, if available.
8. PNG or PDF reference screens, if available.
9. Screen-to-code mapping, if available.
10. Open Decisions Register.

The absence of a full traditional Dev Mode package does not automatically block the read-only audit. It may block exact visual implementation when essential specifications cannot be confirmed.

## Preferred access path

When Figma Dev Mode, Figma for VS Code, or Figma MCP is available:

- inspect source frames directly;
- use spacing, variables, component variants, and annotations;
- do not copy generated CSS into Flutter;
- explicitly map semantic variables to existing Flutter theme tokens;
- export only genuine assets.

When only Figma Make is available:

- inspect screens, interactions, copy, states, and generated project structure where permissions allow;
- treat generated web code as behavioural evidence only;
- do not port web routing, browser state, CSS, or React components;
- identify which visual dimensions and tokens cannot be confirmed;
- use approved screenshots and the existing Flutter design system;
- request exact missing specifications before implementing an unresolvable visual detail.

## Gate 0 handoff audit document

Create:

`core/plans/FIGMA_MAKE_REFACTOR_AUDIT_<DATE>.md`

The report must contain:

- Figma version and exact URL;
- access result;
- list of visible screens and states;
- list of working prototype transitions;
- available variables and assets;
- missing states;
- conflicts with the repository;
- screen-to-route/provider mapping;
- open blockers;
- recommended gate sequence.

STOP after the audit.

## Asset rules

- SVG for icons and vectors;
- PNG or JPG for raster assets;
- do not use screenshots as production UI;
- do not embed text labels in image assets;
- do not duplicate media already present in the repository;
- verify licences and privacy;
- use stable names;
- optimise assets without visible degradation.

## Token rules

- Figma variables are the design source when available;
- Flutter semantic theme is the code source;
- create an explicit mapping table;
- do not spread raw hex values or spacing values through feature widgets;
- stop and raise a decision when sources conflict.

## Verification rules

For every implemented screen:

1. Use a real representative viewport.
2. Capture an emulator or device screenshot.
3. Compare it with the Figma reference.
4. Record deviations.
5. Validate light and dark, Russian and English, large text, and required states.
6. Do not update golden files automatically without review.

---

# INCOMPLETE FIGMA MAKE PROTOTYPE POLICY

Do not stop solely because the Figma Make prototype is not connected end to end.

Use approved screens, visual patterns, available specifications, and existing repository behaviour.

Before implementing any listed gap, verify whether the feature already exists in code. Preserve working business logic and restyle or integrate it rather than rebuilding it.

Absence from Figma does not prove absence from code.

Presence in a prototype does not prove the existence of backend, ML, storage, or real data support.

---

# REMAINING IMPLEMENTATION SCOPE — EMBEDDED v1.9

The Figma Make prototype may be partially wired and may omit ordinary error, offline, accessibility, and platform states. This does not block implementation when approved visual patterns exist and the repository contains the real capability.

Before each item, verify the current branch. Do not rely on stale reports.

## R0 — Figma Make and repository mapping audit

Before modifications, create:

`core/plans/FIGMA_MAKE_REFACTOR_AUDIT_<DATE>.md`

It must include:

1. Branch, HEAD, upstream, status, unpushed commits, and untracked files.
2. Accessibility of this exact Figma Make URL:
   `https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples?t=PknUCnJWYLxe5itJ-1`
3. Complete list of visible screens and states.
4. Complete list of transitions that actually work in the prototype.
5. Mapping:
   `Figma screen → Flutter route → page/widget → provider → repository/service`.
6. Classification for every item:
   - already implemented and visually aligned;
   - implemented but needs visual refactor;
   - implemented only in code;
   - represented only in Figma;
   - missing in both;
   - blocked by a decision;
   - blocked by unavailable asset, data, backend, or capability.
7. Existing design tokens and components suitable for reuse.
8. Missing Figma states that can safely be derived from the design system.
9. Privacy, ML, storage, billing, and schema risks.
10. Exact R1–R9 plan including files and tests.

After the report, STOP. Do not modify files, create a commit, or push.

## AUTHORITATIVE REQUIREMENTS RULE — DO NOT NARROW SCOPE BECAUSE A REPO DOC IS MISSING

This single-file master prompt and the approved Figma Make reference are the authoritative product/design requirements for this refactor.

Approved Figma Make reference:
`https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples?t=PknUCnJWYLxe5itJ-1`

If any repository audit/state document references `fitness-app-redesign.md` or another design file that is absent:

1. Record that repository reference as stale/missing documentation.
2. **Do not reduce the implementation scope.**
3. **Do not replace a full gate with only the first code gap discovered during audit.**
4. Continue planning from the requirements embedded in this master prompt and the approved Figma Make reference.
5. Only ask the operator when there is a genuine unresolved product decision that this prompt explicitly marks as open.
6. Missing documentation is not permission to invent behaviour, but it is also not permission to discard requirements already embedded here.

For R2 specifically, the full Scanner scope below is mandatory. A differentiated `_CameraUnavailable` message is only one sub-task inside R2, not the entire R2 gate.

---

## R1 — Home completion

Verify and, when needed, implement:

- weekly calendar;
- milestones block;
- horizontal recovery scroll;
- visible scroll affordance;
- correct partial-card reveal or another subtle horizontal-scroll cue;
- loading, empty, error, and offline states;
- safe areas;
- responsive widths;
- preserved Home priorities:
  1. Today Workout;
  2. Scan;
  3. weekly progress and recovery;
  4. milestones and secondary content.

Do not create a new visual language. Use the approved Home design and current semantic components.

## R2 — Scanner and Equipment completion

R2 is a **full Scanner completion gate**, not a one-file camera-error patch.

The design scope comes from the approved Scanner/D4 specification embedded below. Do not depend on a missing `fitness-app-redesign.md`. If an audit document points to that missing file, record the stale reference and continue with this section as the authoritative requirement.

### R2.1 Preserve existing recognition architecture

Before UI changes, audit and preserve the existing scanner/recognition chain, including any already implemented:

- live camera session;
- cloud recognition;
- timeout handling;
- on-device/local fallback;
- result smoothing or debouncing;
- alias/catalog resolution;
- recognition history;
- saved machine / My Machines state;
- existing privacy handling for captured frames;
- navigation to Equipment.

Do **not** introduce a second recognition pipeline, replace ML models, change catalog matching semantics, or change backend contracts in R2 without separate architecture/ML GO.

### R2.2 Mandatory Scanner UI states — all 14

The Scanner must explicitly support and test these fourteen product states:

1. **Permission** — explain why camera access is needed and request it contextually. Distinguish denied vs permanently denied when the platform provides that distinction; permanently denied should offer an Open Settings action.
2. **Ready** — live camera is initialized and the user can scan.
3. **Targeting** — the user is aligning the machine inside the target area; show concise guidance without blocking the camera.
4. **Capturing** — capture has been triggered; prevent accidental duplicate captures and give immediate visual feedback.
5. **Analyzing** — recognition is running; no infinite spinner, no fake confidence, cancellation/back behaviour remains safe.
6. **High-confidence result** — show the recognized equipment result and primary CTA to open it.
7. **Top-3 alternatives** — when confidence is not strong enough for one deterministic result, show up to three real candidates rather than silently choosing the nearest item.
8. **Unknown equipment** — honest unknown state; never substitute a nearest incorrect catalog item.
9. **Low light** — actionable message such as adding light / changing angle; allow retry.
10. **No equipment in frame** — distinguish this from generic recognition failure and instruct the user to center the machine.
11. **Timeout** — recognition exceeded the bounded wait; expose Retry and any valid local fallback.
12. **Offline fallback** — clearly indicate that cloud recognition is unavailable and the existing on-device/local fallback is being used when supported.
13. **Error** — actionable terminal/retryable error state. Camera-specific reasons must be differentiated where the runtime exposes them: permission denied, permission permanently denied, no camera, camera busy/in use, camera initialization failure, or other unavailable-hardware state. Internal exception text must never be shown.
14. **History** — scan history / My Machines / saved machine cards with stable navigation back to recognized equipment.

Do not collapse these into one generic `Camera unavailable` or `Something went wrong` state when the underlying cause is known.

### R2.3 Scanner camera composition and controls

Preserve or implement the approved camera UX:

- fullscreen or camera-first view;
- target/corner brackets;
- subtle sweep/scan feedback where already approved;
- concise glass instruction pill or equivalent approved component;
- flash control when supported;
- capture control;
- cancel/back;
- retry;
- direct history access.

The camera remains the dominant surface. Do not cover it with large cards or developer/debug information.

### R2.4 Recognition result sheet

A successful/alternative result should expose the approved result content using real data:

- equipment name;
- purpose/category;
- muscles where real mappings exist;
- number of compatible exercises;
- suitability/personalisation only when backed by real data;
- primary CTA: Open Equipment;
- alternatives when present;
- explicit `This is a different machine` / correction action where supported.

Never fabricate confidence percentages or suitability values.

### R2.5 Unknown-equipment flow

Unknown is a first-class valid result. The flow may show, when actually available:

- the user's captured image/thumbnail under the existing privacy/storage rules;
- a tentative machine name only when the recognition service really provides one;
- short description/use information only when backed by data;
- `Content is being prepared` / unsupported-catalog messaging;
- save machine card when existing product capability supports it;
- retry / scan again.

Do not invent a catalog mapping. Do not auto-route to a different machine merely to avoid an empty result.

Manual-search fallback remains a product decision unless it is already implemented or explicitly approved elsewhere. Do not silently add a new search/indexing backend.

### R2.6 History and saved machines

Verify the existing recognition history and My Machines behaviour before changing code. R2 must ensure:

- history is reachable from Scanner;
- entries render with stable IDs;
- saved machine cards reopen the correct Equipment page;
- deleted/invalid catalog entries fail honestly;
- empty history has a useful state;
- offline rendering uses already cached/local data where supported;
- no duplicate history record is created by one capture/result cycle.

### R2.7 Scan → Equipment navigation

High-confidence and user-selected alternative results must navigate to the correct equipment identity.

Verify:

- stable equipment ID is passed, not display-name matching;
- Back returns to Scanner without corrupting camera lifecycle;
- returning to Scanner does not create duplicate camera sessions;
- current scan state is reset or restored intentionally;
- deep-link/navigation behaviour remains compatible with the existing router.

### R2.8 AI Coach entry

If the approved design shows contextual AI Coach from Scan Result or Equipment, reuse the existing AI Coach service/sheet. Pass structured equipment context; do not create a second generic chat implementation.

### R2.9 Camera-unavailable differentiation — one sub-task, not the gate

The currently discovered `_CameraUnavailable` issue must be fixed inside R2 after auditing the actual `camera` package/runtime exceptions.

At minimum, distinguish the causes the current platform layer can reliably identify, such as:

- permission denied;
- permission permanently denied;
- camera busy/in use;
- no camera / unavailable hardware;
- initialization failure / unknown retryable camera error.

Use localized, human-readable text. Offer Open Settings only when appropriate. Do not display raw exception names/messages.

### R2.10 Required tests

Add or extend tests for the real state machine and UI boundaries. Cover, as applicable:

- permission denied;
- permanently denied + Open Settings action;
- ready;
- targeting;
- capture de-duplication;
- analyzing;
- high-confidence result;
- alternatives;
- unknown;
- low light;
- no equipment;
- timeout;
- offline fallback;
- differentiated camera unavailable errors;
- history empty/data states;
- saved machine navigation;
- scan → equipment navigation;
- camera lifecycle on leave/return;
- no duplicate camera session;
- localization for new user-facing copy.

Run the repository's normal Flutter analyze/test gates plus focused scanner tests. Device/integration checks are required for behaviour that cannot be proven in host widget tests, especially native camera lifecycle and real permission flows.

### R2.11 R2 Definition of Done

R2 is complete only when:

1. All fourteen Scanner states are represented in production UI or explicitly proven impossible/not applicable by current product capability.
2. Existing cloud/local recognition architecture is preserved.
3. Unknown equipment remains honest.
4. Camera errors are differentiated when the runtime exposes the reason.
5. History and saved machine cards work.
6. Offline/local fallback is explicit and non-deceptive.
7. Scan result opens the correct Equipment identity.
8. User-facing copy is localized.
9. Focused tests pass.
10. `flutter analyze` and the agreed regression test suite pass.
11. Emulator/device screenshots are compared with the approved Figma Make reference.
12. No unrelated backend/ML/catalog changes are included.

Act-gate review → local commit → STOP. Push only after separate push-GO.

## R3 — Dedicated Exercise Page

The Exercise Page is mandatory and must be a separate screen, not part of Equipment or Workout Player.

If the route is missing, add a dedicated route with a stable exercise ID.

The screen must use real catalogue, media, history, and restriction data and include:

- licensed anatomical animation or poster fallback;
- name;
- equipment;
- level;
- primary and secondary muscles;
- suitability or personalisation explanation;
- concise technique steps;
- full instructions;
- common mistakes;
- restrictions and contraindications only from real data;
- personal history;
- last performance;
- honest personal record when available;
- Start Exercise;
- Add to Workout;
- Technique Coach;
- AI Coach;
- loading;
- media unavailable;
- no history;
- unsupported or restricted state;
- long Russian and English content;
- accessibility.

Do not move workout logging or workout business state into this page. Pass context to Workout Player.

## R4 — Technique Coach entry and context

Preserve the existing `/form-check` route and real on-device pose pipeline when confirmed by audit.

Add entry points:

- Exercise Page → Technique Coach;
- Workout Player → Technique Coach;
- optional Workout Summary → retry Technique Coach only when supported.

Pass explicit context:

- exercise ID;
- exercise name;
- supported classifier or rule set;
- required camera angle;
- workout or session ID when applicable;
- target repetitions when applicable;
- language and voice preference.

Do not show debug coordinates, raw landmark IDs, or internal confidence dumps.

Do not save frames or video by default.

## R5 — WorkoutDone and WorkoutSummary consolidation

Q26 must be resolved before destructive mutation.

Recommended decision:

- `WorkoutSummary` becomes the only canonical completion screen;
- useful existing `WorkoutDone` logic is moved or reused;
- the old screen may temporarily remain as a thin compatibility wrapper only when needed for safe migration;
- one persisted completion path;
- one analytics event family;
- one navigation destination.

If the operator has not confirmed Q26, prepare an exact migration plan and STOP before route mutation.

## R6 — Rest Timer wiring

If Rest Timer exists as a screen or state but has no real navigation path, implement:

Complete Set
→ Persist Set
→ Rest Timer
→ Ready / Skip / Add Time
→ Next Set

Requirements:

- one authoritative timer state;
- no duplicate clocks;
- background and foreground lifecycle;
- restoration after app pause;
- sound and haptic behaviour according to settings;
- Skip, add 30 seconds, pause, resume, and next-set transition;
- timer behaviour must never lose a persisted set;
- unit, widget, and integration tests.

## R7 — Real Progress charts

Replace placeholders with real data-backed visualisations.

### Strength progression

- selected exercise;
- period selector;
- line chart using a valid metric;
- use estimated 1RM only if the formula is approved and already part of the domain;
- insufficient-data state.

### Volume

- weekly bars;
- formula must match workout-domain volume;
- no fabricated values.

### Consistency

- weekly or monthly workout frequency;
- calendar or bars based on the nearest approved pattern;
- timezone-safe dates.

### Muscle load

- anatomical map only when muscle mapping is reliable;
- otherwise ranked bars by aggregated muscle group;
- describe it as training distribution, not medical analysis.

Required for all charts:

- loading;
- empty;
- error;
- offline or stale;
- range selector;
- accessibility summary;
- large text;
- screenshot review.

## R8 — AI Coach contextual integration

Reuse the existing AI Coach UI, service, and cache. Do not create a second chat backend.

Add or verify entries from:

- Scan Result;
- Equipment;
- Exercise Page;
- Recovery;
- Workout Summary.

Pass structured context:

- source screen;
- equipment or exercise;
- active workout state;
- relevant history and recovery data within privacy constraints;
- locale.

AI Coach must not invent unavailable sensor, medical, or body-analysis data.

## R9 — Theme, platform, accessibility, offline, and end-to-end completion

### Light theme

When Figma Make does not provide a complete light theme:

- build a semantic light palette from approved brand tokens;
- do not mechanically invert colours;
- validate Home, Scanner, Exercise, Workout Player, Progress, and dialogs;
- provide screenshots before broad rollout;
- preserve dark theme without regression.

Light theme must not block early dark-theme implementation gates.

### Android and iOS

- SafeArea and system bars;
- Android predictive back;
- iOS swipe-back where appropriate;
- keyboard insets;
- camera lifecycle;
- permission wording and behaviour;
- native date, time, and picker behaviour where appropriate;
- no device-specific clipping.

### Accessibility

- touch targets at least 48 logical pixels where applicable;
- `Semantics` labels;
- logical focus order;
- no colour-only status;
- text scale 1.0, 1.3, 1.6, and 2.0;
- reduced motion;
- screen-reader-friendly chart summaries;
- accessible camera controls and timers.

### Offline

At minimum verify:

- Home cached or limited state;
- Scanner local fallback;
- Workout Player and set logging;
- Rest Timer;
- Progress cached or empty state;
- retry and sync status.

### End-to-end wiring

Implement a real happy path even when prototype wiring is incomplete:

Onboarding
→ Home
→ Scan
→ Result
→ Equipment
→ Exercise Page
→ Workout Player
→ Complete Set
→ Rest Timer
→ Next Set
→ Technique Coach
→ Workout Summary
→ Progress
→ Progress Photos

There must be no dead routes, dead CTA, or screen enum without navigation.

---

# PROVISIONAL DECISIONS FOR PLANNING

These defaults may be used for planning and non-destructive UI, but must remain marked provisional until the operator explicitly approves them:

- Flutter, Riverpod, and go_router remain locked.
- Figma Make generated code is not ported to production.
- Existing ML pipeline is reused.
- Technique Coach does not show raw confidence percentage; use human-readable reliability states.
- Technique Coach history stores summary metadata only, without frames or video, until another privacy policy is approved.
- Voice cues follow app or system language and use existing on-device TTS when the audit confirms it.
- Progress Photos are private by default.
- Comparing different photo angles shows a warning; never compare silently.
- Light theme does not block the first dark-theme implementation gates.
- WorkoutSummary consolidation requires operator confirmation before route mutation.

---

# REQUIRED TEST MATRIX FOR THE REMAINING SCOPE

## Unit tests

- calculations and aggregations;
- Progress chart series;
- timer state and lifecycle;
- route and context parsing;
- exercise-history mapping;
- AI context builder;
- pure theme-token mapping where applicable;
- offline and sync state transitions;
- Form Check gates and repetition state machine;
- progress-photo metadata and export options.

## Widget tests

- Home calendar, milestones, and recovery scroll;
- Scanner saved, unknown, low-confidence, and offline states;
- Exercise Page loaded, loading, no-history, media-error, and restriction states;
- Technique Coach entry visibility and unsupported state;
- Rest Timer controls;
- canonical Workout Summary;
- every Progress chart state;
- AI Coach contextual CTA;
- light and dark modes;
- large text;
- Semantics for controls and charts.

## Integration tests

- Scan → Equipment → Exercise;
- Exercise → Workout;
- Exercise → Technique Coach;
- Workout set → Rest Timer → next set;
- workout completion → one canonical Summary;
- Summary → Progress;
- offline workout logging and later sync;
- app restart restores appropriate state;
- actual camera and ML smoke test on hardware;
- progress-photo capture, save, compare, delete, and export.

## Visual tests

- emulator or device screenshot for every key screen;
- comparison with Figma Make or exported reference;
- documented intentional deviations;
- representative Android and iOS viewports;
- Russian and English;
- dark and light;
- large text.

---

# EXECUTION ORDER

1. R0 read-only audit only → report → STOP.
2. After audit-GO, run Design System and token gate if needed.
3. R1 Home.
4. R2 Scanner and Equipment.
5. R3 Exercise Page.
6. R4 Technique Coach entries.
7. R5 Summary consolidation only after Q26 decision.
8. R6 Rest Timer wiring.
9. R7 Progress charts.
10. R8 AI Coach context integration.
11. R9 theme, platform, accessibility, offline, and end-to-end completion.
12. Final regression and handoff.

Do not combine everything into one giant commit.

After every implementation gate:

- perform scoped diff review;
- run targeted tests;
- run broader regression tests;
- run `flutter analyze`;
- capture a real emulator or device screenshot;
- update audit and state documents;
- create one local commit;
- STOP;
- push only after separate `push-GO`.

---

# FIRST MESSAGE / REQUIRED RESPONSE FROM THE DEVELOPMENT AGENT

Start only with R0 / Gate 0 read-only audit.

The first response must provide:

1. Git baseline.
2. Whether the exact Figma Make link is accessible.
3. Which screens, states, and transitions are actually visible.
4. Repository feature inventory.
5. Screen-to-code mapping.
6. Figma-versus-code gap classification.
7. Decisions and blockers.
8. Gate plan with exact files and tests.
9. Risks.
10. Explicit statement: `STOP — no files modified`.

Do not modify files, create a commit, or push before a separate GO.


---

# FIGMA MAKE → GITHUB REFERENCE REPOSITORY PROTOCOL — v1.9

## Repository separation is mandatory

The production Flutter application and the Figma Make generated project must remain in separate repositories.

### Production repository

`https://github.com/xLZDx/Fitness-App`

This is the only repository in which production Flutter/Dart implementation is allowed.

### Figma Make reference repository

Create a separate repository from Figma Make, recommended name:

`fitness-app-figma-make-reference`

This repository is a generated UX/interaction reference. It may contain web-oriented code such as TypeScript, React, CSS, or other Make-generated implementation details.

Do not merge or copy this generated application wholesale into the Flutter repository.

## Figma Make GitHub limitations

Treat the following as architecture constraints:

1. Figma Make creates and pushes only to a repository created through its own GitHub integration.
2. It cannot push directly to the existing `xLZDx/Fitness-App` repository.
3. Synchronization is one-way: Figma Make → GitHub.
4. Changes made in GitHub are not synchronized back into Figma Make.
5. A later Make push may overwrite GitHub-side edits in the Make-created repository.
6. Make pushes only to the repository default branch.
7. Branch selection and normal branch management are not supported by Make.

Therefore, never use the Make-created repository as a production development branch.

## Required local workspace layout

Prefer two sibling clones:

```text
<workspace>/
├── Fitness-App/                         # production Flutter repo
└── fitness-app-figma-make-reference/   # generated Make reference repo
```

Do not combine unrelated histories and do not add the generated repository as a branch of the Flutter repository.

## Gate 0 must inspect both repositories

During the read-only audit:

1. Verify the exact commit SHA of both repositories.
2. Inspect the Make reference repository only for:
   - screen inventory;
   - interaction behaviour;
   - navigation flow;
   - copy/text;
   - states;
   - visual hierarchy;
   - reusable raw assets whose licensing is verified.
3. Map every relevant Make screen to the production Flutter route, widget, provider, repository, and service.
4. Classify each item as:
   - already implemented;
   - visual refactor only;
   - missing behaviour;
   - missing screen;
   - prototype-only and not suitable for production;
   - web-specific and must not be ported.
5. Do not run package installation or generated web builds unless needed for the audit and explicitly approved.
6. Do not modify either repository during Gate 0.

## Source-of-truth hierarchy

Use this priority order:

1. Explicit operator decisions and approved product requirements.
2. Existing production business logic, data contracts, privacy rules, and repository invariants.
3. Approved Figma Make UX and visual behaviour.
4. Generated Make source code only as a supporting reference.

When generated Make code conflicts with the Flutter architecture or production logic, preserve the Flutter architecture and implement the intended UX natively.

## Update workflow

When the Figma Make design changes:

1. The operator pushes the update from Figma Make to its linked GitHub repository.
2. The developer fetches or pulls the Make reference repository.
3. The developer records the new Make commit SHA.
4. The developer compares the old and new Make commits.
5. Only approved differences are ported into Flutter through a scoped implementation gate.
6. The Make repository remains read-only from the developer workflow.

## Snapshot recommendation

After a meaningful Figma Make push, create an immutable Git tag or snapshot branch in the reference repository, for example:

```text
figma-make-v1.9
```

This preserves the exact design reference used for a Flutter implementation gate.

## Prohibited actions

- Do not push Figma Make directly into `xLZDx/Fitness-App`.
- Do not merge Make `main` into Flutter `main`.
- Do not replace Flutter widgets with screenshots of the Make prototype.
- Do not copy React/TypeScript architecture into Flutter.
- Do not edit the Make-created repository and expect changes to return to Figma.
- Do not perform production work on the Make repository default branch.
- Do not allow a later Figma Make push to silently redefine already approved production behaviour.
