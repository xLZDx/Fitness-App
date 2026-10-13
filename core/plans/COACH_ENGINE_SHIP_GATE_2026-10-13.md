# Coach engine ship gate (2026-10-13)

Scope: the registry-driven coach engine (`mobile/assets/data/coach_exercises.json`, schema `coach_exercises/v1`) and the eight exercises added to it. This document says when an exercise may stop being beta, how to collect the evidence, and what the engine cannot see.

## Default state

Every registry row ships as `provenance.status = beta` and every rule as `advisory = true`. Consequences enforced by the engine:

- Cues are shown on screen only: never spoken, severity 0, never fail a rep.
- Rep counts are not shown for authored rows (counting withheld until the measured holdout is >= 80%).
- Hold exercises (plank, glute bridge) show a hold timer.
- The picker and the coaching screen show a neutral "Beta" badge and the line "Guidance is advisory while we calibrate; not medical advice." (en and ru).

Ranges are authored from standard biomechanics in 2D image space. No recorded sets back them yet.

## Exercises and provenance

| Exercise | View | Provenance kind | Status |
|---|---|---|---|
| bentOverRow | side | authored | beta |
| lateralRaise | front | authored | beta |
| plank | side | authored | beta |
| gluteBridge | side | authored | beta |
| pullUp | side | authored | beta |
| stepUp | side | authored | beta |
| tricepDip | side | authored (safetyWording) | beta |
| goodMorning | side | authored (safetyWording) | beta |

Calf raise is excluded: there are no heel or toe landmarks, and the ankle-rise proxy (about 3% of body height) is below ML Kit jitter, so any count or verdict would be fabricated. Squat and deadlift stay `canFault = false` in the legacy classifiers for the reasons recorded in `form_classifier.dart`.

## Promotion criteria (beta/advisory to spoken/faulting)

An exercise may be promoted only with recorded real sets, collected with the participants' consent, that meet all of:

1. At least 20 sets per exercise.
2. At least 3 camera heights and at least 3 different people across those sets.
3. Both good reps and deliberately faulty reps, labelled.
4. Fault margin greater than 2x the rule tolerance (the 5.2 degree class-overlap lesson: a rule whose faulty and good distributions overlap within tolerance must not fault).
5. False-positive rate on good reps at most 5%.

Promotion is a registry edit (`status`, per-rule `advisory`, provenance `kind`/`source` updated to the dataset) plus the evidence summary in the commit record. Partial promotion is allowed per rule: a rule that fails the margin or false-positive test stays advisory.

## Record-and-review harness

Available in debug and profile builds only (`coachHarnessEnabledProvider`, default `kDebugMode || kProfileMode`; tests override it to simulate release). It is not built in release.

1. Open the Form Coach, pick the exercise, press Start; the "DEV recorder" panel sits under the movement chips on the live screen. You must be signed in (files are stored per account).
2. Press Record, perform the set (label good vs faulty in your own notes and in the file name you export), press Stop.
3. Press Export to share the JSON file.

File: `<app documents>/coach_recordings/<uid>/<exercise>-<epochMs>.json`, schema `coach_recording/v1`. Per frame: time since the first frame (ms), angles in degrees at eight joints (left/right elbow, shoulder, hip, knee), rep phase, rep count, hold ms, gate verdict, and the engine's rule, severity, cue id and advisory flag. Decisions are read when the frame arrives and may lag that frame's own verdict by one frame. Recording stops at 20000 frames.

Privacy: no video, no images, no landmark coordinates, no name or uid inside the file. Stored locally only; sharing is the developer's explicit export. The account-deletion wipe removes `coach_recordings/<uid>/`.

Evaluation: replay the angle series against the rule thresholds offline, compute fault margin and false-positive rate per rule, and record them with the promotion change.

## Limits

- 2D image-space angles from a single camera: the same movement looks different from different heights and bearings, hence the camera-height requirement.
- No heel or toe landmarks: calf raise, foot position and heel lift are not judged.
- No spine landmarks: back rounding, lumbar extension and hyperextension are not scored. Good morning and tricep dip use neutral wording and make no back or injury claims.
- Camera view: rules assume the declared view (side or front); a wrong view degrades accuracy silently. Occlusion (box in step-up, bar in pull-up, a weighted arm in a row) and far-leg ambiguity are not detectable.
- Per-frame rules cannot see rep phase, so completion cues (pull-up full hang, step-up stand fully) are not shipped.
- Nothing here is medical advice.
