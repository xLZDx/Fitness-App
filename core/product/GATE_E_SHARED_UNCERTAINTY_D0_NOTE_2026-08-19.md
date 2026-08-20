# Gate E D0 — Reconnaissance note: shared uncertainty contract (MRD-06)

Scope: "build a minimal shared semantic layer [for expressing uncertainty]
without inventing a universal numeric confidence model." Per the Decision
Pack, MRD-06 was assessed "Partly built" — three surfaces already expose
uncertainty (closest-matches, count-not-tracked, experimental label) with no
shared vocabulary between them.

## FACT — full inventory of existing uncertainty surfaces (Explore agent, 2026-08-19)

Six categories searched exhaustively across `mobile/lib/`; full file:line
evidence in the agent transcript, summarized here:

1. **Equipment recognition** (`features/visual_equipment/`) — the richest
   vocabulary in the app: `VisualMatch.confidence` (raw softmax, never
   renormalised), `ScanOutcome` enum (`confident|alternatives|unknown|
   noEquipment|timeout|failed`), `ScanResult` (ranked candidate list +
   margin-based confident-vs-alternatives decision, NOT an absolute
   threshold — `confidentMargin = 0.15`, top1-vs-top2 gap), `LiveRecognition.
   settled` (tentative vs final reading), `TextAnchorMatch.confidence`
   (**explicitly documented as a different, non-comparable scale from
   `VisualMatch.confidence`** — `machine_text_anchor.dart:49`).
2. **Rep-count / weight withholding** (`features/workouts/`) —
   `SetCapture`'s `weightKg`/`reps` are `double?`/`int?` where **null means
   "declined to say," never coerced to 0** (`set_capture.dart:1-8`,
   enforced at parse time in `set_capture_sheet.dart:105-115`). A different
   axis from "the app doesn't know" — this is "the *user* chose not to
   answer."
3. **AI-generated content labels** — an `ai::`-prefixed id convention
   (`equipment_providers.dart:260-267`) plus a static disclaimer string on
   the AI coach sheet. This is **provenance/authorship, not confidence** —
   explicitly out of scope for an uncertainty model (see below).
4. **Safety/injury screening** (`features/equipment/state/
   safety_coverage_providers.dart`) — `SafetyScreeningLevel` enum
   (`none|rulesOnly|clinical`, a claim-strength ladder, not a score),
   per-region coverage fractions, fail-closed defaults on unresolved
   futures. Philosophically the closest existing precedent, but still fully
   domain-local.
5. **Form-check / posture** (`features/form_check/`, `features/posture/`) —
   `poseMatchScore()` returns `double?` where **null explicitly means
   "cannot tell," documented as categorically different from a low score**
   (`pose_target.dart:511-513`); `PoseGateVerdict` (6-value prioritized
   enum) collapsed by a pure mapping function into the coarser
   user-facing `CoachBlocker`; `CoachReadinessBand`
   (`widgets/coach_readiness_band.dart`) is the **one place in the app that
   already had to arbitrate between several independently-computed
   uncertainty signals that a real device screenshot caught contradicting
   each other** — the strongest existing precedent for multi-signal
   arbitration.
6. **`VideoFailureReason`** (`features/equipment/data/video_failure.dart`) —
   a third, independent reinvention of "name only what is known, never guess
   the reason" (`linkUnavailable|quotaExhausted|offline|playbackFailed` —
   corrected 2026-08-20, porting this gate to master: the original inventory
   above missed `quotaExhausted`, added to the real enum on 2026-08-18,
   before this note's own 2026-08-19 date).

**Confirmed: no shared type exists.** A direct search of `lib/shared/` and
`lib/core/` for `Confidence`/`Uncertainty`/`AmbiguityLevel`/`Ambiguous`
returned zero hits. Every one of the six mechanisms above was designed
independently, in its own feature folder, with its own shape (nullable
field, enum, ranked list, hardcoded string).

**The load-bearing finding:** `ScanOutcome`, `PoseGateVerdict`→`CoachBlocker`,
and `VideoFailureReason` independently converge on the *same* underlying
idea — a prioritized, closed-set "why can't I give you one confident
answer" enum, with absence/null as a first-class non-answer, never a
fabricated value — without ever referencing each other. That three-times
convergence, not any one existing system, is the actual evidence for what a
shared layer should capture.

**Explicitly ruled out as a fit, with reasons:**
- **A universal numeric confidence score.** The codebase's own authors
  already rejected this once: `VisualMatch.confidence` and
  `TextAnchorMatch.confidence` are two *different* 0..1 scales living in
  the *same* feature, and the second is explicitly documented as "not a
  probability and must not be rendered as a percentage next to the
  classifier's softmax, which IS one." A cross-domain numeric model would
  repeat that exact mistake at a larger scale.
- **`BuddyMatchScore`** (`features/buddy/data/buddy_match.dart`) — a real
  0..1 score already in the app, but it answers "who is a good match for
  you" (a preference/ranking heuristic), not "how sure is the app of a
  fact." Surfaced explicitly so a future reader doesn't mistake it for
  epistemic uncertainty and fold it into this model by analogy.
- **`ScanResult`'s ranked-candidate-list shape.** "Confident value, or a
  reason why not" does not fit "here are 3 plausible candidates, you pick" —
  forcing the alternatives case into a single-value contract would either
  drop the list (losing real information) or misrepresent the shape. This
  case needs, and already has, its own richer type. Left untouched.

## DECISION — what Gate E actually ships, and what it deliberately does not

**Ships:** `Answer<T, R>` (`mobile/lib/shared/uncertainty/answer.dart`) — a
sealed, exhaustiveness-checked contract for exactly the shape that recurred
three times: either a confident `T` value, or an explicit `R` (a
domain-specific, closed-set reason enum — never a magic string, never a
number) for why there isn't one, with an optional, structurally-separate
`bestGuess` for the "possibly: X" tentative-reading case
(`LiveRecognition.settled == false` is the existing precedent for this
exact idea). `R` stays generic and domain-owned on purpose: `PoseGateVerdict`,
`VideoFailureReason`, and a future reason enum are different closed sets for
different failure modes, and unifying *those* into one enum would be the
same universal-model mistake one level down.

**Does not ship, deliberately: retrofitting any of the five existing
systems onto `Answer<T, R>` in this gate.** Each one is mature,
individually tested, and in three cases (visual_equipment, form_check,
safety screening) safety- or trust-adjacent with calibrated, evidenced
thresholds (`confidentMargin = 0.15`, `kPoseMatchPassing = 0.80`,
`_unsureBelow = 0.45`). Retrofitting them now, with no second/third real
consumer yet driving the need, would be exactly the large-blast-radius
change the "smallest independently verifiable change" principle warns
against — and none of the null-returning cases (`poseMatchScore`,
`MachineDescriber.describe()`, the posture signal functions) currently
carry an explicit reason at all, so adopting the contract there would mean
*inventing new reason taxonomies inside safety-adjacent code* as a side
effect of a governance gate, not a genuine behavioral improvement anyone
asked for. That is a decision for whoever next touches one of those
systems for its own reasons, with its own review — not a default outcome
of shipping a shared type.

This mirrors Gate D's D0 decision shape: the minimal safe seam is the
contract itself, proven by tests against a realistic shape, not a mandate
to migrate five independently-evolved systems in one pass.

## Independent review (2026-08-19)

One specialist (`type-design-analyzer`) — proportionate to a self-contained,
zero-existing-call-site change (R1 tier, one new file + its tests, per
global CLAUDE.md §6), rather than the 3-specialist panel Gate D used for a
much larger, multi-file, provider-wiring change.

**MAJOR, applied — unbounded `T`/`R` reopened the exact ambiguity the type
exists to close.** `sealed class Answer<T, R>` with no bound let `T` be
instantiated as nullable, at which point `Answer<String?, R>.confident(null)`
("I confidently know there is nothing") and an uncertain answer became
indistinguishable through `valueOrNull`, and an explicitly-passed
`bestGuess: null` became indistinguishable from an omitted one. **Fix:**
`sealed class Answer<T extends Object, R extends Object>` (and matching
bounds on both leaf subtypes and the extension) — a one-line-per-declaration
change, zero effect on any real usage (`int`, `String`, and enum `R` all
already satisfy `Object`). Verified directly: a temporary probe declaring
`Answer<String?, R>` was added to the test file and confirmed to fail
analysis with `type_argument_not_matching_bounds` before the fix would have
allowed it, then removed — the bound is enforced by the compiler itself, so
no runtime regression test was added (there being no runtime behavior to
regress; the repo has no existing "must not compile" test convention to
extend for a single narrow bound).

**MINOR, not applied, explicitly deferred (reviewer's own recommendation)**
— `ConfidentAnswer<T,R>`'s `operator==` is stricter about the phantom `R`
type argument than its `hashCode` is (two confident answers with equal
`value` but different `R` compare unequal yet can hash-collide — not a
hash-contract violation, since only equal→equal-hash is required). The
reviewer explicitly recommended no action "unless this type is later used
in a more dynamic/mixed-domain context" — there are zero call sites today,
so deferred rather than added defensively.

Re-verified after the fix: `flutter analyze` clean on both files, full
suite 2459/2459 (2445 before Gate D's own tests + 14 new for this gate).
