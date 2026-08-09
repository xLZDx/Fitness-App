# FITNESS APP — SINGLE-FILE DEVELOPMENT MASTER PROMPT v1.6

Ты — Senior Flutter Engineer, Mobile UI Architect, Product Engineer и
implementation specialist для сложных fitness/health приложений.

Нужно внедрить утверждённый Figma-редизайн и выполнить безопасный поэтапный
рефактор существующего Fitness App.

Repository:
https://github.com/xLZDx/Fitness-App

Figma Make — основной UX, visual и interaction reference:
https://www.figma.com/make/9jSH442Xw2Bhgb8ARm3u5o/Review-Existing-Examples?t=PknUCnJWYLxe5itJ-1

Approved handoff version:
v1.6

Важно: ссылка ведёт на Figma Make functional prototype. Используй её для
понимания экранов, визуальной иерархии, copy, states, transitions и interaction
behaviour. Не переноси generated web/React code из Figma Make в приложение.
Production implementation остаётся в существующем Flutter/Dart repository.


## PRIMARY SOURCES AND PRECEDENCE

Используй источники в таком порядке:

1. Актуальный repository и тесты — source of truth для реальных capabilities,
   данных, lifecycle, persistence, security и backend contracts.
2. Figma Make по ссылке выше — source of truth для утверждённого UX,
   визуального языка и interaction intent.
3. Существующие Flutter theme/components — source of truth для реализации
   semantic tokens до завершения token mapping.
4. Этот prompt — source of truth для scope, gates, invariants и дисциплины.

При конфликте:

- не копируй невозможное или fake behaviour из prototype;
- не удаляй working capability только потому, что её нет в Figma Make;
- не добавляй fake data или fake AI;
- зафиксируй конфликт в Gate 0 report;
- предложи безопасное решение;
- STOP до operator GO, если конфликт затрагивает schema, privacy, billing,
  ML pipeline или пользовательские данные.

### Доступ к Figma Make

В начале Gate 0 проверь, открывается ли ссылка и что именно доступно:

- preview;
- screens;
- interactions;
- prompt/conversation history, если permissions разрешают;
- generated project files, если permissions разрешают.

Если Figma Make недоступна:

- не утверждай, что дизайн проверен;
- перечисли недоступные материалы;
- продолжай repository audit;
- используй приложенные screenshots/exports, если они есть;
- STOP перед visual implementation, если отсутствует необходимый reference.

Если Figma Make доступна, generated code использовать только как behavioural
reference. Не переносить React, CSS, HTML, web routing или browser storage в
Flutter.

Это существующий рабочий проект. Не создавай новый Flutter-проект, не переноси
его во FlutterFlow и не переписывай архитектуру с нуля.

Работай только с актуальным состоянием repository после fetch/pull и проверки
HEAD. Старые документы и прежние отчёты могут быть историческими; текущий код,
тесты и актуальные state/gate документы имеют приоритет.

---

## 1. Цель

Преобразовать приложение из стандартного tile-based UI в современный,
goal-driven, context-aware продукт, сохранив существующую бизнес-логику,
данные, recognition pipeline, workout lifecycle и privacy guarantees.

Главный flow:

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
→ Summary
→ Progress
→ Progress Photos Compare.

Figma — source of truth для UI/UX.
Repository — source of truth для бизнес-логики и реальных capabilities.

При конфликте остановись и сообщи. Не придумывай поведение.

---

## 2. Сохраняемый стек

Сохрани:
- Flutter / Dart;
- Riverpod;
- go_router;
- feature-first architecture;
- Firebase Auth;
- Firestore;
- Firebase Functions;
- существующие camera/ML services;
- existing catalog loaders;
- workout services;
- localisation;
- test architecture.

Запрещено без отдельного architecture-GO:
- Bloc/GetX/MobX;
- новый router;
- новая параллельная state system;
- новый backend schema;
- новый recognition pipeline;
- перенос во FlutterFlow;
- полное переписывание feature.

---

## 3. Gate 0 — Mandatory Read-Only Audit

До любых изменений:

### Git
- branch;
- HEAD;
- upstream;
- git status;
- unpushed commits;
- untracked files;
- concurrent changes.

### Documents
Прочитай:
- CLAUDE.md;
- core/TECHSTACK.md;
- core/CODEMAP.md;
- актуальные state/gate docs;
- changelog;
- current theme and routing docs.

### Code inventory
Найди:
- theme/tokens;
- navigation shell;
- onboarding/auth;
- profile models;
- body metrics logic;
- Home;
- Scanner;
- Equipment;
- Exercise;
- Workout Player;
- Rest Timer;
- Form Check;
- Progress;
- Progress Photos или related media features;
- Programs;
- AI Coach;
- Subscription;
- Health Connect;
- storage/share/permissions;
- tests.

### Audit outputs
Создай mapping:

Figma screen
→ existing route
→ existing widget
→ providers/services
→ existing models
→ missing capabilities
→ risks
→ tests
→ gate assignment.

Отдельно перечисли:
- hardcoded colors;
- hardcoded strings;
- duplicate cards;
- oversized widgets;
- business logic in UI;
- expensive rebuilds;
- lifecycle risks;
- missing states;
- schema/privacy conflicts.

После Gate 0 предоставь implementation plan и STOP без изменений.

---

## 4. Architecture Rules

1. UI не содержит бизнес-логику.
2. Не дублировать source of truth.
3. Providers/services сохраняют ответственность.
4. Не создавать repository ради presentation.
5. Models менять только при доказанной необходимости.
6. Backend schema — только отдельный GO.
7. Recognition pipeline не менять в UI gate.
8. Workout calculations не менять без separate scope.
9. Injury filtering не менять в visual gate.
10. Subscription products не выдумывать.
11. Production code не содержит fake data.
12. User strings проходят localization.
13. Internal exceptions не показываются пользователю.
14. Unrelated files не трогать.
15. Scope не расширять молча.

---

## 5. Design System Refactor

Сначала tokens, затем components, затем screens.

Адаптируйся к существующей структуре. Возможная структура:

lib/core/theme/
- app_theme.dart
- app_palette.dart
- app_semantic_colors.dart
- app_typography.dart
- app_spacing.dart
- app_radius.dart
- app_elevation.dart
- app_motion.dart
- app_component_sizes.dart
- app_breakpoints.dart

Semantic tokens:
- backgroundPrimary
- backgroundSecondary
- surfacePrimary
- surfaceElevated
- surfaceInteractive
- textPrimary
- textSecondary
- textDisabled
- accentPrimary
- accentSecondary
- success
- warning
- danger
- outline
- cameraOverlay
- poseCorrect
- poseWarning
- poseError

Не распространять по feature widgets:
- random Color literals;
- случайные EdgeInsets;
- локальные TextStyles;
- hardcoded radii.

Light/dark — отдельные semantic configurations.

---

## 6. Component Library

Минимальный набор:
- AppPrimaryButton
- AppSecondaryButton
- AppTertiaryButton
- AppIconButton
- AppTopBar
- AppNavigationBar
- AppChoiceCard
- AppMultiSelectCard
- AppChip
- MuscleChip
- EquipmentChip
- RecommendationHero
- GoalProgressCard
- RecoveryStatus
- WorkoutCard
- ProgramCard
- ExerciseMediaCard
- EquipmentMediaCard
- AIInsightCard
- BodyMetricPicker
- SetLogger
- WeightInput
- RepsInput
- RestTimerCard
- CameraTargetOverlay
- RecognitionResultSheet
- ConfidenceIndicator
- EmptyState
- ErrorState
- OfflineState
- PermissionState
- LoadingSkeleton
- WorkoutBottomControls
- FormCheckCue
- WorkoutSummaryMetric
- ProgressPhotoCard
- ProgressPhotoTimelineItem
- ProgressPhotoCompareView

Не создавать giant AppCard с десятками optional arguments.

Presentational components не должны напрямую зависеть от feature providers.

---

## 7. Localisation and Units

Все новые строки через существующий localization pipeline.

Проверить:
- RU/EN;
- plurals;
- kg/lb;
- cm/ft;
- date/time;
- long Russian strings;
- accessibility labels;
- permission explanations;
- errors.

Не допускать hardcoded English в русском UI.

Unit conversions должны сохранять точность и не накапливать drift.
Canonical storage units определить из текущей модели; если отсутствуют,
предложить решение и STOP до GO.

---

## 8. Onboarding Refactor

Flow:
1. Value proposition.
2. Goal.
3. Experience.
4. Location.
5. Equipment.
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

Требования:
- one primary question per screen;
- progress indicator;
- back navigation;
- resumable draft;
- skip only optional;
- preview before account/paywall;
- no fake progress;
- no fake goal forecast;
- no notification permission before context.

Использовать existing profile/onboarding models. Если поля отсутствуют,
предоставить minimal schema proposal и STOP до GO.

Plan Preview использует реальный generator/fallback, не fake fixture в
production.

---

## 9. Body Metrics

### 9.1 BodyMetricPicker
Variants:
- birthYear;
- height;
- currentWeight;
- targetWeight.

Features:
- wheel/ruler interaction;
- direct input;
- haptic ticks;
- `−` / `+` accessibility controls;
- kg/lbs;
- cm/ft;
- light/dark;
- large text;
- resume.

### 9.2 Pure Calculator
Derived values не хранить в Firestore.

Формулы:

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

Каждый percentage документирует denominator.

Adult classification только для age 20+.
Для younger users взрослая категория не показывается.

### 9.3 Feedback
Состояния:
- inside range;
- below range;
- above range;
- missing height;
- missing age;
- under 20;
- muscular-body limitation note;
- target outside range;
- target not set.

Нейтральные формулировки, без diagnosis/shaming.

---

## 10. Health Connect

Permission только после explicit CTA.

Сохрани текущие integrations и contracts.
Не обещать recovery capabilities, которых нет.

Обработать:
- unsupported device;
- denied;
- permanently denied;
- partial permissions;
- disconnected;
- stale data;
- reconnect.

---

## 11. Navigation

Tabs:
- Home
- Scan
- Workouts
- Progress
- Profile

Сохранить existing deep links/route names где возможно.

Обязательно:
- Android back;
- predictive back;
- iOS swipe-back;
- state restoration;
- tab state preservation;
- scroll state;
- safe areas;
- edge-to-edge;
- keyboard insets.

---

## 12. Home Refactor

Порядок:
1. Greeting.
2. Program progress.
3. Today hero.
4. Start/Continue.
5. Quick Scan.
6. Recovery.
7. Weekly progress.
8. Last achievement.
9. Progress photo card conditional.

Каждый блок:
- loading;
- data;
- empty;
- error.

Не смотреть все providers без необходимости.
Не rebuild всего Home каждую секунду.

Progress-photo card показывать только при минимум двух совместимых фото.

---

## 13. Scanner Refactor

Не менять recognition service в UI gate.

Сохранить:
- cloud recognition;
- timeout;
- local fallback;
- alias resolution;
- unknown handling;
- history.

UI states:
- permission;
- ready;
- analyzing;
- success;
- alternatives;
- unknown;
- timeout;
- offline fallback;
- actionable error.

Нет бесконечного spinner.
Нет fake confidence.
Unknown не превращать в nearest wrong catalog item.

Соблюдать существующую privacy policy обработки кадров.

---

## 14. Equipment Page

Использовать existing `equipmentHeroImageProvider` или актуальный аналог.
Hero — poster связанного лицензированного упражнения.
Не возвращать stock photos.

Structure:
- hero;
- name/category;
- purpose;
- muscles;
- suitability;
- safety;
- featured exercise;
- compatible exercises;
- AI Coach;
- add to workout.

Lazy media loading, stable keys, thumbnails first.
Не менять equipment linking в UI gate.

---

## 15. Exercise Page

Использовать реальные:
- posters/clips;
- muscles;
- equipment;
- instructions;
- restrictions;
- history;
- AI service.

Poster first, video on interaction.

Lifecycle:
- pause on background;
- dispose controllers;
- no audio leak;
- orientation restore.

---

## 16. Workout Player and Set Logger

Данные:
- current exercise;
- current set;
- total sets;
- weight;
- reps;
- previous result;
- timer;
- rest;
- workout duration.

После complete set:
1. Persist через existing source of truth.
2. Confirmation.
3. Undo.
4. Start rest timer.
5. Advance согласно existing rules.

Не создавать presentation state, расходящийся с persisted state.

Timer изолировать от rebuild всего screen.

Guard finish action.

---

## 17. Rest Timer

Features:
- remaining time;
- next target;
- skip;
- +30 sec;
- pause/resume;
- completion haptic/notification;
- background lifecycle.

Tests:
- starts once;
- no double timer;
- add time;
- skip;
- pause/resume;
- background/foreground;
- completion.

---

## 18. Тренер по технике / Live Form Check

Это отдельный технический subsystem, а не только новый camera widget.
Не переписывай detector/classifiers в visual gate и не меняй ML pipeline без
отдельного GO.

### 18.1 Обязательный read-only audit Form Check

До изменений найди и задокументируй:

- поддерживаемые упражнения;
- поддерживаемые ракурсы каждого упражнения;
- фактический pose detector и его runtime;
- landmark coordinate space;
- обязательные landmarks для каждого rule/classifier;
- body-in-frame/visibility logic;
- low-light и blur detection;
- angle validation;
- rep counter state machine;
- top/bottom thresholds и hysteresis;
- cue gating/cooldown;
- TTS implementation;
- camera lifecycle;
- frame sampling rate;
- current privacy behaviour;
- записываются ли кадры или видео;
- все debug overlays и developer strings, попавшие в production UI.

Отдельно зафиксируй строку типа `pose[pixels]...`, видимую в текущем UI.
Она является debug output и должна быть удалена из production presentation,
но может сохраняться только за явным debug flag в development build.

После аудита покажи contract:

Camera Frame
→ Pose Detector
→ Frame Quality Gate
→ Required-Joint Visibility Gate
→ Angle Gate
→ Exercise Classifier / Rule Engine
→ Rep Counter
→ Cue Gate
→ UI State
→ TTS.

Не объединяй эти слои в один giant widget.

### 18.2 Архитектурные границы

Предпочтительно сохранить или выделить независимые contracts:

- `PoseFrameResult`;
- `FrameQualityResult`;
- `VisibilityGateResult`;
- `AngleGateResult`;
- `MovementPhase`;
- `RepEvent`;
- `TechniqueCue`;
- `TechniqueCoachState`.

Названия адаптировать к существующей кодовой базе.
Не создавать параллельные models, если эквиваленты уже существуют.

UI не вычисляет углы суставов и не решает, засчитан ли повтор.
UI только отображает state из domain/application layer.

### 18.3 Entry Points и Session Context

Запускать Form Check только с известным context:

- exerciseId;
- required/supported angle;
- active workout/session ID, если запуск из Workout Player;
- expected camera orientation;
- supported capabilities.

Entry points:

1. Exercise Page.
2. Workout Player.
3. Optional pre-set setup.

Для unsupported exercise показывать честный state, а не запускать generic
classifier.

### 18.4 Pre-check Screen

Показать реальные данные:

- exercise title;
- required angle;
- camera placement;
- body visibility requirements;
- privacy copy, соответствующий реальной реализации;
- CTA camera start.

Не утверждать on-device processing, если audit это не подтверждает.

### 18.5 Camera Presentation

Production screen:

- top bar: back, title, flash, sound, help;
- camera as dominant area;
- silhouette/angle guide;
- landmark/skeleton overlay;
- segment states;
- quality banner;
- rep counter;
- movement phase;
- one live cue;
- pause/finish.

Никогда не показывать пользователю:

- raw landmark arrays;
- `pose[pixels]` coordinates;
- raw model confidence dumps;
- internal rule IDs;
- stack traces;
- classifier names;
- developer logs.

Debug overlay разрешён только при explicit debug flag и non-release build.
Добавь тест, что release/presentation state не содержит debug copy.

### 18.6 Frame Quality Gates

До реп-счёта проверять подтверждённые текущей архитектурой gates:

- camera initialized;
- minimum light/brightness;
- blur/stability;
- exactly one person, если detector это поддерживает;
- body scale/distance;
- required joints visible;
- full body/required body region in frame;
- required camera angle;
- pose confidence threshold;
- calibration complete.

Результат каждого gate должен иметь:

- machine-readable reason;
- localized user message;
- severity;
- recoverable flag.

Пока required gates не пройдены:

- rep counter frozen;
- no rep event;
- no score;
- no positive/negative form verdict;
- no misleading success TTS.

### 18.7 Rep Counter Invariants

Счётчик должен:

- работать только после ready/calibrated state;
- использовать существующую movement state machine;
- иметь hysteresis/debounce;
- не считать один цикл дважды;
- не засчитывать partial rep после pose loss;
- не считать во время low quality/wrong angle;
- корректно восстанавливаться после краткой потери landmarks;
- явно различать detected reps и evaluated reps;
- иметь deterministic tests на последовательностях landmarks/angles.

Если текущая реализация считает от верхней точки движения, UI и voice setup
должны объяснять это простым пользовательским языком, не показывая внутренние
threshold values.

### 18.8 Live Cue Gate

Одновременно активна максимум одна primary cue.

Требования:

- priority ordering;
- cooldown;
- duplicate suppression;
- no overlapping TTS;
- visible cue и spoken cue используют один localization key;
- потеря visibility имеет приоритет над technique correction;
- не повторять одну ошибку каждый frame;
- cue очищается после исправления или timeout;
- cue history не должна бесконтрольно расти.

### 18.9 Pose Loss / Quality Drop During Set

При потере pose или обязательного gate:

- перейти в paused/cannotEvaluate state;
- заморозить rep counter;
- текущий неполный rep не засчитывать;
- остановить technique scoring;
- показать actionable localized message;
- безопасно продолжить после восстановления и recalibration, если требуется.

Не сбрасывать весь завершённый set без причины.

### 18.10 Overlay Rendering

Skeleton overlay должен использовать одну систему координат с camera preview,
учитывая:

- crop/fit mode;
- rotation;
- front-camera mirroring;
- device orientation;
- preview aspect ratio;
- letterboxing;
- viewport resize.

Добавить golden/widget tests или deterministic transform tests, чтобы точки не
смещались относительно тела при разных aspect ratios.

Segment states:

- neutral;
- correct;
- warning;
- error;
- unavailable.

Цвет дублировать icon/text semantics.

### 18.11 TTS и Audio

- sound toggle сохраняет visual cues;
- no overlapping utterances;
- lifecycle pause stops or safely resumes speech;
- same localization source for text and TTS;
- rate limiting;
- errors TTS не блокируют visual coaching;
- Bluetooth/audio interruptions не ломают session state.

### 18.12 Privacy и Recording

Сохраняй текущую privacy architecture.

Если обработка on-device и frames не отправляются, это должно быть подтверждено
кодом и network audit до отображения такого promise.

По умолчанию:

- не сохранять raw frames;
- не записывать video;
- не прикладывать camera images к analytics/crash reports;
- не логировать landmark payloads с user identifiers;
- не делать replay UI без отдельной recording feature и explicit opt-in.

### 18.13 Lifecycle и Performance

Проверить:

- permission flow;
- camera init failure;
- app background/foreground;
- route pop;
- controller disposal;
- orientation changes;
- front/back switching;
- screen wake lock policy;
- thermal warning;
- frame backpressure;
- detector concurrency;
- no queue growth;
- UI isolate responsiveness;
- no full-page rebuild per frame;
- overlay repaint isolation;
- target FPS на поддерживаемом среднем Android device.

Если обработка не успевает, дропать устаревшие frames, а не строить очередь.

### 18.14 Summary

Использовать только реальные события session:

- detected reps;
- evaluated reps;
- unevaluated reps;
- top 1–2 positive observations;
- top 1–2 corrective priorities;
- insufficient-data state;
- return to workout;
- retry set.

Не показывать aggregate score при недостаточном количестве evaluated reps.
Не обещать video replay, если recording отсутствует.

### 18.15 Required UI States

Реализовать:

- unsupported exercise;
- angle selection;
- permission explanation;
- denied/permanently denied;
- camera unavailable;
- initialization;
- low light;
- blur;
- too close/far;
- partial body;
- missing joints;
- wrong angle;
- multiple people;
- calibration;
- ready;
- countdown;
- active;
- cue warning/error;
- pose lost;
- paused;
- cannot evaluate rep;
- detector error;
- thermal/performance warning;
- completed;
- insufficient-data summary.

### 18.16 Tests

Unit/domain:

- each quality gate;
- gate precedence;
- angle validation;
- visibility thresholds;
- rep state machine;
- hysteresis/debounce;
- no double count;
- no count while invalid;
- partial rep on pose loss;
- recovery after pose restoration;
- cue priority/cooldown/deduplication;
- detected vs evaluated counts;
- insufficient-data summary.

Widget/golden:

- all camera states with fake camera surface;
- overlay alignment;
- rep counter;
- live cue;
- low-light banner;
- wrong-angle banner;
- pose-lost state;
- sound toggle;
- large text;
- RU/EN;
- high contrast;
- no debug text in production UI.

Integration/device:

- permission lifecycle;
- camera start/stop;
- background/foreground;
- session resume;
- orientation;
- front-camera mirroring;
- TTS interruption;
- sustained processing soak;
- memory/controller leaks;
- thermal degradation behaviour.

Critical invariant:
не показывать score и не считать rep, если required visibility/quality/angle
gates не пройдены.

---

## 19. Workout Summary

Использовать реальные данные:
- duration;
- sets;
- volume;
- PR;
- difficulty;
- form feedback;
- recovery;
- next workout.

Не добавлять fake achievements.

Milestone prompt на progress photo может показываться только по реальному
условию, не после каждой тренировки.

---

## 20. Progress

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

No fake percentages.
Recovery labels должны быть честными.

Charts:
- accessible labels;
- correct axes/date ranges;
- no misleading smoothing;
- empty states;
- efficient repaint.

---

## 21. Progress Photos

Отдельный feature внутри Progress.

### 21.1 Gate P0 Audit
До реализации проверить:
- camera/photo picker;
- local storage;
- cloud storage;
- Firestore metadata;
- encryption/access rules;
- account deletion;
- data export;
- notifications;
- EXIF;
- existing privacy promises.

Storage policy требует явного решения:
A. Local-only.
B. Local-first + optional backup.
C. Cloud-synced.

Не выбирать молча.

### 21.2 Model
Минимально:
- id;
- userId;
- capturedAt;
- angle;
- localPath;
- remotePath?;
- thumbnailPath?;
- weightKg?;
- note?;
- milestoneTag?;
- createdAt;
- updatedAt;
- syncState.

Angles:
- front;
- sideLeft/sideRight или канонический side согласно утверждённой модели;
- back;
- custom/free.

Не хранить body score/fat estimate/beauty score.

### 21.3 Privacy Invariants
- private by default;
- no public URLs;
- no AI analysis without explicit opt-in and scope;
- no analytics attachment;
- deletion removes metadata and bytes;
- account deletion handles all photos;
- export strips location EXIF;
- no sensitive paths/tokens in logs;
- sync failure never deletes local original.

### 21.4 Capture
- select angle;
- silhouette guide;
- camera;
- timer;
- flash;
- switch;
- preview;
- retake/save;
- orientation normalization;
- metadata.

Не сохранять до explicit confirmation.

### 21.5 Timeline
- thumbnails;
- date;
- angle;
- optional weight;
- note/milestone;
- filters;
- multi-select;
- edit/delete/compare.

Не декодировать originals в list.

### 21.6 Compare
Modes:
- side-by-side;
- overlay slider.

Controls:
- swap;
- hide weight/date;
- fit/fill;
- select other;
- manual scale/x/y/rotation/reset.

Original files immutable.
No morphing.

Auto-align только отдельным optional gate после проверки on-device feasibility.

### 21.7 Export
- preview required;
- hide/show weight/date;
- optional face blur;
- watermark;
- save/share;
- strip EXIF;
- no auto-post.

### 21.8 Home
Card only with at least two compatible photos.
No empty card.
Not above Today/Scan.

### 21.9 Reminder
Contextual 2/4/8 weeks or none.
Permission only after agreement.

---

## 22. Workout Library and Programs

Search/filter/sort:
- goal;
- level;
- location;
- equipment;
- duration;
- muscles;
- limitations.

Не показывать compatibility percentage без реального scoring algorithm.

Использовать honest labels.

---

## 23. AI Coach

Сохранить existing AI service and caching.

Contextual entry points:
- Equipment;
- Exercise;
- Workout;
- Summary;
- Recovery;
- Plan.

States:
- loading;
- cached;
- timeout;
- retry;
- offline fallback;
- safety disclaimer.

Не отправлять лишние personal data.
Не менять server prompt/contract без отдельного scope.

---

## 24. Profile, Settings and Subscription

Profile/settings:
- personal data;
- goals;
- units;
- Health Connect;
- notifications;
- privacy;
- progress-photo storage/sync settings при наличии решения;
- subscription;
- help.

Billing logic не менять.
UI строить только по реальным products.

Тестировать:
- loading products;
- no products;
- pending;
- success;
- failure;
- cancelled;
- restore;
- already subscribed;
- offline.

---

## 25. Accessibility

Обязательно:
- Semantics;
- screen-reader order;
- 44–48dp targets;
- Dynamic Type;
- text scale 1.0/1.3/1.6/2.0;
- contrast;
- no color-only states;
- reduced motion;
- accessible charts;
- drag alternatives;
- long RU strings;
- safe areas.

Не использовать fixed-height cards для dynamic text.

---

## 26. Responsive and Platforms

Проверить:
- small Android;
- common Android;
- large Android;
- iPhone safe areas;
- landscape workout;
- tablets without breakage;
- keyboard;
- cutouts;
- gesture nav.

Не создавать отдельные pixel-perfect copies per device.

---

## 27. Performance

Цели:
- 60 FPS на среднем Android;
- no full-page timer rebuild;
- no BackdropFilter over scrolling lists;
- lazy media;
- poster before video;
- thumbnails in progress-photo timeline;
- correct cache dimensions;
- no repeated parsing;
- stable keys;
- controller disposal;
- no OOM compare/export.

Измерять до оптимизации:
- rebuilds;
- frame times;
- memory;
- image decode;
- camera CPU;
- video lifecycle;
- export memory.

---

## 28. Error, Empty, Loading and Permission States

Для каждого feature:
- loading;
- empty;
- partial;
- stale;
- retryable error;
- terminal error;
- offline;
- denied;
- permanently denied;
- interrupted session.

No infinite spinners.

---

## 29. Testing Strategy

После каждого gate:
- unit;
- widget;
- golden/screenshot;
- integration where needed;
- existing regressions;
- flutter analyze;
- manual emulator;
- dark/light;
- RU/EN;
- large text;
- small/large screens.

Critical flows:
- onboarding resume;
- body metrics calculations;
- plan preview;
- Home states;
- scan success/alternatives/unknown/timeout;
- equipment/exercise media lifecycle;
- log set/undo/rest;
- interrupted workout;
- Technique Coach setup, quality gates, overlay alignment, rep counting, cue gating and visibility invariant;
- summary;
- progress;
- progress photo capture/save/compare/delete/export;
- subscription.

Не обновлять goldens без visual diff review.

---

## 30. Screenshot Comparison

Для каждого approved Figma screen:
1. matching viewport;
2. emulator screenshot;
3. compare;
4. log spacing/typography/color/alignment/state differences;
5. fix proven mismatches;
6. no production fake data.

---

## 31. Gate Sequence

G0 — Read-only audit and mapping.
G1 — Design tokens.
G2 — Base components and states.
G3 — Navigation shell.
G4 — Onboarding core.
G5 — Body Metrics and Health Connect presentation.
G6 — Plan Preview and account flow.
G7 — Home.
G8 — Scanner.
G9 — Equipment.
G10 — Exercise.
G11 — Workout Player and Set Logger.
G12 — Rest Timer and workout lifecycle.
G13A — Form Check read-only audit and state contracts.
G13B — Technique Coach setup, permission and quality-gate presentation.
G13C — Live skeleton overlay, rep counter, movement phase and cue gating.
G13D — Form Check summary, accessibility, lifecycle and performance validation.
G14 — Workout Summary.
G15 — Progress and Recovery.
G16 — Progress Photos audit/storage decision.
G17 — Progress Photos capture/timeline.
G18 — Progress Photos compare/export/Home integration.
G19 — Programs/library.
G20 — AI Coach integration.
G21 — Profile/settings/subscription presentation.
G22 — Dark/light finalization.
G23 — Accessibility/responsive audit.
G24 — Performance audit.
G25 — Screenshot regression and final polish.

Каждый gate требует отдельного GO после предыдущего report, если scope или
риски изменились.

---

## 32. Gate Report Format

После каждого gate:
1. Goal.
2. Files read.
3. Files changed.
4. Behaviour preserved.
5. Behaviour changed.
6. Data/schema impact.
7. Privacy impact.
8. Risks.
9. Tests added.
10. Tests run/results.
11. flutter analyze.
12. Screenshot comparison.
13. Remaining issues.
14. Commit SHA.
15. Push status.

Не писать «всё работает» без evidence.

---

## 33. Git Discipline

Перед каждым gate:
- status;
- branch;
- upstream;
- unpushed commits;
- concurrent changes.

Stage только scoped files.
Не трогать unrelated untracked files.

Один gate — один локальный commit.
После commit — STOP.

Push только по отдельному push-GO.
Это правило имеет приоритет над auto-push instructions.

---

## 34. Prohibitions

Запрещено:
- переписывать приложение с нуля;
- менять Riverpod/router без необходимости;
- менять backend/ML/billing contracts без GO;
- удалять functions;
- fake confidence/recovery/body analysis;
- public progress-photo URLs;
- hardcoded English;
- random styles;
- giant widgets;
- heavy scrolling blur;
- silent scope expansion;
- push without push-GO.

---

## 35. Definition of Done

Рефактор завершён только когда:

1. Home goal-driven.
2. Scanner — заметное преимущество.
3. Onboarding показывает реальную ценность до account/paywall.
4. BodyMetricPicker и calculations корректны и честны.
5. Workout logging и rest timer надёжны.
6. Technique Coach has audited quality gates, aligned overlay, deterministic rep counting, gated cues and never evaluates invalid frames.
7. Equipment uses licensed posters.
8. Progress uses real data.
9. Progress Photos private, deletable, comparable and safely exportable.
10. AI contextual.
11. All states implemented.
12. Light/dark match Figma.
13. Android/iOS safe areas and behaviour work.
14. Accessibility passed.
15. Regression tests green.
16. No new analyze issues.
17. Screenshots match approved design.
18. Performance not worse.
19. Each gate has scoped commit.
20. Nothing pushed without push-GO.

Начни только с G0 — read-only audit.
После G0 выдай detailed plan и STOP без изменений.

---

# UPDATE v1.3 — Decision Governance and Architecture Locks

## Decision Register

Перед implementation gates используй отдельный decision register с 44 вопросами.

Для каждого вопроса храни:
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
- affected files/features;
- required-before gate;
- decision date.

Не считать Figma ResearchScreen production requirement. Он является internal design governance artifact.

## Corrected totals

- Completed-gate debt (D1–D5 + D7): 22
- D6 blockers/questions: 8
- Future D8–D9 questions: 14
- Total: 44

Не использовать неверную разбивку 26 / 8 / 10.

## Architecture locks

### Mobile stack

Stack уже определён:
- Flutter / Dart;
- Riverpod;
- go_router;
- feature-first architecture.

Q39 закрыт как `LOCKED: Flutter`.

Запрещено:
- начинать React Native rewrite;
- создавать parallel native app;
- использовать React Native как вариант Form Check implementation.

### Form Check wording

Q19 должен звучать:
`Реальный on-device ML в текущем Flutter stack или demo/prototype mode?`

Перед решением аудировать существующие:
- ML Kit / MediaPipe / pose detector;
- TFLite capabilities;
- classifiers;
- camera pipeline;
- supported exercise rules.

## Duplicate decisions

Q1 и Q41 — один decision по Light Theme.
Не реализовывать два независимых решения.

Связать их одним ADR / Product Decision Record.

## Platform health integration

Q4 не реализовывать как fake iOS “скоро” card без отдельного Product GO.

Сначала определить:
- Android integration scope;
- отдельный iOS health integration scope;
- platform capability visibility;
- no dead CTA.

## Gate blocking policy

### Hard blockers for D6
- Q19 ML scope;
- Q20 supported exercises;
- Q21 angle matrix;
- Q23 TTS strategy;
- Q26 Workout Summary integration route.

### Provisional defaults allowed
До решения Product можно использовать только документированные provisional defaults:
- Q22: session summary metadata only; no video/frame persistence;
- Q24: app/system locale;
- Q25: human-readable reliability state, no raw confidence percentage.

Каждый provisional default должен:
- быть записан в decision register;
- иметь owner;
- иметь expiry / required review gate;
- не считаться финальным решением.

## No silent implementation from open questions

Агент не должен выбирать option A/B/C молча.

Если вопрос marked Blocker:
- STOP;
- показать impact;
- предложить recommendation;
- ждать Product/Tech GO.

Если вопрос future/non-blocking:
- использовать existing behavior;
- не расширять scope;
- записать deferred decision.

## Decision evidence in gate reports

Каждый gate report должен включать:
- Decision IDs consumed;
- Decisions still open;
- Provisional defaults used;
- Architecture locks respected;
- New questions discovered.

Новые вопросы добавлять с новым ID, не перезаписывая существующие 1–44.

---

# FIGMA MAKE HANDOFF INGESTION PROTOCOL — v1.6

До Gate 0 разработчик должен получить единый handoff package.

## Required inputs

1. Figma file link с view/Dev Mode access.
2. Approved page/section и release version.
3. Prototype link.
4. Focus links на ключевые Ready for development sections.
5. Exported Figma variables JSON.
6. Export-ready SVG/PNG/JPG assets.
7. PNG/PDF reference screens.
8. Screen-to-code mapping.
9. Open Decisions Register.
10. Approved Figma prompt/version.

Не начинать implementation, если получены только screenshots без states,
tokens и behaviour annotations.

## Preferred access path

Если доступен Figma Dev Mode, Figma for VS Code или Figma MCP:

- инспектируй исходные frames напрямую;
- используй spacing, variables, component variants и annotations;
- не копируй сгенерированный CSS в Flutter;
- вручную маппируй semantic variables на существующие Flutter theme tokens;
- экспортируй только настоящие assets.

Если прямого доступа к Figma нет:

- используй exported package;
- явно перечисли, какие детали нельзя подтвердить;
- не угадывай размеры, states или interaction behaviour;
- запроси недостающие exact specs до implementation.

## Gate 0 additions

В Gate 0 создай:

`core/plans/FIGMA_HANDOFF_AUDIT_<DATE>.md`

В отчёте укажи:

- Figma version;
- список полученных файлов;
- какие links открываются;
- какие variables доступны;
- какие assets доступны;
- missing states;
- conflicts с repository;
- screen → route/provider mapping;
- open blockers;
- recommended gate sequence.

STOP после аудита.

## Asset rules

- SVG для icons/vectors;
- PNG/JPG для raster assets;
- не использовать screenshots как production UI;
- не добавлять текстовые labels в image assets;
- не дублировать media, уже присутствующие в repository;
- проверить лицензии и privacy;
- использовать stable names;
- оптимизировать assets без визуальной деградации.

## Token rules

- Figma variables — design source;
- Flutter semantic theme — code source;
- создать явную mapping table;
- raw hex/spacing values не размножать по feature widgets;
- при конфликте остановиться и вынести решение.

## Verification rules

Для каждого implemented screen:

1. Использовать реальный viewport.
2. Сделать emulator/device screenshot.
3. Сравнить с Figma reference.
4. Зафиксировать отклонения.
5. Проверить light/dark, RU/EN, large text и states.
6. Не обновлять golden автоматически без review.

---

# v1.6 — Incomplete Figma Make Prototype Policy

Do not stop solely because the Figma prototype is not wired end-to-end.
Use approved screens, tokens, specifications and existing repository behaviour.

Before implementing any listed gap, verify whether the feature already exists
in code. Preserve working business logic and restyle/integrate it rather than
rebuilding it.

See:
Полный оставшийся scope встроен ниже в этот же файл; внешние prompt-файлы не требуются.


---

# REMAINING IMPLEMENTATION SCOPE — EMBEDDED v1.6

Figma Make prototype может быть не полностью соединён и не обязан содержать
все error/offline/platform states. Это не блокирует implementation, если уже
есть утверждённые visual patterns и repository содержит реальную логику.

Перед каждым пунктом сначала проверь фактическое состояние текущего branch.
Не считать отсутствие frame в Figma доказательством отсутствия функции в коде.
Не считать наличие demo-frame в Figma доказательством наличия backend/ML/data.

## R0 — Figma Make and Repository Mapping Audit

До изменений подготовь:

`core/plans/FIGMA_MAKE_REFACTOR_AUDIT_<DATE>.md`

Отчёт должен содержать:

1. Branch, HEAD, upstream, status, unpushed, untracked.
2. Доступность точной Figma Make ссылки.
3. Полный список найденных screens и states.
4. Полный список переходов, которые реально работают в prototype.
5. Mapping:
   `Figma screen → Flutter route → page/widget → provider → repository/service`.
6. Classification для каждого элемента:
   - already implemented and visually aligned;
   - implemented, needs visual refactor;
   - implemented only in code;
   - represented only in Figma;
   - missing in both;
   - blocked by decision;
   - blocked by unavailable asset/data/backend.
7. Existing design tokens/components suitable for reuse.
8. Missing Figma states that dev can safely derive from the design system.
9. Privacy, ML, storage, billing и schema risks.
10. Exact R1–R9 plan with files and tests.

После отчёта STOP. Никаких изменений, commit или push.

## R1 — Home completion

Проверь и при необходимости реализуй:

- weekly calendar;
- milestones block;
- recovery horizontal scroll;
- visible affordance, что список прокручивается;
- корректное partial-card reveal или другой ненавязчивый scroll cue;
- loading, empty, error и offline states;
- safe areas;
- responsive widths;
- сохранение приоритетов Home:
  1. Today Workout;
  2. Scan;
  3. weekly progress/recovery;
  4. milestones и secondary content.

Не создавать новый visual language. Использовать approved Home и текущие
semantic components.

## R2 — Scanner and Equipment completion

Проверить и сохранить существующие capabilities, затем привести UI к Figma:

- scan history;
- saved machine cards / My Machines;
- camera permission flow;
- analyzing/result/retry;
- unknown equipment flow;
- offline/on-device fallback;
- network failure;
- low-confidence result;
- manual search fallback, если он утверждён и поддерживается;
- navigation Scan → Equipment;
- contextual AI Coach entry;
- не подменять unknown machine ближайшим неверным результатом.

Если cloud recognition и local fallback уже существуют, не создавать второй
pipeline и не менять ML architecture без отдельного GO.

## R3 — Dedicated Exercise Page

Exercise Page является обязательным отдельным экраном, а не частью Equipment
или Workout Player.

Если route отсутствует, добавь отдельный route с устойчивым exercise ID.

Экран должен использовать реальные catalog/media/history данные и включать:

- licensed anatomical animation или poster fallback;
- название;
- equipment;
- level;
- primary и secondary muscles;
- suitability/personalisation explanation;
- краткие шаги техники;
- полную инструкцию;
- common mistakes;
- restrictions/contraindications только из реальных данных;
- personal history;
- last performance;
- personal record, если вычисляется честно;
- Start Exercise;
- Add to Workout;
- TechCoach;
- AI Coach;
- loading;
- media unavailable;
- no history;
- unsupported/restricted state;
- long RU/EN content;
- accessibility.

Не копировать workout logging/business state в Exercise Page. Она должна
передавать контекст в Workout Player.

## R4 — TechCoach entry and context

Сохранить существующий `/form-check` и реальный on-device pose pipeline, если
они подтверждены аудитом.

Добавить входы:

- Exercise Page → TechCoach;
- Workout Player → TechCoach;
- optional Workout Summary → retry TechCoach only if supported.

Передавать explicit context:

- exerciseId;
- exercise name;
- supported classifier/rule set;
- required camera angle;
- workout/session ID when applicable;
- target reps when applicable;
- language and voice preference.

Не показывать debug coordinates, raw landmark IDs или internal confidence dump.
Не сохранять кадры/видео по умолчанию.

## R5 — WorkoutDone / WorkoutSummary consolidation

Q26 должен быть решён до destructive mutation.

Рекомендуемое решение:

- `WorkoutSummary` — единственный канонический итоговый экран;
- существующая полезная логика `WorkoutDone` переносится или переиспользуется;
- старый экран временно остаётся thin compatibility wrapper только при
  необходимости безопасной миграции;
- один persisted completion path;
- один analytics event family;
- один navigation destination.

Если operator не подтвердил Q26, подготовь exact migration plan и STOP перед
изменением маршрутов.

## R6 — Rest Timer wiring

Если Rest Timer определён как Screen/state, но не имеет реального входа:

`Complete Set → Persist Set → Rest Timer → Ready/Skip/+Time → Next Set`

Требования:

- один authoritative timer state;
- no duplicate clocks;
- background/foreground lifecycle;
- восстановление после app pause;
- sound/haptic согласно settings;
- `Skip`, `+30 sec`, pause/resume, next-set transition;
- timer не должен терять уже сохранённый set;
- unit/widget/integration tests.

## R7 — Real Progress charts

Заменить placeholders реальными data-backed визуализациями:

### Strength progression
- выбранное упражнение;
- period selector;
- line chart по честной метрике, например best weight или estimated 1RM только
  если formula уже утверждена;
- insufficient-data state.

### Volume
- weekly bars;
- volume formula должна совпадать с workout domain;
- no fabricated values.

### Consistency
- weekly/monthly workout frequency;
- calendar или bars согласно ближайшему approved pattern;
- timezone-safe dates.

### Muscle load
- anatomical map только если muscle mapping достоверный;
- иначе ranked bars по агрегированным muscle groups;
- явно обозначить, что это training distribution, а не медицинская оценка.

Обязательно:

- loading/empty/error/offline;
- range selector;
- accessibility summary;
- large text;
- screenshot review.

## R8 — AI Coach contextual integration

Переиспользовать существующий AI Coach UI/service/cache.
Не создавать второй chat backend.

Добавить или проверить contextual entries:

- Scan Result;
- Equipment;
- Exercise Page;
- Recovery;
- Workout Summary.

Передавать структурированный context, не только длинную строку:

- source screen;
- equipment/exercise;
- active workout state;
- relevant history/recovery data с privacy constraints;
- locale.

AI Coach не должен придумывать недоступные sensor, medical или body-analysis
данные.

## R9 — Theme, platform, accessibility, offline and E2E

### Light theme

Если Figma Make не содержит полный light theme:

- построить semantic light palette на основе утверждённых brand tokens;
- не инвертировать цвета механически;
- проверить Home, Scanner, Exercise, Workout Player, Progress и dialogs;
- предоставить screenshots до массового rollout;
- dark theme сохранить без regression.

### Android/iOS

- SafeArea и system bars;
- Android predictive back;
- iOS swipe-back where appropriate;
- keyboard insets;
- camera lifecycle;
- permission wording/flows;
- native date/time/picker behaviour where appropriate;
- no device-specific clipped content.

### Accessibility

- touch targets не меньше 48 logical px, где применимо;
- Semantics labels;
- logical focus order;
- status не только цветом;
- text scale 1.0/1.3/1.6/2.0;
- reduced motion;
- screen-reader friendly summaries для charts;
- accessible camera controls и timers.

### Offline

Минимум проверить:

- Home cached/limited state;
- Scanner local fallback;
- Workout Player and set logging;
- Rest Timer;
- Progress cached/empty state;
- retry and sync status.

### End-to-end wiring

Реализовать настоящий happy path независимо от неполного prototype wiring:

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
→ TechCoach
→ Workout Summary
→ Progress
→ Progress Photos.

Не должно остаться dead routes, dead CTA или Screen enum без navigation.

---

# PROVISIONAL DECISIONS FOR PLANNING

Эти defaults можно использовать для planning и non-destructive UI, но отмечать
как provisional, пока operator не утвердил окончательно:

- Flutter/Riverpod/go_router остаются locked.
- Figma Make code не переносится в production.
- Existing ML pipeline переиспользуется.
- TechCoach raw confidence percentage не показывается пользователю; показывать
  human-readable reliability states.
- TechCoach history хранит только summary metadata, без кадров/видео, пока не
  утверждена другая privacy policy.
- Voice cues следуют языку приложения/системы и используют existing on-device
  TTS, если audit подтверждает готовую реализацию.
- Progress Photos private by default.
- Different photo angles: warning, не silent comparison.
- Light theme не блокирует первые dark-theme implementation gates.
- WorkoutSummary consolidation требует operator confirmation перед mutation.

---

# REQUIRED TEST MATRIX FOR REMAINING SCOPE

## Unit

- calculations and aggregations;
- progress chart series;
- timer state/lifecycle;
- route/context parsing;
- exercise history mapping;
- AI context builder;
- theme token mapping where pure;
- offline/sync state transitions.

## Widget

- Home calendar/milestones/recovery scroll;
- scanner saved/unknown/offline states;
- Exercise Page loaded/loading/no-history/media-error/restriction;
- TechCoach entry visibility and unsupported state;
- Rest Timer controls;
- canonical Workout Summary;
- each progress chart state;
- AI Coach contextual CTA;
- light/dark and large text;
- Semantics for controls and charts.

## Integration

- Scan → Equipment → Exercise;
- Exercise → Workout;
- Exercise → TechCoach;
- Workout set → Rest Timer → next set;
- Workout completion → one Summary;
- Summary → Progress;
- offline workout logging and later sync;
- app restart restores appropriate state;
- actual camera/ML smoke test on hardware.

## Visual

- emulator/device screenshot per key screen;
- compare with Figma Make/reference;
- document intentional deviations;
- Android and iOS representative viewports;
- RU/EN;
- dark/light;
- large text.

---

# EXECUTION ORDER

1. R0 audit only → report → STOP.
2. После audit-GO — Design System/token gate, если нужен.
3. R1 Home.
4. R2 Scanner/Equipment.
5. R3 Exercise Page.
6. R4 TechCoach entries.
7. R5 Summary consolidation только после Q26 decision.
8. R6 Rest Timer wiring.
9. R7 Progress charts.
10. R8 AI Coach contexts.
11. R9 theme/platform/accessibility/offline/E2E.
12. Final regression and handoff.

Не объединять всё в один giant commit.

После каждого implementation gate:

- scoped diff review;
- targeted tests;
- broader regression tests;
- `flutter analyze`;
- real emulator/device screenshot;
- update audit/state docs;
- один локальный commit;
- STOP;
- push только по отдельному push-GO.

---

# FIRST MESSAGE / REQUIRED RESPONSE FROM DEV AGENT

Начни только с R0 / Gate 0 read-only audit.

В первом ответе предоставь:

1. Git baseline.
2. Доступна ли точная Figma Make ссылка.
3. Какие screens/states/transitions реально видны.
4. Repository feature inventory.
5. Screen-to-code mapping.
6. Figma vs code gap classification.
7. Decisions/blockers.
8. Gate plan с файлами и тестами.
9. Риски.
10. Явный `STOP — no files modified`.

Не изменяй файлы, не создавай commit и не делай push до отдельного GO.
