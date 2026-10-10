# Fitness App — Redesign Remainder, August 12 Checkpoint (English Translation)

**Original:** [Redesign remainder state](PLAN_REDESIGN_REMAINDER_2026-08-12.md), source blob `6627b604530d81cec2a6e6f54a90d551e965bf61`.  
**Historical date:** August 12, 2026.  
**Purpose:** Persist expensive code/prototype reconnaissance across chat-session boundaries under the "Audit / Review Findings Persistence" rule. This is a **delta to** `PLAN_R11_FIGMA_PARITY_REBUILD_2026-08-08.md`, not a new master design plan.

The original operator had historically authorized autonomous work over **F3, bug 5, bug 6, R11f/R11h/R11b**, with the paywall still **HELD pending prices**. That dated GO, like every permission recorded here, is **not reissued** by this translation.

## Done and committed — source checkpoint

| Sub-gate | Outcome | Source commit |
| --- | --- | --- |
| D1 / bug 5 | Right-most chip in a program-card header no longer clipped | `725c215` |
| D2 / bug 6 | Program-card gradient derived consistently from goal color, not card index | `725c215` |
| R11h | Camera opened on an explicit tap, not on page arrival; two preparation screens; **24 tests** | `59d5257` |
| C1 | Front/rear camera switching for Form Coach, Posture and photo capture | See detailed section |
| R11f-1..3 | Split capture/save; image preview/retake; metadata persisted | See detailed section |

Checks reported at the last historical commit: `flutter analyze` **7 pre-existing issues, 0 new**; `flutter test` **1,981 PASS, 0 failed**; `audit_doc_links.ps1` **PASS, 0 broken among 789 checked**.

**R11h was not fully finished:** `active` / `paused` / `summary` still needed integration with the actual repetition state machine. `calibration` remained outside transitions because the app lacked an independently validated "detector stabilized" signal.

## Resolved investigation obstacle — prototype source can be inspected without Vite

`docs/Redisign/reference/prototype/README.md:62-65` had implied the prototype must run locally to inspect eight screens absent from still frames. The source corrected that premise: the provided ZIP could be extracted and its `src/App.tsx` (**5,471 lines**) read directly, which the README itself described as a more precise reference than screenshots.

Historical extraction example:

```bash
unzip -o "docs/Redisign/Review Existing Examples (Copy).zip" -d <scratch>/proto
# <scratch>/proto/src/App.tsx
```

The source mapped prototype screen entry points:

| Prototype | Source line |
| --- | ---: |
| `OnboardingFlow` — 13 view states with 9-step progress | 2379 |
| `HomeScreen` | 2441 |
| `ScanScreen` | 2555 |
| `ExerciseScreen` | 2781 |
| `EquipmentScreen` | 3009 |
| `WorkoutPlayer` | 3162 |
| `ProgressPhotoModule` — nine states | 3909 |
| `ProgressScreen` | 3944 |
| `TechCoachScreen` — eight phases | 4220 |
| `WorkoutsScreen` | 4735 |
| `ProfileScreen` | 4916 |
| `PaywallScreen` | 4984 |

This is a historical source-line map, not a certification those references still match the latest design.

## Work left unfinished and why

### R11h — one state machine, not four independent display phases

The source found `coachPhaseControllerProvider` was **never consumed by production**: a search for it under `lib/` found only its own provider file. `start()`, `pause()`, `resume()`, `finish()` and `restart()` existed as **unwired methods**; `form_check_page.dart` consumed only `CoachReadinessBand` for detector verdict, not `CoachPhase` for operator-triggered transitions.

Thus a "Pause" button without correct initial Start semantics would **lie** if the rep counter continued counting. Real pause must gate the underlying repetition calculation, not only update the page.

The prototype's setup ended with **"Ready — turn on camera"** (`App.tsx:4562`). Its privacy description (`App.tsx:4558`) said the camera was used only during this session. Showing that setup screen **after** the camera was already running would be deceptive.

The real gate needed **a changed camera-start boundary + two setup screens + updates to nine tests** in `test/features/form_check/start_lifecycle_test.dart` (323 lines) that assumed the camera opened on arrival. Deferring camera permission to a user tap was a deliberate privacy improvement.

Entry points: `form_check_page.dart:112` (`_startDetector(requestPermission: true)` in `initState`) and `:172` for resumed lifecycle behavior. Prevent unexpected camera restart during launch/preparation.

### C1 — switch between front and rear cameras

The operator had asked for camera switching at least to permit posture analysis using a mirror.

At the snapshot, Form Coach and Posture defaulted to the **front** camera (`mlkit_pose_detector_service.dart:26`); Progress Photo capture defaulted to the **rear** (`progress_photos_providers.dart:107`). `facing` was `final` and only read once in `_open()`.

This was functional, not cosmetic: shoulder tilt, pelvic tilt and forward-head metrics required whole-body geometry (`posture_metrics.dart:20-80`). A phone held at selfie distance poorly framed head-to-feet; a stationary device viewed via a mirror could address positioning and visibility.

Source implementation model:

- Make `facing` mutable; `setFacing()` must reopen the camera since `CameraController` is bound to one physical lens for its lifetime.
- Publish **actually opened** lens through `activeFacing` / `ValueListenable`, not merely the requested lens. A phone without the requested lens may fail at `cameras.first`; the UI should not claim a successful switch.
- The first attempt to add concrete members to abstract `PoseDetectorService` falsely assumed test doubles would inherit their method implementations. They used Dart `implements`, requiring every member to be implemented. Fix used `NoCameraControls` mixin applied to fakes.
- Two actual test-discovered defects: `_applyFacing` read private `_running` instead of overridable `isRunning`, breaking reopen for subclasses; and failed switching left UI claiming a nonexistent lens and made subsequent taps no-op. A rollback/reconciliation rule corrected that state.

**Unverified:** Live camera-preview mirroring and skeleton overlay alignment had not been checked on any lens/real device; `_toInputImage` read `sensorOrientation` for the selected lens (`camera_session.dart:373-375`), but the display transformation still needed actual verification.

### R11f — completed capture/preview/metadata separation

The change was not merely a new optional parameter. New contract:

- `takeShot()` returns pixel bytes and **does not persist**.
- `save(bytes, {angle, weightKg, note})` encrypts and stores bytes and metadata **after** user preview.
- Two prototype stages — preview/retake, then metadata — sit between capture and persistence.

A failure found during implementation: the old code called `capture()` **after** closing the photo bottom sheet, whose `dispose()` stopped the camera. That was already a shutter-versus-camera-stop race. Inserting a preview between closing the camera and saving would have made the gap seconds long, allowing `awaitReady()` to return null, indistinguishable from "user cancelled".

Moving the **shutter action inside the still-open camera sheet** addressed the ordering.

Another failure: `capture()` put failures in a provider's `AsyncValue` that **nobody observed** (only `.notifier` consumers found). Camera errors appeared as dead buttons. Revised behavior both records/throws failure so the sheet can display an error; save errors are shown via the page snackbar.

The historical `test/features/progress_photos/capture_flow_test.dart` covered the **entire order**: capture → preview → retake back to camera (not timeline) → metadata → persistence, not isolated screens that could accidentally pass out of order.

**No real-device verification was claimed for this entire R11 series at the checkpoint.**

### R11f — intentionally NOT implemented or separately governed

**Privacy gate:** Not built. The app already showed a persistent `_PrivacyStrip` every time (`progress_photos_page.dart`), while the Figma one-off explanatory card was weaker. Replacing the persistent promise with a once-only note could weaken privacy. A meaningful **consent** gate (camera unavailable until accepted) was a separate Product decision, not a mere layout task.

**Export:** Not built, because it contradicted the recorded source at `local_progress_photos_repository.dart:68-72`: "photos don't leave the phone". Sending a decrypted JPEG to an OS share sheet would violate that value statement. **Do not interpret the prototype Export frame as owner consent to enable export.**

**Reminder:** Belongs to `core/notifications/notification_service.dart`, separate from the shutter/save transaction. Decisions and later work are described in [R11 decisions companion](PLAN_R11_DECISIONS_2026-08-12.en.md).

### R11f — original investigation preserved

The original `photo_store.put()` accepted `weightKg`, `bodyFatPercent` and `note` (`photo_store.dart:61-63`), stored them (`:144-146`), and read them back (`:158-160`), while its one caller at `local_progress_photos_repository.dart:97` did **not pass them**. The storage capability existed, but the UI flow failed to persist the metadata. This also explained why R11g comparison rarely had a meaningful weight delta.

Affected interface path at first reconnaissance:

`ProgressPhotosRepository.capture()` in `state/progress_photos_providers.dart:24` → `local_progress_photos_repository.dart:92` → demo implementation `:41` → **five test fakes** (`data_export_providers_test.dart:254`, `progress_page_test.dart:38`, `photo_paging_test.dart:49,82` and `progress_photos_demo_banner_test.dart:22`).

Since the fakes use `implements`, adding even an optional method parameter requires fixing all implementations. It was **not** safely just "add one optional argument".

The next source correction explicitly distinguished those interface-call sites from the much wider UI flow: prototype `ProgressPhotoModule:3909` required **shutter → preview → retake/save → metadata → final persistence**. Existing `capture()` combined shutter and save, so the meaningful implementation required splitting into two operations.

An alternative shortcut — request weight/note *before* the photo — would save screens but worsen UX and prevent proper retake. If chosen it would need an explicit recorded Product decision, not silent scope drift.

### R11b — largest remaining gate

The prototype had **13 UI screens/states** (`Step0` to `Step13`, `OnboardingFlow:2379`) while the progress bar counted **nine** (`TOTAL_OB_STEPS = 9`, `App.tsx:1202`). Initial/final steps were deliberately outside progress count.

Missing/shared widgets by source line:

- `WheelYear:1635`
- `HRuler:1723`
- `VRuler:1860`
- `BodyDiagram:1443`
- `ChoiceCard:1218`
- `BMICard:1962`
- `DeltaCard:1997`

The year picker was blocked on a data-model mismatch: profile stored `age`, not birth year. The subsequent O-series decision history must be read before starting any current version of R11b.

### F3 — only after R11 sub-gates

The formal reference listed eleven screens, but R11a/R11c/R11d/R11g/R11i already changed most. Actual F3 remainder should be **per-screen comparison with App.tsx** for screens R11 did not touch, **after** R11f/R11h/R11b. Doing it earlier would duplicate effort.

## Global acceptance weakness for the R11 series

**No screen in the R11 series had been opened on a real device at this checkpoint.** The series and two defects were closed by `flutter analyze` + `flutter test` only. This was the source's most significant evidentiary weakness: **passing tests without real-device visual/interaction confirmation is insufficient for a UI refactor**.

**Paywall remained HELD:** Price tiers and trial duration were monetary decisions owned by the operator, not merely UI details.

## Translation / original-authority limitations

This English companion retains the source's chronological implemented/not implemented split, source-code proof/line references, **1,981 Flutter tests** and **789 documentation-link audit**, device-test absence, consent/export/product decision restrictions and historically quoted multi-gate GO. The original reports and exact Russian operator words remain unchanged.

No phone, image, app, browser, Flutter test suite, source file, Firebase, Stripe, consent flow, historical report or deployment action was changed by this translation.

**Disposition: SOURCE-BOUND HISTORICAL REDESIGN REMAINDER IN ENGLISH; independent semantic parity and current-run confirmation pending.**
