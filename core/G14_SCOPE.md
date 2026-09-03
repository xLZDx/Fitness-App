# G14 scope note — target-alignment torso upper bound

## What this gate covers

`alignTargetToBody` (`mobile/lib/features/form_check/data/pose_target.dart`)
had a guard against a degenerate torso reading (`liveTorso < 1e-9`, division
blow-up) but none against an implausibly LARGE one. Found live: the operator
ran a real squat set on the S23 (build 2965, `dbe02a9`) and reported an
obviously broken silhouette — a grotesque, exploded shape frozen on screen
after the set. `adb logcat` correlated it with a `[pose-probe]` line showing
a *trusted* (likelihood >= 0.70) coordinate extent of roughly 1.6x frame
height corner-to-corner, right after the last rep completed (the lifter
stepping back/picking up the phone). Each individual joint was within
`pose_avatar.dart`'s own +-0.5 `_drawable` slack, but the PAIR distance
between them was not — a case nothing was checking.

**Round 1 correction (GPT-PM, 2026-09-03, MAJOR).** The first fix rejected
`liveTorso > 1.2`, cited to the `[pose-probe]` line above. GPT-PM correctly
challenged that citation: `PoseUnitProbe` accumulates a bounding box over
every frame and every landmark since the controller was built (never reset
in `FormFeedbackController`), so its logged extent is not proven to be one
frame's shoulder-and-hip pair. Checked the existing evidence for a genuine
per-frame reading first — none existed (the `[rep]` lines only dump joints
for a completed rep's deepest frame, and both completed reps finished before
the exploded-outline window started). Added a permanent `[align]` debug log
directly in `alignTargetToBody` and reproduced the same trigger live, on a
Mi 9T Pro (S23 not available at the time), 2026-09-03: stepping out of frame
mid-set produced real per-frame `liveTorso` 0.461-0.641 across a dozen
frames, while nine matched, correctly-scored reps in the same session
measured 0.252-0.256 at their deepest frame (`wantTorso` is 0.257). **1.2
would not have rejected a single one of the real bad frames** — the
original guard was a no-op against the defect it was written for.

Fix, corrected: `alignTargetToBody` now rejects `liveTorso > 0.40` — real
margin below every observed bad frame (min 0.461), real margin above every
observed good one (max 0.256) — falling back to the same "cannot place,
draw at the authored position" path a body with too few shared joints
already takes. Evidence: `reports/device-check-2026-09-02/
mi9_align_repro_logcat.txt`.

New regression tests, `pose_alignment_test.dart` (now built from the real
Mi 9T Pro single-frame reading, not the disputed accumulator
reconstruction): "a torso far longer than any real body is not scaled up
either", "and the same, fed through the actual production path...", and a
new positive control "a real, well-matched torso is not rejected by the
same guard" (real deepest frame of a real passing rep, same session). All
three mutation-checked (fail without the 0.40 guard, pass with it; the
positive control stays green either way, confirming it is not accidentally
exercising the same code path).

**Round 2 (GPT-PM, MAJOR): the reject side was proven, the accept side was
not.** An absolute cutoff also has to not reject a real, validly-tracked
user standing closer to the camera, since `liveTorso` grows with proximity
for a genuine body too -- and the only positive control so far was a
nominal-distance rep (~0.25), nowhere near 0.40. Required: capture the
largest legitimate `liveTorso` a real, correctly-framed close body reaches.

Asked the operator to hold a squat progressively closer to the Mi 9T Pro,
twice. Every rep that stayed under ~0.26 matched normally (`gate=ok`, peak
0.81-0.86). The closest sustained attempt reached `liveTorso` 0.454-0.470
across 8 consecutive real frames (`reports/device-check-2026-09-02/
mi9_close_distance_repro_logcat.txt`, 14:16:06.7-08.9) -- but that same rep
independently scored `gate=PoseGateVerdict.lowConfidence` and `match=0.193`
(a second close attempt: `match=0.640`), both well under the 0.80 pass
mark. **The one real sample this investigation could produce anywhere near
the 0.40 cutoff was already flagged unreliable by the app's own confidence
and match signals**, not a case of a confidently-tracked body losing its
outline to this guard alone. Stated plainly, not overclaimed: two honest
attempts did not produce a clean high-confidence sample between 0.26 and
0.40 -- that is evidence the band was not observed to be populated, not
proof it is empty. Added as a fourth test, using the real coordinates from
the middle of that cluster: "the closest real attempt this investigation
could capture is also rejected, and it was already unreliable by the app's
own signals." Mutation-checked with the other three.

`pose_alignment_test.dart` + `pose_target_test.dart`: 80 green.

**Round 3 (GPT-PM, MAJOR, correcting round 2's own framing): `gate=ok` and
a low silhouette match are not the same signal.** Round 2's rep #17
(`gate=PoseGateVerdict.ok`, `match=0.640`) was cited as another "unreliable"
sample; GPT-PM correctly pointed out a correctly-tracked person can simply
not be in the target's shape yet, which is not evidence the coordinates are
unusable for placement. Required: either a genuinely valid near-boundary
sample with real margin below 0.461, or stop using torso size alone as the
discriminator (checked: `pose_gate.dart`'s `gatePose` has no upper-bound
torso check at all today, only `minTorsoSpan` for too-small, so "reuse an
existing signal" is not a drop-in option without its own new gate work).

Asked for one more attempt: a deliberately closer, well-EXECUTED squat
(not just closer). Rep #25 in that session (`reports/device-check-2026-09-02/
mi9_close_good_match_repro_logcat.txt`) produced `gate=PoseGateVerdict.ok`
with `match=0.210` (short of depth: `hipMinusKnee=0.104`, not a tracking
problem) at `liveTorso=0.332` (verified: `leftShoulder=0.345,0.486
leftHip=0.186,0.777`, distance 0.3316) — a real, reliably-tracked sample
squarely inside the previously-empty 0.26-0.40 band, correctly NOT rejected
by the 0.40 guard. Added as a fifth test, using these exact coordinates.
Mutation-checked with the other four (positive controls confirmed to stay
green with the guard disabled too, i.e. not accidentally exercising the
guard's own rejection path).

`pose_alignment_test.dart` + `pose_target_test.dart`: 81 green.

## What this gate does NOT cover

**The golden-test order-independence flake, PRE-EXISTING and NOT caused by
this change.** `form_coach_golden_test.dart`'s three goldens, previously
fixed in G13 (`precacheBackdrop`, verified stable across repeated full-file
and individual runs at the time), are failing again now — reproducibly,
across repeated runs, at `--concurrency=1` too, and confirmed via `git
stash` to fail IDENTICALLY with this gate's change removed. So this is a
regression in test infrastructure the codebase already shipped, not
something G14 introduced, and not something G14 attempts to re-diagnose or
re-fix — flagged to GPT-PM as a separate, honestly-reported finding rather
than silently worked around or silently left unmentioned.

Full `flutter test` re-run after the round-1 correction: 3489/3492 green,
the 3 failures confirmed by a targeted re-run to be the identical
pre-existing `form_coach_golden_test.dart` flake (same pixel-diff symptom,
same file) -- not a new regression from this correction. Not re-run again
after rounds 2/3 (only `pose_target.dart` and its own test file changed
each time, both covered directly above).
