# First continuous-retraining candidate — scored decision

**Decided 2026-08-17.** Status: `FIRST_CONTINUOUS_RETRAINING_CANDIDATE = equipment_recognition`,
**with a prerequisite that is not a model problem**.

The instruction was not to assume the scanner wins. It is compared below against three alternatives
on eleven criteria, and it does win — but the honest result is that the winner is currently blocked
on data collection, and a non-ML candidate delivers value before any of them.

---

## Candidates

| | Description |
|---|---|
| **A — Equipment recognition** | The scanner classifier. `equipment_v1` bundled, `equipment_v2` trained and unshipped. |
| **B — Recommendation ranking** | `rankedForYouProvider` and the programme builder's `rank` permutation callback. |
| **C — Search / catalogue ranking** | Ordering within a machine's exercise list. |
| **D — Content QA prioritisation** | Ranking missing catalogue content by how often users actually meet the machine. |

---

## Scoring

`0` = absent/blocking · `1` = weak · `2` = adequate · `3` = strong. Justification per cell in the
notes below; nothing here is scored on impression.

| Criterion | A scanner | B recs | C search | D content QA |
|---|---|---|---|---|
| Business value | 3 | 3 | 1 | 2 |
| Existing data | 2 | 0 | 0 | 3 |
| Label quality | 2 | 0 | 0 | 3 |
| Offline evaluation | 3 | 1 | 1 | 3 |
| Online evaluation | 1 | 0 | 0 | 2 |
| Safety risk (3 = lowest) | 3 | 2 | 2 | 3 |
| Privacy risk (3 = lowest) | 0 | 2 | 3 | 3 |
| Implementation cost (3 = cheapest) | 1 | 1 | 2 | 3 |
| Rollback simplicity | 3 | 3 | 3 | 3 |
| Model maturity | 3 | 0 | 0 | 3 |
| Time to useful feedback | 2 | 1 | 1 | 3 |
| **Total (max 33)** | **23** | **13** | **13** | **31** |

---

## Notes on the cells that decide it

**Existing data.** A scores 2 because `recognised_equipment` and `machine_cards` already persist
what the model decided and what the user did about it. B and C score **0** — there is no product
telemetry at all (`debug_telemetry.dart` is debug-builds-only by explicit design and the privacy
policy promises no analytics SDK), so there is no impression log, no click stream and no way to
learn a ranking. That single zero is what removes B and C from contention, and it is a privacy
decision rather than an engineering gap.

**Label quality.** A has a real correction path: a user who is shown the wrong machine can say so,
which is a `VERIFIED_LABEL`. D's signal is `machine_cards.timesSeen` — an explicit count of how
often users met a machine the catalogue could not name. B and C would have to infer intent from
behaviour that is not recorded.

**Privacy risk.** A scores **0**, the only zero in its column, and it is the finding of this
analysis. Retraining a scanner needs photographs of gyms, which means camera images leaving the
device — the most sensitive collection this product could add, and squarely against the current
policy. **This is what blocks A, and it is not a modelling problem.**

**Safety risk.** A's failure mode is a wrong machine name, which the user sees and can correct. B's
is a worse-ordered but still eligibility-filtered list — the `rank` callback is a *permutation*, so
it cannot introduce an unsafe exercise. None of the four can reach clinical territory, and none is
allowed to.

**Model maturity.** A has a measured baseline (v1 and v2 both evaluated against real gym photos), a
registry entry, a documented leakage bug the pipeline now raises on, and a licence-filtered corpus.
B and C have no model at all.

**Time to useful feedback.** D wins because it needs no model: rank the gap by `timesSeen` and read
the answer the same day.

---

## Decision

```text
FIRST_CONTINUOUS_RETRAINING_CANDIDATE = A (equipment_recognition)
FIRST_DELIVERABLE                     = D (content QA prioritisation)
```

Two different things, and collapsing them would be the mistake.

**A is the right first CT pipeline.** It is the only candidate with a model, a baseline, a bounded
label space, a correction path and a failure mode a user can see. `ML_STRATEGY §3.2` reached the
same conclusion from the model-quality side, and this analysis reaches it from the platform side.

**A is not startable today**, and the blocker is not `M0`. Even with a held-out set collected,
continuous retraining means continuous data, and continuous data means gym photographs leaving
devices. That requires:

- an operator decision on the privacy policy (the same §0 decision that blocks ML-1);
- a consent design;
- retention and deletion, including deletion propagating into training sets;
- a decision on whether **embeddings suffice instead of raw images** — genuinely open, and the
  answer that would most reduce risk.

Until those exist: `PRODUCTION_IMAGE_COLLECTION = DISABLED`, and it stays disabled by default.

**D scores higher than A and is deliberately not called the CT candidate**, because it is not
continuous retraining — it is a ranked query over data already collected, with no model, no
promotion gate and no privacy consequence. It is listed as the first deliverable because it produces
value in days and feeds the corpus gap the model README already names as the one that matters
(`ab_crunch_machine`, 31 crops — the machine the shipped model calls `treadmill` at 0.940).

---

## Next executable CT milestone

Not "start retraining". In order:

1. **ML-2a — bring the training pipeline under version control.** `D:/tools/equipment-model` is not
   a git repository (verified), so `training_code_commit` is `UNKNOWN` for both registered models
   and neither can be regenerated by anyone who does not hold that directory. This is the cheapest
   item in the whole ML programme and it blocks every reproducibility claim.
2. **ML-2b — version and hash the datasets** already used, so v1 and v2 become reproducible rather
   than merely recorded.
3. **M0** — the independent held-out set with negatives (`ML_STRATEGY §3.1`), unchanged.
4. **ML-5 — the evaluation gate** (§22 criteria: per-class recall, calibration, OOD handling,
   confident-false-identification rate), so that a candidate can *fail*.
5. Only then a challenger, and only then shadow.

Step 1 is executable now, requires no decision from anyone, and is a directory and a `git init`.
That is the next thing to do.

---

## What this does not authorise

D3 stands: nothing here permits shipping v2. No image collection is enabled. No model is promoted.
Retraining infrastructure is not evidence about any model, and none of this touches D1 or H3.
