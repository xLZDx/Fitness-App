# Gate G12 — review scope

**In scope: two defects found on an S23 on 2026-09-02, and only those.**

1. The target silhouette was drawn at its authored coordinates while the user
   was drawn where the camera saw them. New `alignTargetToFrame` places the
   outline on the tracked body: anchored on the torso midline, sized by torso
   length, mirrored by the score's own mirror decision.
2. The live coach screen demonstrated the movement forever in the default
   (avatar) mode, so there was no still target to aim at. The demo loop is
   removed from the live screen entirely; the picker keeps it. This was decided
   by you earlier today as `VERDICT: MAJOR` — B supersedes A.

Also included, all found by review of (1) and remediated in the same batch:
- torso-length anchoring replaced a first attempt that reused `poseMatchScore`'s
  RMS normalisation and inflated the outline 1.69x for a standing user;
- midline anchoring replaced left-joint anchoring, which left the outline half a
  hip-width off the body on the device;
- `latestPoseFrameProvider` is cleared when leaving a set;
- three test-coverage gaps raised by the internal test reviewer.

**Explicitly OUT of scope — deferred, not overlooked:**
- The authored `squat.bottom` geometry itself (the MM-Fit refinement already on
  the roadmap). The demo of the squat's bottom position does not read as a
  squatting human on the device; that is the target's own shape, not this gate's
  placement of it.
- Rep #13 in the recording spans 980 frames — the rep counter has no upper bound
  on a repetition's duration. Real, observed, and a different subsystem.
- The three targets whose authored phases stretch a limb (pushup/hinge/situp).
- `[pose-probe] OUT OF CONTRACT` lines for low-confidence landmarks.

Acceptance: the outline is drawn on the user at the user's size and holds that
size through a repetition; the live screen shows a still target and never the
loop; the full suite stays green (593 in form_check + golden, 3477 overall).
