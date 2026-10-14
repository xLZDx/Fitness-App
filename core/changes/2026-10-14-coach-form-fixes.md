# Coach form fixes (2026-10-14)

Branch `sprint/coach-form-fixes-2026-10`, from master 42d1b84. Source: the
operator tested the squat coach on a real phone and reported (1) squat depth and
rep detection wrong and flaky, (2) no target silhouette on screen although the
voice says "you did not reach the silhouette", (3) voice cues too generic, never
"round back" or "shallow squat".

All paths below are under `mobile/`.

## Piece 1: target silhouette is drawn again

What changed
- `lib/features/form_check/form_check_page.dart`: new layer
  `form_check.layer.target` (widget `_TargetOutline`, painter
  `_TargetOutlinePainter`, paint key `form_check.target`) between the avatar
  and the skeleton overlay. It paints `poseTargetProvider` placed on the
  tracked body with `alignTargetToBody` (the same anchoring and mirror choice as
  the match score) and projected with `projectLandmark` using
  `frame.aspectRatio`, exactly like `_SkeletonPainter`. Semi-transparent
  outline (alpha 0.55 bones, 0.7 joint rings, theme `poseCorrect` colour).
- Shown only while `coachBodyDrawableProvider` is true; while nobody is tracked
  the demonstration still owns the panel.
- The paint is static (no animation), so there is no reduce-motion branch.
- Stale comment about the removed outline updated.

Why
- The operator's latest explicit instruction overrides the G17 decision that
  removed the outline. The voice cue and the match score already judge against
  this exact target; the user could not see it.

Contracts and paths affected
- No provider or scoring change. New widget keys only.

Verification
- New `test/features/form_check/coach_target_layer_test.dart`: layer painted
  with a tracked body (avatar and camera mode), absent with nobody tracked and
  after the body is lost.
- Re-run: live_demo_test, demo_silhouette_test, skeleton_overlay_test,
  avatar_mode_test (all green).

Not verified
- No live pose test on a device: placement on a real body, the look of the
  outline over the real camera/avatar, golden images (not run).

## Piece 2: specific squat voice cues (back rounding, shallow squat)

What changed
- Registry check: `assets/data/coach_exercises.json` has no squat row (squat is
  deliberately a legacy-classifier movement), so a dedicated classifier was
  added instead of lifting the squat exclusion.
- `lib/features/form_check/data/form_classifier.dart`: new `FormCueKey`
  values `squatBackRounding` and `squatDepthShallow`; new `SquatBackClassifier`
  (rule `squat.back`, `canFault` true, fault vertex hip). It measures the
  shoulder-to-hip line off vertical while the hip is within
  `minDepthRatio` of the knee (in torso lengths), enters at 60 degrees, releases
  at 50 degrees, needs 5 consecutive bad frames (hysteresis against flicker),
  and judges the better-visible side (`FrameSelectingClassifier`). Front-on it
  stays silent. It is a proxy: BlazePose has no spine landmarks, so true
  curvature is not observable; the explanation text says so.
- `lib/features/form_check/data/rep_counter.dart`: `RepCounterConfig.fullDepthSignal`
  (null by default, so every other movement is unchanged) and `shallowRule`.
  A completed rep whose peak stayed below `fullDepthSignal` is recorded as
  severity 1 under `squat.depth`.
- `lib/features/form_check/state/form_check_providers.dart`: squat now runs
  `[SquatDepthClassifier(), SquatBackClassifier()]`; `avatarVerdictSeverity`
  also colours the body for a later fault-capable rule; at rep completion a
  shallow rep produces the shallow cue and a specific squat cue is no longer
  overwritten by the generic `silhouette.match` cue; an `incomplete` rejection
  on squat speaks the shallow cue instead of the generic miss.
- `lib/features/form_check/data/cue_text.dart` and `lib/l10n/app_en.arb`,
  `app_ru.arb`: cue text, calm explanation and rule name (`squat.back`) for both
  languages. Voice floor checked: `CueGate` speaks severity >= 1; back is 2
  (preempts), shallow is 1 (3 s gap, same-cue repeat window 20 s). No gate change
  was needed.

Why
- The only fault the squat could raise was `silhouette.match`; depth and any
  back rule were severity 0 or absent, so the voice was generic.

Contracts affected
- `activeClassifiersProvider` for squat has two entries (depth first).
- `lastRepEvaluated` is now true for squat reps (a fault-capable rule ran);
  `scoring_gate_session_test` expectation updated accordingly.

Verification (focused)
- New `test/features/form_check/squat_cues_test.dart` (back rule fires on a
  folded sequence, not on an upright one, not before the min frames, hysteresis,
  not while standing, right-side-only view; texts RU/EN; voice floor; shallow
  vs deep vs unconfigured counter).
- Updated for the new contract: generic_coach_engine_test (`.first`),
  one_cue_per_rep_test, scoring_gate_session_test, cue_text_test.

