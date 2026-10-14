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
