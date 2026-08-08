# R10 — Posture, plan (2026-08-08)

Written before code, per the operator's own requirement ("новая фича, нужен
свой план перед кодом"). Cross-references: `core/DECISION_LOG.md` entries
"Decision — осанка входит в план как R10, после R9" and "Decision — R8 и R10
строим на MM-Fit" carry the decisions this plan builds on; not repeated here
in full.

## 1. Scope, as already decided (not re-litigated here)

- Separate gate from R8 (Technique Coach). Static standing pose, not an
  exercise rep counter — the user stands in front of the camera, not
  squatting.
- Three metrics: shoulder asymmetry, pelvis tilt, forward head.
- Same detector as the rest of Form Check: `google_mlkit_pose_detection`
  (BlazePose, 33 points) via the existing `PoseDetectorService` /
  `MlKitPoseDetectorService`.
- Thresholds measured, not guessed — from MM-Fit (CC BY 4.0), the same
  dataset R8's `measured_rep_configs.dart` already draws from.

## 2. The methodology problem this plan exists to name

MM-Fit is exercise motion-capture data (squats, push-ups, curls, lunges,
sit-ups, presses) — it contains no "stand neutrally for a posture check"
scenario. `core/DECISION_LOG.md` already recorded that both skeleton sides
are present (so asymmetry is *computable*), but computable is not the same
as *representative of neutral standing*.

**Proxy, stated plainly as a proxy, not as ground truth:** the "top" phase
of a standing exercise — the moment `extract_mmfit_targets.py` already
isolates as `top_deg` (95th percentile of the driver signal) for squats and
lunges — is the closest available approximation of "an ordinary person
standing normally" in this dataset. Measuring shoulder-height-diff,
hip-height-diff and head-forward-offset from those specific frames, across
many people, gives a distribution of *typical variation among people who
are not being clinically assessed* — not a clinical "correct posture"
reference range. This is the same posture the R8 file's own docstring takes
toward its numbers ("describes what a repetition looks like when ordinary
people do it — not what a *correct* one looks like. Use as the centre of a
plausible range, never as a pass/fail line on their own"); R10 inherits that
same posture, one level up.

**A second, real mismatch:** Human3.6M's skeleton (used by MM-Fit) has one
`HEAD` joint (index 10), not ears. The app's live detector is BlazePose,
which has `leftEar`/`rightEar` (verified: `PoseLandmarkType.leftEar` at
`google_mlkit_pose_detection-0.14.0/lib/src/pose_detector.dart:93`) but no
single "head" point. So the *measured* forward-head number (from
Human3.6M's HEAD-to-shoulder-midpoint offset) and the *live* forward-head
signal (from ear-midpoint-to-shoulder-midpoint offset) are approximating the
same idea — how far forward the head sits relative to the shoulders — from
two different anatomical references, not the same one. Both this and the
proxy problem above go into the extraction script's own docstring, the same
way `extract_mmfit_targets.py:27-33` already states its own limits.

## 3. What "measured" buys here, honestly

Given both caveats, R10's thresholds are weaker evidence than R8's. R8
measured how a KNOWN exercise's known driver angle behaves — a repeated,
labelled, unambiguous event. R10 measures incidental asymmetry in people who
were captured mid-workout, not applying for a posture assessment. The
gauntlet that applies: **shuffle/dedup/cost/cross-period** doesn't
transplant cleanly to a threshold-derivation script, but the equivalent
check does — report the sample's own spread (P25/P50/P75), not just a
mean, so a wide band is visible as a wide band rather than smoothed into a
single confident-looking number. Same discipline `measured_rep_configs.dart`
already applies (`bottomP25`/`bottomP75` fields, not just `bottomDeg`).

**Language discipline for this gate specifically:** never call these
"correct posture" thresholds. They are "typical range observed in a
motion-capture sample," full stop, and the UI copy has to say that too.

## 4. Architecture

Mirrors R8's file layout, one directory over (`features/posture/` next to
`features/form_check/`), because there is no static-pose target/silhouette
concept to share with a rep-counting page.

| Layer | File | Mirrors |
|---|---|---|
| Landmark wiring | `mobile/lib/features/form_check/data/pose_landmark.dart` — add `leftEar`, `rightEar` to `LandmarkType` | n/a, extends an existing enum |
| Landmark wiring | `mlkit_pose_detector_service.dart` — two more `add(...)` calls | the 13 existing `add()` calls |
| Data extraction | `scripts/pose/extract_mmfit_posture.py` (new script, not a flag on the existing one — different unit of analysis: whole-frame posture, not a per-exercise driver angle) | `extract_mmfit_targets.py` |
| Measured config | `mobile/lib/features/posture/data/measured_posture_config.dart` | `measured_rep_configs.dart` |
| Metric functions | `mobile/lib/features/posture/data/posture_metrics.dart` — pure functions, `PoseFrame -> double?` per metric | `rep_signals.dart` |
| Session state | `mobile/lib/features/posture/state/posture_providers.dart` — captures ~2s of frames while the user holds still, averages, reports a verdict per metric | `form_check_providers.dart`'s `RepSessionController`, but averaging instead of counting |
| Screen | `mobile/lib/features/posture/posture_page.dart` | `form_check_page.dart` |
| l10n | new `posture*` keys, EN + RU | existing `formcheck*` keys |
| Tests | metric-function tests, measured-config test, provider test, screen widget test | R8's own test files, same names one level over |

### Not decided here — needs a product answer, not an engineering one

**Entry point / navigation.** `MainShell`'s bottom nav is a fixed 5 tabs
(home/scan/workouts/progress/profile) — R10 does not obviously belong on any
of them, and adding a 6th persistent tab is a navigation-IA decision, not
one this plan makes unilaterally. Candidates: a card on Home (like the
existing Technique Coach entry point, if one exists there), a card on
Profile, or a new tab. **This plan does not pick one** — flagged for the
operator, not guessed.

## 5. Metric definitions (for the extraction script and the live functions to agree on)

All three read the same skeleton on the same frame; all three are
normalised by a body-scale measurement so the number does not depend on
distance from the camera — same principle `rep_signals.dart` already uses
for the non-squat rep signals.

- **Shoulder asymmetry** = `(rightShoulder.y - leftShoulder.y) / shoulderWidth`. Positive = right shoulder lower.
- **Pelvis tilt** = `(rightHip.y - leftHip.y) / hipWidth`. Positive = right hip lower.
- **Forward head** = `(earMidpoint.x_forward_axis - shoulderMidpoint.x_forward_axis) / torsoLength`. Sign convention depends on which way the person faces the camera — needs the same side-on framing instruction Form Check already uses (`formcheckStandSideOn`), since a face-on frame cannot show sagittal forward-head displacement at all. **This is a framing requirement the UI must state**, not an edge case to handle silently.

## 6. Rollout inside this session

Given the size already landed this session (R8, R9, R9b — three gates,
eleven commits), and that R10 involves a genuinely new methodology
(sections 2-3 above) rather than extending an already-proven pattern:

1. This plan (done, this file).
2. Landmark wiring + extraction script + measured config + metric
   functions + their tests — the well-specified "data/model" layer,
   same rigor as R8.
3. Screen + provider + route — held for a product decision on entry point
   (§4), not attempted blind.

Step 3 is explicitly **not** started until §4's open question is answered.
