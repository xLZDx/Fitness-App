# What to do next — after two review rounds

Both rounds are complete (8 agents round 1, 6 round 2). This supersedes Part V of
[`../PLAN_2026-07-31.md`](../PLAN_2026-07-31.md) and section C of
[`GATE_V0_REVISED.md`](GATE_V0_REVISED.md).

Nothing below is approved. Each gate needs its own `GO <name>`. Push needs a separate `push`.

---

## Decisions the two rounds settled

| # | Question | Settled as |
|---|---|---|
| B1 | Are landmark coordinates pixels or 0..1? | The plugin's own doc says **image space** (`pose_detector.dart:135-141`), and nothing in the chain scales. BUT the operator's 6-counted-reps incident is arithmetically **impossible** with pixel values (the counter's whole hysteresis ladder spans 0.11 units; crossing it would need hip and knee within 0.11 px). Unresolved on evidence → **normalise explicitly (correct either way) and MEASURE before touching any threshold.** |
| B2 | Is the deadlift rule a false positive on correct technique? | **Yes, structurally.** Correct RDL = 82.9°, rounded back at the same depth = 77.7°, threshold at 150°. Both severity 2, 5.2° apart. The metric is hip flexion, not spinal curvature; the classes overlap by construction. No retune fixes it. |
| B3 | References-from-stills, or invariants? | **Neither, as proposed.** References: 126/192 have no local stills, and a still gives a point, not a tolerance band. Invariants: symmetry is exact only where limbs have no frontal-plane extent — i.e. exactly where there is nothing to detect — and is blind to all bilateral faults. Self-as-reference *certifies* a beginner's error. `movementPattern` does not exist. |
| B4 | Widen the l10n guard repo-wide now? | **Split by mechanism.** 35 UI sites are script-automatable now; ~14 data-layer sites need the cue-key treatment and wait (7 of them are deleted by E1.6 anyway). Guard gets an explicit allow-list so the debt is visible rather than invisible. |
| B5 | Expand 13 → 33 landmarks now? | Free, but **after** the coordinate measurement, not in the same edit — otherwise it muddies the signal the diagnostic exists to produce. |

**The product consequence.** V0 ships **no form correction**. It ships rep counting, honest
"cannot score this" verdicts, and a UI that says plainly what is and is not being judged.

---

## Bugs I introduced that the review caught

These are not findings about old code. They are defects in the uncommitted V0 work.

| # | Defect | Consequence |
|---|---|---|
| 1 | Torso-span check assumes an upright body | Push-ups and every supine exercise return `implausibleGeometry`. `PushupAlignmentClassifier` — one of the three shipped rules — is disabled outright |
| 2 | `SquatDepthClassifier` declares shoulders so the gate can check the torso; the gate then edge-checks them | A squat framed with shoulders near the top of frame returns `outOfFrame`; depth is never scored. A rule that never reads shoulders is blocked by shoulders |
| 3 | Proposed normalising x by width and y by height | Anisotropic scaling does not preserve angles. Measured: 82.9° → 77.5°, an error larger than the entire signal the deadlift rule claims to measure |
| 4 | `CueGate.decide()` commits "spoken" before the text is resolved | A cue that fails to resolve is dropped **and** poisons the throttle for the next real attempt |
| 5 | `_configured = true` set before the unguarded TTS setters | One transient failure latches a permanently mis-configured coach |
| 6 | `unawaited(AppLocalizations.delegate.load(...))` with no error handler | Load failure = permanent silent mute, invisible to `lastErrorMessage` |

---

## V0a — everything that does not read a coordinate

No measurement needed. Safe and useful regardless of how B1 resolves — and it must come first,
because a coach that can die silently cannot report a coordinate range.

1. **Fix defects 1 and 2.** Run the torso check only when the body is upright; separate "landmarks
   this rule reads" from "landmarks that must be plausible for it to be trusted" so the latter are
   not edge-checked as if the rule needed them in frame.
2. **Fix defects 4, 5, 6.** Commit the throttle only once the text is known and non-empty (needs
   `decide()` split into peek/commit); distinguish transient from permanent TTS failure so a device
   with no Russian voice latches as broken instead of re-probing every 1.2 s; attach an error
   handler to the localisation load.
3. **Give `lastErrorMessage` a reader** — a persistent banner in the form-check screen, following
   `health_sync_card.dart:38`. A one-shot toast reproduces the same silence after its first showing.
4. **Types**: `GatedEvaluation`'s invariant enforced by construction; `PoseGateVerdict` priority
   explicit instead of implicit in declaration order; cue keys as an enum so a typo is a compile
   error rather than a silently empty cue.
5. **Register**: Russian cue strings to «вы», matching the rest of the app.
6. **l10n**: widen `scripts/l10n/extract_strings.py` `PATTERNS` for positional args with a callee
   deny-list, run it, hand-write the 35 Russian strings, widen the guard test, allow-list the
   data-layer residue by file:line.
7. **Coordinate diagnostic**: read-only min/max reporter over incoming landmarks. This is what turns
   B1 from a blocker into the output of a shipped slice.
8. **Tests**: both face-only signatures (low-confidence AND collapsed-torso); a valid squat still
   counts; **a valid push-up still counts** (defect 1's regression); edge-of-frame boundary; an
   unscorable frame does not advance `repCount`, asserted through the controller; every cue key
   resolves non-empty in both locales.

~10 files.

## V0b — settle the unit

1. Normalise **both axes by the same scalar** (post-rotation image height), so angles survive.
2. `gatePose` takes per-axis bounds — `y ∈ [0,1]`, `x ∈ [0, w/h]`.
3. Fix the `pose_landmark.dart` doc to describe what the field actually holds.
4. A unit mismatch gets its **own** surfaced state, not `outOfFrame` — never tell the user to step
   back from a bug that stepping back cannot fix.
5. Ends with **one run on the operator's phone** reading the diagnostic.

~5 files + one device run.

## V0c — only after the measurement

1. Retune every threshold against the now-known unit: `edgeMargin`, `minTorsoSpan`, `topEnter`,
   `bottomEnter`, `ratio > -0.04`, and the two competing likelihood floors (delete one, don't tune
   two).
2. **Exercise selection**, so a rule only runs for the movement the user picked. Without this,
   fixing the deadlift rule is cosmetic — all three rules currently run on every frame, which is why
   a squatting user is judged by the deadlift rule at all.
3. The deadlift rule stops emitting a safety cue until a real curvature proxy exists. There is no
   spine landmark at any BlazePose configuration, so this is not a "later" item — it is permanent
   for this model class.
4. Expand 13 → 33 landmarks.

~8 files.

---

## Outside the V-chain, independent, can run in parallel

| Gate | Why now |
|---|---|
| **A1** — zero empty machines | ~1 h, no dependencies, immediately visible. 9 of 11 empty machines close with real content once my category filter is lifted |
| **A3a** — test pins zero-empty | 15 min, right after A1. Do not wait for A2 (which is blocked on the translation decision) |
| **V0.5** — scanner discloses that photos go to Google | 3 files, ~20 min. Two shipped screens currently contradict each other |
| **V0.6** — measure scan latency by stage | Pairs with V0b's device run — one session, both measurements |
| **E1.1′** — wire `rankedForYouProvider` | One consumer, code already tested. **First** read what it ranks on: if it keys on `difficulty` (129/55/8), it makes the feed worse until the catalog is tagged |

---

## Removed or downgraded from the earlier plan

- **V1 (references from 186 stills)** — not built as specified. Both rounds agree the inputs do not
  support it.
- **B1a (tempo morph)** — already shipped in a previous gate (`exercise_demo.dart:47-57`). Only the
  asymmetric eccentric/concentric split remains, ~10 lines, folded into B3.
- **V2 (skeleton overlay)** — promoted ahead of V1. It makes no claim about form, so it cannot be
  wrong about form, and it delivers most of the perceived value.
- **E1.3 (tag all 192 exercises)** — the location axis needs **48 equipment rows**, not 192
  exercises: 178 inherit through `equipmentId` and the remaining 14 have none, so coverage is 100 %
  from one file.

---

## What I need from the operator

1. **One device run** with the V0b diagnostic build. Everything downstream of it is guesswork until
   then. Pair it with the scan-latency measurement.
2. **Scanner disclosure** — fold into V0a, or its own gate?
3. **A2 translation strategy** — still open from 2026-07-30. Narrow hand-written set, or batch draft
   through Gemini with spot-checks?
