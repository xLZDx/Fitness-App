# Fitness App — O-Series Resume Checkpoint (English Translation)

**Original:** [O-series resume state](RESUME_O_SERIES_2026-08-12.md), exact Git blob `e8e3da56dadda1368d12603b168e7518ef733208`.  
**Historical checkpoint:** **August 12, 2026**.  
**Original operator scope:** The owner had authorized O3–O10, P3, P4-lite, compile SDK **35→36**, upperBack catalogue tagging, and splitting debug/release `applicationId`. The source made **additional explicit approval boundaries** for sensitive/signing work. This translation does not reissue the GO or authorize present-day runtime changes.

## Three plan conflicts resolved before the then-current work

1. **O9 / Health Connect was SKIPPED.** The operator specifically said to **remove it from onboarding entirely**, reserving multiple-device health integrations for a future **separate gate**. O2 had already removed the step. The existing `HealthService` architectural seam remained intact. **Do not accidentally restore an onboarding step contrary to the owner decision.**
2. **P3 was not a standalone gate.** `PLAN_R11_DECISIONS_2026-08-12.md:253` said O8 includes the year-of-birth wheel on the **About You** screen. A separate P3 would duplicate work.
3. **Hard-coded N/9 onboarding progress was obsolete.** The updated operator choices shortened the flow; compute progress from `kOnboardingOrder.length` rather than printing a constant.

## Done and committed at the checkpoint

### O3 — Combined Goal and Level

- Extended `ProgrammeGoal` with `endurance` as a sixth value (`programme.dart:30`).
- Extended `FitnessTier` with `never` as the first option (`profile_models.dart`).
- Added `FitnessGoals.primary` as `ProgrammeGoal?` for the single primary goal; retained six existing booleans because a user may principally seek strength while also wishing to lose weight.
- Introduced real `ChoiceCard` (`inputs.dart`) when the first consumer was ready, rather than building it prematurely in O1.
- Replaced `OnboardingStep.goals` and `.level` with `.goalAndLevel`; removed old `step_goals.dart` / `step_level.dart` instead of leaving dead code.
- Completed the affected exhaustive switches: `_goalHue` / `_goalLabel` (`workouts_page.dart`), `_tierRank` (`exercise_filter.dart`), `planFor` (`set_timer_providers.dart`), and added `AppPalette.programmeEndurance`.

### O4 — Location and Equipment

- Introduced `TrainingLocation {gym, home, outdoor, mixed}` and the eight-valued `EquipmentKind` including `cameraScan` (**user intention, not physical equipment**; exercise recommendations must ignore it).
- Made `EquipmentAccess.hasGymAccess` a **calculated** field from `location`, but retained a private `_storedGymAccess` for profiles created before O4.
- The source called that backwards compatibility the **principal risk of the gate**, covered by **11 tests** in `test/features/onboarding/equipment_access_test.dart`. Without the old-field fallback, existing users could be silently treated as "question unanswered" without a crash or a red test.
- Updated Firestore read/write and wrote the **computed `hasGymAccess`** for old consumers rather than stale data.

All of these are past source-reported implementation outcomes, **not independently rerun tests**.

## Remaining work, in original sequence

### O5 — Schedule (NEW screen and largest new data field group)

The planned `TrainingSchedule` structure was inherited from `O0_ONBOARDING_SCHEMA_2026-08-12.md` `5:

```dart
class TrainingSchedule {
  final int? daysPerWeek;            // 2..6
  final int? sessionMinutes;         // 30 / 45 / 60 / 75 / 90
  final List<int> preferredWeekdays; // DateTime.monday..sunday
}
// Add UserProfile.schedule
```

**Never reuse `FitnessLevel.frequencyPerWeek`**: it measures training **today**, not intended frequency. Combining the two destroys the actual baseline for planning workload. Calculate `MotivationPrefs.preferredDuration` compatibly from `sessionMinutes`.

Implement after `equipment` in `kOnboardingOrder`, with `OnboardingStep.schedule`, page, `isOnboardingStepAnswered`, `_titleFor`, `_widgetFor`, l10n, Firestore serialization and tests.

### O6 — Body (largest UI scope)

Tabs **Limitations ↔ Priorities**, anatomical selector, two chip groups, and a collapsible **Additional Information** section containing the existing Health step's content **without changing its existing behavior**. The owner had said the original health screen was useful; the plan moved it under disclosure rather than rewriting or deleting free text.

`FocusZone {chest, back, shoulders, arms, core, glutes, legs, fullBody}` must **not** be merged with `InjuryRegion`. A muscle group to **train** is not the same as an injury area to **avoid**.

### O7 — Barriers

`TrainingBarrier {exerciseChoice, machineUse, techniqueDoubt, time, consistency, discomfort, none}`, a multi-select partially replacing the prior Motivation step.

### O8 — About You plus P3

Add `PersonalInfo.birthYear` and a derived `age = current year − birthYear`; migrate old age at a single read point `firestore_profile_repository.dart`.

**Derived birth-year precision is only ±1 year** because birth month was never collected. Disclose approximation in the UI.

Provide birth-year wheel using `BodyMetricPicker` `9.1, height, current/target weight, gender and activity level.

### O9 — SKIPPED

As above, explicitly deleted from the onboarding sequence by operator decision; leave real integration for another gate.

### O10 — Actual generation, plan preview and account

**Not merely a layout issue.** Spec prohibited fake plan-generation progress and invented forecasts (`:382-383`) and required a **real generator** for Plan Preview (`:388`). Check whether a real generator exists before implementing a UI; absent one, flag an actual capability blocker rather than building a mock pretending to generate a plan.

### P4-lite — silent loss of injury notes

`step_health.dart:72` used `.where((s) => s.contains(':'))`, silently dropping text without a colon such as **"My knee hurts"**. The proposed correction was to store unparsed entries as injuries with an empty type instead of discarding them.

**Honest benefit limitation:** This did **not** improve real exercise safety at that checkpoint: `exercise_filter.dart` filtered **0 of 1,887** catalogue exercises due to the lack of contraindication tags. Saving user data is necessary for a future tagging system, **not proof the app became safer**.

### Compile SDK 35→36

`flutter_secure_storage` and `flutter_tts` required 36 while the app built against 35, with warnings and eventual distribution risk. Confirm SDK 36 is actually installed in the authorized environment before modifying compilation settings. The original device snapshot mentioned Android 16 on the S23.

### upperBack tagging

A ninth `upperBack` area had already been added in O1 but had **zero tagged exercises**. This was safe only because `coversAllOf` in `safety_coverage_providers.dart:58-61` refused to claim screening coverage when its class had none.

Actual tag remediation had four independent contract/checkpoint locations: **Dart enum, JSON projection, Dart test and Python test**. Do not add a false coverage claim merely to satisfy a UI checkbox.

### Debug/release `applicationId` separation — explicit signing GO

Both builds used `com.fitnessapp.fitness_app.sptr`. On August 12, the operator observed a debug installation on a Samsung S23 requiring removal of the release APK (`INSTALL_FAILED_VERSION_DOWNGRADE`, versionCode **14** vs **2360**), causing loss of the prior app's local data.

The same collision could disrupt Wear OS pairing, whose Gradle configuration lacked `signingConfig`.

**Critical source rule: signing/package changes require a separate explicit, named GO. Do not bundle with routine SDK or UI work.** The broad work-chain authorization must not be used to justify deleting a live build or its local data.

## Required checks — historical guidance only

- `flutter analyze` baseline: exactly **seven** known issues. Any eighth must be accounted for as a new regression.
- Full `flutter test` suite.
- `flutter test integration_test/app_test.dart -d <device>` only on an authorized actual device.
- Before every live phone test, the source instructed waking the screen because device E2E could hang indefinitely otherwise.

Illustrative command sequence from the original:

```bash
adb -s <dev> shell svc power stayon usb
adb -s <dev> shell input keyevent KEYCODE_WAKEUP
adb -s <dev> shell wm dismiss-keyguard
adb -s <dev> shell dumpsys power
```

After testing, restore `svc power stayon false`. Original exact phone serials and network address are preserved in the source but intentionally **not repeated here**. They are not needed for a document translation and must not be treated as currently connected devices.

## Source and authority limits

The original records **O3/O4 committed**, **O5–O8/O10 pending**, **O9 skipped**, P4-lite and SDK/tag work planned, and **debug/release package changes requiring separate signing GO**. It does not establish those tasks remain at the same status today. The historical GO, device actions and old installation risks do not become fresh approvals when translated.

The source retains the exact original Russian statements, IDs, code signatures and operator device evidence unchanged. No local phone, emulator, database, app, Firebase project, signed artifact, Git worktree or CI was touched.

**Disposition: SOURCE-LINKED HISTORICAL ENGLISH O-SERIES HANDOFF FOR REVIEW; NO APP BUILD, SIGNING CHANGE OR PUSH AUTHORIZED.**
