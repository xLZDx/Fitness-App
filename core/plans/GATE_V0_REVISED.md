# Gate V0 (revised) + round-1 findings for cross-review

Round 1 of review (8 agents, 2026-07-31) is complete. This document is the input to round 2.
It states (a) what round 1 established, (b) the points where reviewers **contradict each other**,
(c) the revised gate that must now be built.

Round 2's job is NOT to repeat round 1. It is to attack the conclusions below and to say, for each
contested point, AGREE / DISAGREE / REFINE with evidence.

Prior context: `../PLAN_2026-07-31.md`, `../BACKLOG_2026-07-31.md`.

---

## A. Established in round 1 (verified against the repo by the author, not just asserted)

| # | Finding | Evidence |
|---|---|---|
| A1 | Nothing normalises pose coordinates anywhere in the chain | Android `PoseDetector.java:94` `getPosition3D().getX()`; iOS `landmark.position.x`; plugin `pose_detector.dart:160` `x: json['x']`; our `_convert` `x: lm.x` |
| A2 | `pose_landmark.dart:35-39` documents those fields as "normalised 0..1" | direct read |
| A3 | `CueGate.decide()` commits "spoken" BEFORE the text is resolved; the new empty-text early-return therefore drops a cue while the throttle believes it fired | `voice_coach.dart` decide/_commit + `cue()` |
| A4 | `VoiceCoach.lastErrorMessage` has zero readers in `form_check` UI or state | grep: only `health_sync_card.dart:38` reads any `lastErrorMessage` |
| A5 | `_configured = true` is set before the unguarded `setLanguage`/`setSpeechRate`/… calls, so one throw latches a permanently mis-configured coach | `tts_voice_coach.dart:54-79` |
| A6 | `main.dart`'s `unawaited(AppLocalizations.delegate.load(...))` has no error handler; failure = permanent silent mute | `main.dart` |
| A7 | BlazePose has no thoracic/lumbar landmark at any configuration; `DeadliftBackAngleClassifier` measures **hip flexion**, not lumbar flexion | `form_classifier.dart` `_angleDeg(shoulder, hip, knee)`; landmark set |
| A8 | `exercise_demo.dart:47-57` already implements eased travel with holds — planned gate B1a is ~90% redundant | direct read |
| A9 | 30 `FieldLabel('…')` English literals in `features/onboarding/steps/`; `_SectionHeader('Today'/'Upcoming'/'Quick stats'/'Suggestions')` in `home_page.dart`; English `reason` strings in `suggestion_builder.dart:111+` | grep |
| A10 | The l10n guard scans only `Text('…')`, so positional args to custom widgets are invisible; `scripts/l10n/extract_strings.py` shares the blind spot | `no_untranslated_strings_test.dart:54` |
| A11 | `navyBodyFatPercent` requires `neckCm` and returns 0 without it | `body_comp_estimate.dart:41,45` |
| A12 | `rankedForYouProvider` has zero consumers repo-wide | grep |
| A13 | 192 exercises: 14 have `equipmentId: null`; the other 178 can inherit location from 48 equipment rows → 100% coverage from one file | counted |
| A14 | `CameraSession` defaults to `SessionFacing.back`; form_check explicitly overrides to front | `camera_session.dart:29`, `mlkit_pose_detector_service.dart:24` |
| A15 | `camera_session.dart:199-201` already supplies `InputImageMetadata(size:, rotation:)`, so image dimensions are available at conversion time | direct read |

---

## B. CONTESTED — reviewers disagree with each other. Round 2 must resolve these.

### B1. Are ML Kit landmark coordinates pixels or normalised? **(highest stakes)**

- **flutter-reviewer**: BLOCKER — they are image **pixels**; the new gate compares them against 0.02 / 0.10, so `gatePose` returns `outOfFrame` on essentially every real frame and the feature stops scoring anything, ever.
- **code-reviewer**: walked `gatePose` with "a real squat" at y=0.25/0.55 and concluded the logic is **correct** — i.e. implicitly assumed normalised input, and never questioned the unit.

These cannot both be right. The author verified A1 (nothing normalises) but did **not** verify ML Kit's own contract, which lives in a binary AAR.

**Round 2 must decide**: what does `PoseLandmark.getPosition3D()` actually return, and what is the decisive check that does not require a device? If the answer is pixels, then note that the PRE-EXISTING thresholds (`rep_counter.dart` `topEnter=-0.15`, `bottomEnter=-0.04`; `SquatDepthClassifier`'s `ratio > -0.04`) were already meaningless, i.e. the feature never worked — which is a different and larger defect than the one V0 was written to fix.

### B2. Is the deadlift rule a live false positive on correct technique?

- **architect**: yes — a correct Romanian deadlift puts shoulder-hip-knee at ~90-120°, below the 150° threshold, producing severity 2 "Stop — back is rounding under load", spoken on a 1.2 s loop. The pose gate cannot catch it because the joints are real and confident. Explicitly flagged as derived from geometry, **not observed on a device**.
- No other reviewer looked at it.

**Round 2 must decide**: is the geometry right? What does the angle actually measure for (a) a correct RDL, (b) a conventional deadlift at lockout, (c) a genuinely rounded back? If the finding holds, what is the minimum honest fix — retune, re-cue, rename, or remove the rule?

### B3. References-from-stills vs invariants. Which architecture?

- **architect**: abandon per-exercise references. Build ~7 camera-invariant checks routed by `movementPattern` (which E1.3 already pays to tag). Argues left/right symmetry is the **only exactly camera-invariant measurement available**, and that the user's own first set is a better reference than a stock photo because it supplies trajectory and tempo, which stills structurally cannot.
- **planner**: did not challenge the reference approach; instead re-sequenced it (V3 does not depend on V2; V4 does not depend on V3).

**Round 2 must decide**: is the symmetry-invariance claim mathematically correct? Is `movementPattern` routing sufficient to cover the faults an ordinary user actually makes? What does the invariant approach FAIL to catch that references would have caught — state it plainly rather than selling the alternative.

### B4. Does the V0 l10n guard widen repo-wide now?

- **planner**: widening as specified turns the suite red on 80+ pre-existing violations (A9); V0 must either ship a knowingly-narrow guard or absorb a repo-wide localisation pass. Also notes `scripts/l10n/extract_strings.py` already exists and widening its `PATTERNS` is far cheaper than 80 hand edits.
- **pr-test-analyzer**: specified the widened matcher without costing the fallout.

**Round 2 must decide**: narrow-now-widen-later, or one repo-wide pass, and what is the actual cost of the extract-strings route.

### B5. Expand 13 → 33 landmarks now, or later?

- **architect**: now, in V0 — ~20 lines, zero inference cost, ML Kit already computes them; unlocks heel lift, ankle ROM, foot line, head position. Every later gate is built on this set.
- **type-design-analyzer**, **code-reviewer**: silent.

**Round 2 must decide**: does expanding the set now change the gate's own thresholds or tests in a way that makes V0 riskier, or is it genuinely free?

---

## C. Revised gate V0 — what will actually be built

Order matters: each step below is a precondition for the next.

### V0.1 — Settle the coordinate unit, loudly

1. Normalise in `_convert` using `InputImageMetadata.size` (available per A15), swapping width/height for 90°/270° rotation.
2. Make a unit mismatch **detectable rather than silent**: if landmarks land far outside 0..1, that is its own surfaced error state, not a permanent "step back" hint. The V0 defect class is "the feature went quiet and nobody could tell why" — the fix must not create a new instance of it.
3. Fix the `pose_landmark.dart` doc so it describes what the field holds.
4. Add a diagnostic that reports observed min/max so one device run settles B1 for good.

### V0.2 — The deadlift rule (pending B2)

If B2 holds, the rule must not keep telling a correct lifter to stop. Minimum honest options, in preference order: re-cue to what it actually measures (hip flexion), retune thresholds, or disable it until it can be measured properly.

### V0.3 — The three self-inflicted blockers

- A3: do not commit the throttle state until the text is known and non-empty.
- A5: reset the configured-latch on failure so the next cue retries.
- A6: attach an error handler; on failure degrade to something audible/visible, never to silence.
- A4: give `lastErrorMessage` a reader, or stop claiming in the doc comment that it has one.

### V0.4 — Correctness of what is already written

- `requiredLandmarks` doc says "joints this rule reads"; `SquatDepthClassifier` declares shoulders it never reads. Restate the contract as "must be present and plausible for this rule to be trusted; a superset is fine, a subset is a bug".
- `GatedEvaluation`'s invariant (verdict==ok iff feedback non-empty) is enforced by one call site only.
- `PoseGateVerdict` priority is implicit in declaration order, in a different file from the code that depends on it.
- Cue keys as bare Strings give no exhaustiveness checking; a typo becomes a silently-empty cue.
- Russian cue strings use informal "ты" while the rest of the app uses "вы".
- `RepCounterConfig.minLikelihood = 0.5` vs `PoseGateConfig.minLikelihood = 0.7`: a frame can be "scorable" because one left-side rule passed, while the counter then reads right-side joints at the looser floor.

### V0.5 — Tests

Both signatures of the face-only case (low-confidence extrapolation AND confident-but-collapsed torso), one per gate verdict, and — most important — **a valid squat still counts**. Localisation resolved against real `AppLocalizations`, not a hand-written mock that will drift from 390 ARB keys.

---

## D. What round 2 is asked for

For each contested point B1-B5: **AGREE / DISAGREE / REFINE**, one paragraph, with file:line or a derivation. Then: what in section C is still wrong, missing, or ordered badly?

Do not restate round-1 findings that are already in section A. Do not propose new features.
