# CT-1 — Content QA

**Started 2026-08-17.** The first operational milestone of the ML programme, and the first thing in
it that runs.

```text
CT-1_STATUS                       = BASELINE_READY
CONTINUOUS_RETRAINING_OPERATIONAL = NO
```

Both answers are proven below rather than asserted.

---

## What exists

Four executable components under [scripts/ct1/](scripts/ct1/), 29 tests, and a built dataset.

| | |
|---|---|
| [scripts/ct1/label_contract.py](scripts/ct1/label_contract.py) | The six label kinds, enforced at construction |
| [scripts/ct1/baseline.py](scripts/ct1/baseline.py) | The deterministic champion |
| [scripts/ct1/build_dataset.py](scripts/ct1/build_dataset.py) | Reproducible dataset builder |
| [scripts/ct1/evaluate.py](scripts/ct1/evaluate.py) | Metrics, and the gap where metrics cannot go |
| [scripts/ct1/test_ct1.py](scripts/ct1/test_ct1.py) | 29 tests |

```bash
python scripts/ct1/baseline.py
python scripts/ct1/build_dataset.py
python scripts/ct1/evaluate.py
python -m pytest scripts/ct1/test_ct1.py -q
```

## Maturity, against the states the brief defines

```text
DESIGNED                          done
DATASET_READY                     done   content_qa_catalogue v1, 1,887 rows
BASELINE_READY                    done   deterministic champion, registered
TRAINING_REPRODUCIBLE             n/a    nothing is trained yet
EVALUATION_READY                  NO     EVALUATION_LABEL_GAP -- zero reviewed labels
CHALLENGER_READY                  NO
SHADOW/ADVISORY_READY             NO
CONTINUOUS_RETRAINING_OPERATIONAL NO
```

The jump this deliberately does not make is architecture straight to operational. Everything above
`EVALUATION_READY` is blocked on one thing, and it is not code.

---

## The label ontology

Six kinds, ordered by authority. The order is **not** a confidence scale — an `OBSERVATION` is the
most certain thing in the pipeline and the least authoritative. What rises is who is entitled to be
wrong.

```text
OBSERVATION                 a measured property of the row. Cannot be incorrect.
AUTO_HEURISTIC_FLAG         a deterministic rule fired.
MODEL_PREDICTION            an opinion. Never a target, never evidence.
HUMAN_REVIEWED_QA_LABEL     a person's verdict on content quality.  <- first trainable kind
DOMAIN_REVIEWED_LABEL       a movement professional's verdict.
CLINICALLY_VALIDATED_LABEL  a named clinician's verdict.  <- UNREACHABLE HERE
```

Three rules are enforced in code, not described:

1. **`MODEL_PREDICTION` can never be a training target.** A predicted class becoming its own label
   is the failure that still reports excellent metrics — the model has learned to agree with itself,
   and the only trace is provenance nobody kept.
2. **`AUTO_HEURISTIC_FLAG` can never be a training target either.** Training on the rules produces a
   slower, less precise, unexplainable copy of rules that already run exactly. A challenger has to
   beat the baseline, and it cannot do that by imitating it.
3. **`CLINICALLY_VALIDATED_LABEL` cannot be constructed at all.** It raises. The member exists so the
   absence is representable and so no lesser label can be quietly promoted into meaning it. D1, H3.

A reviewed label without a reviewer identity raises; a machine label *with* one also raises, because
a heuristic flag with a person's name beside it reads exactly like a review.

## Dataset — `content_qa_catalogue v1`

```text
rows       1,887 included, 0 excluded
splits     1,501 train · 386 holdout
hash       09522b126a0ab1e550c6b9f81b7c8d514ed57928e7edc8990db4dfd18a21d1ee
commit     recorded per build in the manifest
images     none. personal data: none.
```

Reproducible in two separate senses, and the distinction matters:

**Deterministic.** No clock, no RNG, no set-iteration order reaches the output. The split assigns
each row by hashing its stable id, so adding rows tomorrow cannot reshuffle rows already assigned —
the failure mode of a seeded `shuffle`, which is reproducible for a fixed corpus and silently is not
the moment the corpus grows.

**Attested.** `dataset_hash` covers the content and excludes the manifest's own timestamp, because a
hash that moves when nothing moved cannot prove anything. Tested both ways: two builds agree, and a
one-word change to a title does not.

CI compares a rebuild against the **committed** manifest, not against a second run in the same job —
two runs agreeing proves determinism, not that the artefact in the repository is the one this code
produces.

## Baseline — the champion is a rule set

Measured against the shipped catalogue:

```text
1,664 findings over 836 rows (44.3% of the catalogue)
  1,400 OBSERVATION
    264 AUTO_HEURISTIC_FLAG
```

| findings | check |
|---:|---|
| 451 | `primaryMuscles` present but empty |
| 407 | `tips` absent |
| 359 | `contraindications` absent |
| 216 | duplicate `summary` |
| 182 | `muscles` present but empty |
| 45 | duplicate `steps` block |
| 3 | duplicate `title` |
| 1 | `contraindications` present but **empty** |

Zero dangling equipment references, zero tags outside the nine-region vocabulary, zero locale gaps,
zero duplicate ids.

Two results worth reading rather than skimming:

**That last row is a third state.** 359 rows have no `contraindications` key; one has the key with an
empty list. "Nobody has tagged this" and "somebody tagged it as having none" are different facts, and
the empty list is the only trace in the entire catalogue that a decision was made. Collapsing them
would erase it. `core/review/CLINICAL_VALIDATION_HANDOFF.md`'s 1,527/360 split is correct precisely
because it counts truthiness rather than key presence.

**`difficulty` is degenerate.** 1,877 of 1,887 rows say `beginner` — 99.5%. A field that says one
thing about almost everything is carrying no information, whatever it was meant to carry. It is
reported as a corpus-level observation rather than as 1,877 labels, because filing it per row would
bury every real finding underneath it.

**216 duplicate summaries and 45 duplicate steps blocks are real content defects**, and they are the
kind a reviewer can act on immediately.

### What the baseline deliberately cannot do

Absent by design, and this is the gap a challenger exists to fill:

- steps that contradict the title
- a description promising equipment the row does not use
- cues unsafe in wording without making a clinical claim
- a translation that is fluent and is not a translation of this row
- instructions that are correct, for a different movement

None of these can be written as a rule. Everything that *can* be is already exact.

## Evaluation — `EVALUATION_LABEL_GAP`

**Precision, recall and false-positive rate are not reported, and their absence is the finding.**

There are zero human-reviewed QA labels in this repository. Every number that could be computed would
be computed against the baseline's own output, which measures its agreement with itself — the same
loop the label contract forbids. Computing it here while forbidding it there would be a strange sort
of principle.

What is reported instead: coverage, queue shape per check, the checks that are exact by construction
(named so that *exact* is never read as *important*), and slice concentration.

For content QA the false positive is the expensive error — a pipeline that flags everything is a
pipeline nobody opens. The queue shape says so plainly: 451 rows for one missing field is not a
review queue, it is a migration, and it should be handled as one.

**What would close the gap:** a reviewed sample from the 386-row holdout split. Roughly 150–200
reviewed rows would make a challenger comparison meaningful; fewer would produce confidence intervals
wider than any difference worth acting on. Nothing else is blocking, and no amount of further code
substitutes for it.

## Champion / challenger

```text
CHAMPION   content_qa@baseline-v1   deterministic rules   ADVISORY_OFFLINE
CHALLENGER none
```

Registered in [core/ml/MODEL_REGISTRY.json](core/ml/MODEL_REGISTRY.json). The registry fence had to
grow for it, and what it grew is worth recording: the rule "not bundled implies not champion"
conflated *runs on the phone* with *is in charge*, which was correct only while every registered
model ran on a device. A model that runs offline can be the champion of its task and be in nobody's
APK. The guarantee that mattered is kept exactly — an `ON_DEVICE` champion must be bundled — and
every entry now declares where it runs, so the rule cannot silently exempt anything that forgets.

`training_code_commit` is **not** `UNKNOWN` here. It is `RECORDED_PER_BUILD`, and that token is
permitted only on a condition the fence enforces: the named evaluation report must exist and its
manifest must carry a real commit. A pointer that resolves to nothing would be worse than `UNKNOWN`,
because it claims provenance exists. Mutation-proven — setting the manifest's commit to `UNKNOWN`
turns the fence red.

Writing a literal commit into the registry was considered and rejected: the commit containing the
registry cannot be known while writing it. This programme already shipped that exact self-reference
once, in a report that stated its own final HEAD.

## Promotion — what it does and does not grant

```text
PROMOTED = an approved QA assistant whose output a human reads
```

It does not grant: editing content, approving exercises, writing to any catalogue or taxonomy, or
any claim about clinical safety. The champion has no write path to anything and promotion does not
create one — recorded as a guardrail metric in the registry rather than as an intention here.

First operational version is `READ_ONLY · ADVISORY · HUMAN_REVIEWED`. There is no evidence supporting
anything stronger, and there will not be until reviewed labels exist.

## Retraining eligibility

No trigger fires on time alone. All of these must hold together:

```text
>= 150 new HUMAN_REVIEWED_QA_LABELs since the last build
+ dataset rebuilds reproducibly (hash matches, CI-enforced)
+ the label contract passes (no machine label among the targets)
+ a taxonomy/schema change, a new content batch, measured degradation,
  or an explicit manual trigger
```

`CT != CD` is preserved and is not a matter of discipline here: retraining can only produce a
challenger, and promotion is a separate decision with a human in it. There is no path from a training
run to a replaced champion.

## Rollback

The baseline is deterministic and version-controlled, so rollback is reverting a commit. Any future
ML challenger's rollback target is this entry — the rules are the floor, and a challenger that cannot
clear them has nothing to offer.

## Privacy

```text
contains_images        false
contains_personal_data false
```

Both asserted by a test that scans the built dataset for `photo`, `image`, `camera`, `uid`, `email`,
`poster` and `video`, so adding any of them becomes a deliberate act with a red test in front of it
rather than a field somebody appends to the feature dict.

This is why CT-1 goes first. The scanner's CT loop is blocked on gym photographs leaving devices —
consent, retention, deletion propagating into training sets, whether embeddings would suffice. None
of those questions arise for a pipeline over text and structure, and the way to keep them not arising
is to never add the field. `PRODUCTION_IMAGE_COLLECTION = DISABLED` is untouched.

## Remaining blockers

1. **Reviewed labels.** ~150–200 from the holdout split. This is the only blocker on
   `EVALUATION_READY`, and it needs a person, not a commit.
2. **A challenger worth building.** Only after 1, and only for the judgement-shaped checks the rules
   cannot express. Building a classifier for anything already covered exactly would be a regression
   sold as progress.
3. **ML-2a**, unchanged and unrelated to CT-1: `D:/tools/equipment-model` is still not a git
   repository, which is why both scanner models remain `UNKNOWN`.

## What CT-1 does not touch

```text
D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED   unchanged
H3 = HOLD                                    unchanged
D3 = CLOSED                                  unchanged
PRODUCTION_IMAGE_COLLECTION = DISABLED       unchanged
CT != CD                                     unchanged
```

Automated content QA is not clinical review and cannot be substituted for it. A row this pipeline has
nothing to say about has not been checked — 56% of the catalogue is unflagged, and silence here means
"no rule matched", never "this row is fine".
