# Change record: data-driven live-coach engine and eight new exercises (beta)

## What changed
- Registry (`mobile/assets/data/coach_exercises.json`, schema `coach_exercises/v1`; `form_check/data/coach_spec.dart`, `coach_registry.dart`): an exercise is a row with its view, counting signal (falling/rising, enter/exit thresholds, optional hold mode), per-rule alignment checks, cue ids, `provenance` (measured, experimentally confirmed or authored) and an `advisory` flag. The loader validates ranges, names and cue ids; authored rows must be advisory and beta.
- Engine: `generic_rule_classifier.dart` evaluates a registry row through the existing `FormClassifier` interface; `coach_signal.dart` supplies the signal metrics; `hold_counter.dart` times hold exercises (plank, glute bridge) while the pose stays in band; `registry_cue_text.dart` resolves cue ids to localized text (`formcheckRegistry*` keys, ru and en). `FormFeedback` gained a `cueId`; the legacy exercises and their classifiers are unchanged and a parity test pins the shared behaviour.
- Eight new exercises: bent-over row, lateral raise, plank, glute bridge, pull-up, step-up, tricep dip, good morning. All thresholds are authored from standard biomechanics in 2D image space (tolerance 12 degrees unless stated). Cues for tricep dip and good morning use neutral wording and make no injury or back claims. Calf raise is excluded: there are no heel or toe landmarks and the ankle-rise proxy is below pose-model jitter.
- UI: `form_check_page.dart` picker scrolls with a pinned Start bar (the file was reformatted with `dart format`, hence the large diff); `widgets/coach_beta_badge.dart` marks registry exercises as beta.
- Debug-only harness (`form_check/debug/coach_recorder.dart`, available in debug and profile builds only): records pose sequences to `<docs>/coach_recordings/<uid>/` for the ship gate; the account wipe removes the directory.
- `core/plans/COACH_ENGINE_SHIP_GATE_2026-10-13.md`: the gate for promoting an exercise from beta/advisory to spoken or faulting.

## Authored versus measured
Authored rows ship on-screen only: no speech, no rep failure, no claim that technique is correct, rep counts hidden until the measured holdout reaches 80 percent, and a visible beta badge. Promotion needs recorded real sets with consent: at least 20 sets per exercise across at least 3 camera heights and 3 people, split into good and deliberately faulty reps, fault margin above twice the tolerance, at most 5 percent false positives on good reps. When required landmarks are missing the engine gives no assessment (the pose gate asks the user to reposition).

## Not expressible per frame (omitted rather than shipped as noisy cues)
Completion cues need rep phase: pull-up "full hang", step-up "stand fully", the bent-over-row lower hip bound. Spine and hyperextension stay unscored.

## Why
Operator task: finish the live coach for all common exercises on one data-driven engine, using the angle measurements already in the repository, without presenting unmeasured thresholds as verified technique.

## Affected contracts and paths
`FormExercise` gained values for the new exercises (exhaustive switches updated); `formCoachTeaches` accepts "registry row present". New l10n keys `formcheckRegistry*` and `formcheckBeta*` in both languages.

## Verification state
Synthetic-frame tests only (good, faulty, partial visibility, noisy landmarks, hold timing, registry content and cue completeness, recorder gating and wipe, picker layout): `test/features/form_check` passes except the golden files, which fail on this host for font and rendering reasons as before the sprint. No recorded real sets exist, so no threshold is measured; camera height, lighting and landmark quality on real devices are unverified.
