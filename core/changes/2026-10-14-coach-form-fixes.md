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

## Piece 3: body-relative squat rep signal

What changed
- `lib/features/form_check/data/rep_signals.dart`: `squatBodyRelativeSignal`
  (hip height below knee divided by the shoulder-to-hip length of the same
  frame; each side measured alone and combined by confidence, so a side-on view
  with only the near side visible counts), `squatBodyRelativeSideDepths` (same
  unit, for the symmetry counter), `kSquatFullDepthSignal` (-0.20) and
  `squatBodyRelativeConfig`: top -0.57/-0.47, bottom -0.40/-0.30 (a rep is
  accepted at about 20 degrees off horizontal), shallow below -0.20. Derived
  from the authored shapes (`squat.top` -0.78, `squat.bottom` +0.16 in this unit).
  The torso, not the thigh, is the reference because the thigh foreshortens
  front-on.
- `lib/features/form_check/state/form_check_providers.dart`: `repSignalFor(squat)`,
  `coachSideSignalFor(squat)` and `coachFullAmplitudeSignalFor(squat)` (amplitude
  100% now means reaching the coach's target depth) use the new pieces. Other
  movements are untouched (`squatDepthSignal` and `RepCounterConfig` defaults are
  unchanged).
- `lib/features/form_check/data/form_classifier.dart`: `SquatDepthClassifier`
  now reads one side in the left slots (`FrameSelectingClassifier`) so a frame
  with a hidden far leg is no longer refused before it reaches the counter.

Why
- The raw hip-minus-knee fraction changed with phone height and distance, needed
  four joints at 0.5 and both legs visible, and used one fixed depth threshold.

Not changed, on purpose
- Counting before Start: `countingIsLiveIn` counts in every phase except
  paused, summary and selection. Eighteen existing cases in five files drive rep
  streams through the default phase (see the comment at
  `lib/features/form_check/data/coach_phases.dart`), so it was left alone.
- Front-on view: the torso reference keeps counting, but the back rule is silent
  there (a forward fold runs toward the camera). Documented limit.
- Shoulders are now required for counting (reference length). A squat filmed with
  the shoulders cropped no longer counts; documented limit.

Verification (focused, all run from `mobile/`)
- New `test/features/form_check/squat_body_relative_signal_test.dart`: same squat
  at two scales and heights counts 3/3 with the same peak (and a contrast
  assertion that the old raw signal differs by more than 0.05); near-side-only
  view counts; no side with three joints gives null; shallow rep (thigh 17
  degrees) counted but flagged, deep rep not, quarter squat not counted; live
  controller speaks shallow only for the shallow rep, round back only for the
  folded rep, nothing for a deep upright rep from a small far body; an
  incomplete squat with the silhouette target speaks the shallow cue.
- Fixture updated for the new unit: `rep_rejection_test.dart` half squat.
- Command: `flutter test` on the 45 focused files listed in the final report:
  536 passed, 0 failed.

Not verified
- No live pose test on a device; thresholds (-0.57/-0.47/-0.40/-0.30/-0.20, lean
  60/50 degrees, 5 frames) are PRODUCT_HEURISTIC values derived from authored
  shapes and synthetic bodies, not measured on the operator's phone.
- Golden images, full suite, analyzer, build: not run (policy).

## Follow-up A: squat cues written but not spoken (operator, real phone)

Trace (FACT, read in code): rep end in `RepSessionController` -> `coach.cue(cue)`
-> `GatedVoiceCoach.cue` -> `CueGate.peek` -> `resolveText(cueKey)` ->
`TtsVoiceCoach.utter` -> `flutter_tts speak`. The on-screen banner
(`lastRepCue`) is set on every counted rep without going through the gate.
Mute defaults to false, the severity floor is 1 (both new cues clear it), and
`formCueText` maps every new key (exhaustive switch).

Root cause reproduced by a test (FACT): `CueGate` applied its same-cue repeat
window (20 s) and minimum gap (3 s) on top of the per-rep pacing the controller
already provides. Three identical rep-end cues gave ONE utterance and three
banners (shallow cue, and the generic silhouette cue, were both affected; the
back cue at severity 2 is only held back by the 1.2 s interrupt gap).

Fix:
- `FormFeedback.repScoped` and `asRepScoped()` (`data/form_classifier.dart`);
  `CueGate.peek` (`data/voice_coach.dart`) skips the repeat window and the
  minimum gap for such cues (severity floor and mute still apply); the controller
  marks both rep-end cue sites (completed and rejected) as rep-scoped.
- The production voice wiring was moved out of `main.dart` into
  `data/localized_tts_voice_coach.dart` (`buildLocalizedTtsVoiceCoach`) so the real
  Russian resolver and `TtsVoiceCoach` can be driven by a test; `main.dart` calls
  it. Behaviour is unchanged.

Tests: new `test/features/form_check/squat_voice_spoken_test.dart` drives the real
controller, gate, resolver and `TtsVoiceCoach` over a fake `flutter_tts`
channel whose `speak` never completes until released, and asserts the Russian
text reaches `speak` once per rep for shallow, back-rounding and generic
silhouette cues (and that the specific cue wins over the generic one). Gate unit
test added to `squat_cues_test.dart`. `squat_body_relative_signal_test.dart`
fixtures are now exported (`squatRep`, `squatBody`).

HYPOTHESIS (not reproducible without a device): total silence from the very
first cue would come from the device, e.g. no ru-RU voice installed (the coach
latches `voiceUnavailable` and the page shows the voice-error card), or the TTS
engine/volume. The code path to `speak` is proven end to end only up to the
platform channel.

## Follow-up B: the target looks like a body figure, not a second skeleton

Operator: "green corners on the figure" -- the first target layer (thin green
lines, 9 px joint rings, theme `poseCorrect`) read as a duplicate skeleton.
`_TargetOutlinePainter` (`form_check_page.dart`) now draws a translucent body
figure: round-capped limbs 16 px, trunk 24 px, arms 11 px, a filled head
(`PoseTarget.head`), pale cyan `0xFF8FE9FF` (not the green/red verdict colours,
not the white skeleton), no joint rings, the whole figure inside one
`saveLayer` at alpha 0.42 so joint overlaps do not double up. Placement is
unchanged (`alignTargetToBody`, `projectLandmark`). Stack order is unchanged:
between the avatar and the skeleton overlay. In avatar mode the avatar's own
bones are part of the avatar layer below, so the figure tints over them; moving
the target under the avatar would hide it behind the avatar's near-opaque body.

Tests: `coach_target_layer_test.dart` now asserts the stroke widths, colour,
filled head, absence of stroked joint rings, the layer order, and that nothing
opaque sits under the layer.

## Follow-up C: preview area and the missing squat demonstration (findings, no code change)

FACT (read in code and in `git diff 42d1b84..HEAD` / `git show 42d1b84:`):
- `git diff 42d1b84..HEAD -- mobile/lib/features/form_check/widgets` is empty:
  none of my commits touched the demonstration widgets. At master 42d1b84
  `coachDemoFor(FormExercise.squat)` already returned
  `CoachDemoUnavailableSource()` (the squat clip was removed on 2026-09-09 and
  the figure stand-in was rejected by the same ruling), and that source is what
  renders "Показа для этого движения пока нет" (`formcheckDemoUnavailable`). So
  squat did not lose a demonstration because of this sprint; it never had one at
  this base. Nothing was restored: re-adding a drawn stand-in contradicts the
  2026-09-09 ruling, and `live_demo_test`/`demo_silhouette_test` pin the
  absence. Whether squat gets a demonstration back is a product decision.
- My `form_check.layer.target` is a `Positioned.fill` > `IgnorePointer` >
  `RepaintBoundary` > `CustomPaint` with no child and no background: it paints
  only the figure and is transparent everywhere else; it sits above the
  backdrop/preview, so it cannot hide them. `coach_target_layer_test` asserts
  there is no `ColoredBox`/`DecoratedBox` under it and the layer order. The only
  other new overlay code is the same layer.
- `avatarModeProvider` defaults to true: in that mode the camera image is NOT
  shown at all, the panel is the photo backdrop (`_AvatarBackdrop`, scrim up to
  65% black at the bottom) with the avatar drawn on it. An "empty/dark" panel
  before a body is tracked is therefore the backdrop plus the demonstration slot.
  In camera mode the existing `_PreviewScrim` (radial, 34% to 86% dark) darkens
  the preview heavily; it predates this sprint (present at 42d1b84).
- "Слишком темно или размыто, чтобы разобрать позу" is `formcheckGateLowConfidence`,
  the `lowConfidence` gate verdict: some joint the active rules or the target
  scoring need is reported below 0.7 likelihood. The effective verdict also
  includes the silhouette's scored joints (shoulder, hip, knee, ankle), so a poorly
  visible ankle alone triggers it. This logic predates the sprint.

HYPOTHESIS (needs the device): the dark preview and that hint came from low light
or a body the detector could not place (no tracked body, so no avatar and no target
figure, only the unavailable-demo text). Whether the squat counter/classifiers now
reject frames the old ones accepted is not expected (they require fewer joints than
before: one side of hip and knee, plus shoulder for the back rule and the signal)
but is unmeasured.

Final focused run for the whole follow-up: 570 tests green (50 files under
`test/features/form_check` plus `test/l10n`, listed in the report).

## Review follow-up 1: target painter cost

`_TargetOutlinePainter` (`form_check_page.dart`): the stroke, head and layer
`Paint` objects are now static (built once, never mutated, one stroke paint per
width) and the alpha `saveLayer` is bounded to the figure's rectangle instead of
the whole canvas, so no full-screen offscreen buffer is allocated per camera
frame. The look is unchanged (same widths, colour and 0.42 layer alpha); the
painter no longer takes a colour argument. Verified by `coach_target_layer_test`.

