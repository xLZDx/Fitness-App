# ML strategy — from three unvalidated features to programme generation

**Status:** strategy, not a gate. No behaviour changes with this document.
**Replaces:** gate A7 of `PLAN_AUDIT_2026-08-11_REMEDIATION.md`, by operator
decision — *"пока пропускаем, но нужен детальный план/стратегия как довести МЛ
до ума и рабочего состояния, он необходим для составления индивидуальных
программ и тренировок"*.
**Written:** 2026-08-11, 17:28 local (Europe/Chisinau) / 14:28 UTC.

---

## 0. The one-paragraph version

Three ML features exist and none of them is validated. Equipment recognition
has a measured classifier that is worse than the OCR fallback sitting in front
of it; rep counting has accuracy numbers that were produced by a *different
algorithm* than the one that ships; posture computes front-facing metrics from
a side-on frame. The product goal — programmes built around what this person
can actually do — needs exactly one of these three to be trustworthy, and it is
the cheapest one. This document says which, why, and what has to be measured
before any of it is allowed to drive a plan.

---

## 1. What each feature actually measures today

Each row is what the code does, not what the UI implies. Sources are the
independent audit (`core/AUDIT_REPORT_2026-08-11.md` §5) and this project's own
measurements, both cited inline.

### 1.1 Equipment recognition — two anchors, and the weak one is the ML one

| Anchor | Status | What it does | Measured |
|---|---|---|---|
| `machine_text_anchor.dart` | shipped | Reads the machine's own printed name with ML Kit text recognition | **18/18** on the frames where a name is legible |
| Equipment classifier **v1** (10 classes, no abstention) | **SHIPPED** — the file in the APK | Bundled TFLite model behind ML Kit's labeler | B1: its three most confident answers on real gym photos were all **wrong**, up to `0.897` |
| Equipment classifier **v2** (29 classes + a trained `none`) | **NOT SHIPPED** | Exists at `D:\tools\equipment-model\`; the app does not load it | **top-3 5/18 (28%)**, abstained 10/30 |

> **Correction, 2026-08-17 (ML-F1).** This table previously described v2 as "the
> bundled TFLite model" and carried only its number. v2 has never been bundled:
> `mobile/assets/models/` holds exactly `README.md` and `equipment_v1.tflite`,
> and `asset_bootstrap.dart:20`, `mlkit_visual_equipment_service.dart:19` and
> `mlkit_live_equipment_service.dart:31` all name v1. The distinction matters
> because **the shipped model cannot abstain at all** — which is B1's finding
> that no confidence threshold repairs — while v2 can. Reading the old row, E2
> below looked partly solved for the shipped artefact. It is not started.
> See `core/ML_PLATFORM_ARCHITECTURE.md` §4.

Evidence: `core/plans/B5b_TEXT_ANCHOR_2026-08-07.md`,
`mobile/assets/models/README.md`, `D:\tools\equipment-model\gym_photos_truth.json`.
The sample is the operator's own 30 gym photos (`D:\Downloads\Photos-1-001 (1)`),
which are **test data and must never be trained on** — training on them buys a
slightly better model and destroys the only means of knowing whether it is
better.

The audit adds the failure mode the accuracy number hides: the model returns
**confident out-of-distribution errors up to `0.892`**, and the temporal
smoothing in `live_recognition.dart:29-96` checks that an answer *repeats*, not
that it is *right* or that the input belongs to any known class. A stable wrong
answer passes the smoother exactly as cleanly as a stable right one.
Live mode ships default-OFF (`live_equipment_providers.dart:41`), which is why
this is a feature-level blocker and not an app-level one.

### 1.2 Rep counting / Form Coach — the numbers measure something else

The MM-Fit evaluation (`scripts/pose/extract_mmfit_targets.py:104-136`) computes
**averaged bilateral 3D joint angles** and drives a **two-phase** counter.
Production (`rep_counter.dart:224-387`, thresholds in
`measured_rep_configs.dart:103-228`) uses **one side**, **2D** projections and a
**four-phase** counter.

This is not a small discrepancy to be corrected with a tolerance. Two of the
three differences change what is being measured:

- **3D → 2D** loses depth, so the same joint angle projects differently with the
  camera at a different yaw. A threshold tuned in 3D has no fixed 2D equivalent.
- **bilateral → one side** turns an average into a sample, and the visible side
  is the one the camera happens to face.
- **2-phase → 4-phase** changes what counts as a rep boundary at all.

So the accuracy figures are real measurements of a program that is not shipped.
They are not evidence about Form Coach, in either direction — the shipped
counter has never been measured.

### 1.3 Posture — geometrically incompatible inputs

`posture_metrics.dart:24-79` computes forward-head, shoulder symmetry and
pelvis symmetry from **one frame**. Forward-head genuinely requires a profile
view; shoulder and pelvis symmetry require a front-facing view. A single frame
cannot be both. Whichever the user gives, some of the reported numbers are
being read off the wrong projection, and
`measured_posture_config.dart:1-20`'s thresholds inherit that.

---

## 2. What "working" has to mean, for programme generation specifically

The product goal is not "recognise gym equipment". It is: **a plan whose
exercises this person can perform, on the equipment they can reach, at a load
that progresses.** That decomposes into three questions, and they do not need
equal ML quality.

| Question the planner asks | Feature | Cost of being wrong | Required quality |
|---|---|---|---|
| *What can they train on?* | Equipment recognition | An exercise in the plan the user cannot do — visible, annoying, self-correcting in one tap | **High precision, recall can be poor.** A confident wrong answer is far worse than "I don't know" |
| *Are they progressing?* | Rep counting | A wrong load recommendation — compounding, invisible | **Calibrated, or absent.** Manual entry is a fine substitute |
| *What must the plan avoid?* | Posture | A contraindicated exercise recommended to someone with a structural issue — a safety question | **Not on the path.** See §4.3 |

The asymmetry in that last column is the whole strategy. Only the first
question is on the critical path to individualised programmes, and it is the
one already closest to working — because its best anchor is not ML at all.

**Existing safety seam, unchanged by any of this:** every path that surfaces
exercises passes through
`mobile/lib/features/equipment/data/exercise_filter.dart`. Injury filtering is
a hard rule and ML output never bypasses it. A recognition result can only ever
*narrow* what the filter already allows.

---

## 3. The measurement path

Each step below is a gate: it produces a number, and the number either clears
the step or sends it back. The discipline is the cross-project one — **try to
kill every promising result before building on it**. A feature that "looks
good" on the 30 photos has not passed anything.

### 3.1 Common prerequisite — an honest held-out set (blocks everything else)

The project has one real-world sample: 30 photos, already used for the v2 vs
text-anchor comparison, therefore already partly burned as a selection set.

**Step M0.** Collect a second, independent set before any further modelling:

- ≥150 frames, ≥3 gyms not represented in the current 30, taken by a second
  person on a second phone model.
- Labelled by machine identity, plus a flag for *"the name is legible in
  frame"* — the text anchor's coverage is a product number in its own right.
- Include **deliberate negatives**: cardio machines, mirrors, benches, walls,
  people. This is the set that measures OOD behaviour, and it is the one the
  current 30 lack entirely.
- Stored beside `gym_photos_truth.json` with the same schema, never merged into
  it, never trained on.

Until M0 exists, every number below is unfalsifiable. It is the cheapest item
in this document and it blocks the rest.

### 3.2 Equipment recognition — the path that is actually short

**Step E1 — measure the anchor, not the model.** The product question is
"how often can we identify the machine at all", and the text anchor answers it
18/18 when the name is in frame. The unmeasured number is *how often the name is
in frame* across a real gym visit, which M0's legibility flag gives directly.
If that is ≥70%, the classifier is a fallback for the tail rather than the
primary system, and the strategy for the tail is different from the strategy for
the main path.

**Step E2 — add an "I don't know" output.** This is the highest-value change in
this document and it is not a model change. A closed-set classifier over 29
classes *cannot* say "not a machine I know"; it redistributes its probability
mass over the 29 and returns `0.892` on a mirror. Two mechanisms, in order of
cost:

1. A rejection threshold calibrated on M0's negatives, tuned for **precision at
   fixed recall**, not accuracy. Cheap, and it converts confident-wrong into
   silent, which is the behaviour the product wants anyway.
2. If (1) leaves too much on the table: a 30th "none of these" class trained on
   negatives. More work, needs training data, only justified by (1) failing.

**Correction, 2026-08-17 (ML-F1):** mechanism (2) is not hypothetical work —
**v2 already trained a `none` class** on mined negatives, four days before this
document was written, and it measurably fixed two of B1's confident errors (the
abduction machine went from `treadmill` 0.892 to `none` 0.808). It is not in the
product because v2 is not shipped. So E2's real content is narrower than written:
the open question is not "how do we build abstention" but "does v2's abstention
hold under viewpoint" — the README records the same abdominal machine reading
`treadmill` 0.940 from one angle and `none` 0.946 from another. That is an M0
measurement, not a modelling task. Mechanism (1) still applies to v1, which has
no abstention of any kind and is what users currently run.

**Step E3 — make the smoother check the right thing.** `live_recognition.dart`
currently rewards agreement across frames. Under E2 it should require *N frames
above the rejection threshold*, and should treat "below threshold" as
information rather than as a frame to skip. A stable rejection is a correct
answer.

**Step E4 — kill-attempt before shipping live mode.** With M0 held out and
parameters frozen: precision, recall, and the confident-error rate on negatives.
Ship live-by-default only if precision on the held-out set is ≥95% at whatever
recall falls out. A tuned-on-M0 number does not count; that requires a third
set or a pre-registered threshold.

### 3.3 Rep counting — decide the algorithm before measuring it

The current state is not "inaccurate", it is "unmeasured", and the fix is a
choice rather than a tuning exercise.

**Step R1 — pick one algorithm and delete the other.** Either:

- **(a) Bring production to the evaluated algorithm**: bilateral averaging, and
  the 3D landmarks ML Kit already returns (`PoseLandmark.z`, accuracy caveats
  and all). The existing MM-Fit numbers then apply, and the four-phase counter
  must be reconciled to two phases or re-evaluated.
- **(b) Bring the evaluation to production**: rewrite
  `extract_mmfit_targets.py` to project to 2D, take one side, and run the
  four-phase counter. Cheaper to write, and it measures what users have.

**(b) is the recommendation** — it costs one script rewrite instead of a
production-behaviour change, and it produces the number for the code that is
actually running. (a) becomes worth doing only if (b) measures badly *and*
attributes the loss to 2D specifically.

**Step R2 — measure per exercise, not in aggregate.** A single accuracy figure
across MM-Fit's exercise set hides that squat and shoulder-press fail in
different ways. `measured_rep_configs.dart` is already per-exercise; the
evaluation must be too, or the thresholds are being tuned against an average
that describes no exercise.

**Step R3 — do not let rep counts drive load until R1+R2 are green.** Manual
set logging already exists and is trustworthy. Progression driven by an
unmeasured counter is the one failure in this document that compounds silently.

### 3.4 Posture — off the path, deliberately

Posture cannot produce a defensible number from one frame, and fixing it means
a two-pose capture flow (front + side), each metric bound to the view that can
express it. That is a feature-sized piece of work whose output — a structural
assessment — sits closest to medical advice of anything in the product, and it
is *not* a prerequisite for individualised programmes: the health questionnaire
and injury filter already carry the constraints that matter for exercise
selection.

**Decision: posture stays experimental and does not feed the planner.** If it
is revisited, the first gate is the capture flow, not the metrics.

---

## 4. What ships in the meantime

Nothing in §3 blocks the product. What it blocks is *claiming* these features
work.

1. **Live equipment recognition stays default-OFF** until E4. Unchanged from
   today (`live_equipment_providers.dart:41`).
2. **The scanner, Form Coach and Posture carry an explicit "experimental"
   label** in the UI — this is audit recommendation 7
   (`AUDIT_REPORT_2026-08-11.md:360`) and the honest version of what the code
   does. It is a copy change, and it is the only piece of this document that
   should become a gate before release.
3. **Programme generation uses declared equipment, not recognised equipment**,
   until E4 clears. The user picks their gym's kit once; recognition is a
   convenience that pre-fills that list, with the user confirming.
4. **Progression uses logged sets.** Rep counting is a display, not an input.

That ordering means individualised programmes are *not* blocked on ML at all —
they are blocked on the equipment list, which a user can supply in a minute and
which recognition later makes faster. That is the point of §2's table: the ML
is an accelerator on a path that works without it, which is the only shape in
which unvalidated ML belongs in a shipping product.

---

## 5. Sequence and cost

| Step | Blocks | Rough size |
|---|---|---|
| **M0** held-out set with negatives | everything | half a day of collection, mostly not at a keyboard |
| **E2** rejection threshold | live mode | small — a threshold and its calibration |
| **E1** anchor coverage number | prioritisation | falls out of M0 for free |
| **E3** smoother rework | live mode | small |
| **E4** kill-attempt | shipping live mode | one measurement run |
| **R1(b)** re-evaluate production algorithm | any rep-driven feature | one script rewrite |
| **R2** per-exercise breakdown | threshold tuning | included in R1 |
| Posture capture flow | nothing on this path | feature-sized, deferred |

The critical path to "ML helps build individualised programmes" is
**M0 → E1/E2 → E3 → E4**, and every one of those is small. The expensive items
in this document are the ones deliberately not on it.

---

## 6. What this document does NOT authorise

No gate is opened here. Anything in §3 needs its own GO. In particular: no
training run, no new model artifact, no change to
`live_equipment_providers.dart:41`, and no relabelling of the 30 test photos
into a training set.
