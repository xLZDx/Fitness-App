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

Nine executable components under [scripts/ct1/](scripts/ct1/), 155 tests, a built dataset and a
built review batch.

| | |
|---|---|
| [scripts/ct1/label_contract.py](scripts/ct1/label_contract.py) | The six label kinds, enforced at construction |
| [scripts/ct1/baseline.py](scripts/ct1/baseline.py) | The deterministic champion |
| [scripts/ct1/build_dataset.py](scripts/ct1/build_dataset.py) | Reproducible dataset builder |
| [scripts/ct1/evaluate.py](scripts/ct1/evaluate.py) | Metrics, and the gap where metrics cannot go |
| [scripts/ct1/review_batch.py](scripts/ct1/review_batch.py) | Blind stratified batch + reviewer assignments |
| [scripts/ct1/review_app.py](scripts/ct1/review_app.py) | The self-contained page a reviewer opens |
| [scripts/ct1/review_import.py](scripts/ct1/review_import.py) | Import refusals, agreement, adjudication |
| [scripts/ct1/human_eval.py](scripts/ct1/human_eval.py) | `CT1_HUMAN_EVAL_V1` + the stratified estimator |
| [scripts/ct1/leakage_guard.py](scripts/ct1/leakage_guard.py) | Split disjointness and training-label origin |

```bash
python scripts/ct1/baseline.py
python scripts/ct1/build_dataset.py
python scripts/ct1/evaluate.py
python scripts/ct1/review_batch.py --out core/ml/review
python scripts/ct1/review_app.py --batch core/ml/review/ct1_review_batch_002
python -m pytest scripts/ct1/ -q
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

## `CT1_REVIEW_BATCH_002` — the batch that would close it

Built by [scripts/ct1/review_batch.py](scripts/ct1/review_batch.py), written to
[core/ml/review/ct1_review_batch_002/](core/ml/review/ct1_review_batch_002/), and asserted by
[scripts/ct1/test_review_batch.py](scripts/ct1/test_review_batch.py) — one of five CT-1 suites in CI
(155 tests total).

**Why 002 and not a rebuilt 001.** Review schema v2 adds structured reason codes, a per-row content
digest, review timestamps and an explicit review status. A v1 answer cannot carry any of them, so
reading a v1 submission as v2 would be guessing what the reviewer meant. 001 was built, committed and
never reviewed, so nothing was lost — which is exactly the situation in which the rule is cheap to
waive, and waiving it the first time it costs anything is how it stops being a rule. The row
SELECTION is unchanged, and a test proves it by rebuilding against the committed `001/items.json`, so
the supersession is provably schema-only. 001 is recorded as `SUPERSEDED_BEFORE_REVIEW`.

**The batch is BLIND, and everything else about it follows from that.** A reviewer who can see which
rule fired is not producing a label; they are producing an agreement rate, and an agreement rate
trained on is exactly the feedback loop the label contract refuses at the training step. Refusing it
there and then handing reviewers the machine's output would be refusing it in the one place it cannot
happen. So `items.json` carries the catalogue content a person needs and no label, flag, score or
hint. The baseline's own labels for the same rows go to `sealed_baseline_labels.json`, which exists
so the batch can be evaluated afterwards and is not part of what a reviewer opens.

**Sampling — stratified, and the manifest says so.**

```text
holdout rows          386
flagged available      56   (every flagged holdout row is in the batch)
unflagged available   330 -> 124 selected
batch                 180   flagged_exhausted = true, backfilled = true, short = false
double review          44   (~20%)
packages              R1 69   R2 81   R3 74
```

A batch drawn at random from the holdout would be ~86% unflagged and would measure the rules'
precision on a handful of rows while saying nothing about what they MISS. A batch drawn only from
flagged rows would measure precision exhaustively and could not, even in principle, discover a missed
row. So both strata are drawn deliberately, flagged rows are spread across check families, and
`manifest.sampling` states in the file that any rate computed on it describes THIS batch.

`flagged_wanted` (120) and `flagged_available` (56) are recorded separately on purpose: the shortfall
is a property of the corpus, not a failure of the sampler, and when the whole flagged population fits
the precision measurement is exhaustive for the holdout rather than a sample of it. The shortfall is
backfilled from the other stratum and `backfilled` records that it happened — an earlier version
returned a silently short batch, which a test caught.

### The interface a reviewer opens

[scripts/ct1/review_app.py](scripts/ct1/review_app.py) generates one self-contained HTML page per
reviewer slot (`app/review_R1.html` and siblings). No server, no build step, no network — a review
tool that needs infrastructure to run is a review tool that does not get run, and this whole gate is
blocked on the work actually being done. Answers autosave to `localStorage`; Export produces a
submission file the importer validates.

The page is where blindness either holds or fails, because it is the only artefact a reviewer
actually opens. [scripts/ct1/test_review_app.py](scripts/ct1/test_review_app.py) scans the RENDERED
BYTES — not the payload builder — and asserts the page names no rule the baseline can produce (the
vocabulary is derived from `run_checks`, so a rule added later is covered without anybody remembering
to add it), carries no verdict/score/prediction word, mentions no other reviewer slot, contains only
the rows its own slot was dealt, and nowhere reveals that a row is double-reviewed.

That last one matters more than it looks: a reviewer who knows a row is also going to somebody else
answers it differently — more carefully, or less, but not the same — and the agreement figure then
measures the marking rather than the labelling. So `double_review` is not on the item at all; the
assignment layer knows and the item does not.

Assignments are deterministic from the batch (`assignments.json`), so a lost package is regenerated
rather than reconstructed from somebody's memory of who had what. The second reviewer of a doubled
row is never its first. CI rebuilds the batch and compares, so drift in either surfaces as a failure.

Procedure for reviewers: [core/ml/review/REVIEW_INSTRUCTIONS.md](core/ml/review/REVIEW_INSTRUCTIONS.md).

### What a reviewer is asked

Eight questions, each a comparison between two things visible on the page:
`title_matches_content`, `content_is_complete`, `structure_is_consistent`,
`instructions_are_consistent`, `content_is_not_duplicated`, `equipment_matches_content`,
`localisation_is_faithful`, `metadata_matches_content`. Verdicts are `ok` / `problem` / `unsure`.

A `problem` requires at least one code from a closed vocabulary of sixteen; an uncoded problem cannot
be counted, compared between reviewers, or acted on. `other` requires a note, so an incomplete
vocabulary shows up as a countable category rather than as reviewers forcing a near-miss code. The
codes are shown identically on every row, so they carry no information about any particular row —
which is what keeps them compatible with blindness. A test asserts no code is named after a baseline
rule.

`unsure` is not politeness. Forcing a verdict on a row a reviewer cannot assess manufactures a label,
and a manufactured label is indistinguishable from a real one once it is in the file. It imports as
an abstention and never as a class.

**No question asks whether an exercise is SAFE.** That is clinical authority, unreachable from this
repository by construction, and a question that invites the answer is how a content label gets read
as a clinical one. Asserted twice: on the question NAMES, and on the PROSE a reviewer actually reads,
which is where the smuggling would happen. `needs_domain_review` routes a row OUT of content QA to
someone qualified; it is not a verdict and cannot become one.
`D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED` and `H3 = HOLD` are untouched and cannot be closed by
any label in this batch.

### What the importer refuses

[scripts/ct1/review_import.py](scripts/ct1/review_import.py), asserted by
[scripts/ct1/test_review_import.py](scripts/ct1/test_review_import.py). Each refusal is a case where
the alternative is a label that looks exactly like a good one:

- a submission for another batch, or under the previous review schema;
- a missing or machine-shaped reviewer identity, or a `reviewer_kind` that is not the literal `HUMAN`;
- a review of a row nobody was asked about, or a row assigned to a different slot — importing it adds
  an unplanned reviewer and changes what that row's agreement figure measures;
- the same row twice in one submission, conflicting or identical: which entry is the review is a
  question the file cannot answer;
- a timestamp that is malformed, or naive — an instant with no offset cannot be ordered against a
  catalogue edit, which is how staleness is judged;
- a partially answered row, an answer to a question that was not asked, a verdict word outside the
  three, a reason code outside the vocabulary, a `problem` with no code, `other` with no note;
- a `SKIPPED` row carrying answers.

**Content that moved under the reviewer** is the one case that is neither imported nor rejected. Each
item carries a digest of exactly the fields it showed; a mismatch means the reviewer judged text that
is no longer there, and the row comes back as `STALE / RE_REVIEW_REQUIRED` — reported, not silently
dropped, because a dropped row is indistinguishable from one that was never assigned.

**A row nobody returned is `NOT_RETURNED`**, which is an UNKNOWN and never "reviewed, nothing found".
The coverage account keeps `COMPLETE`, `SKIPPED`, `STALE` and `NOT_RETURNED` distinct.

**What none of that establishes.** No file format can show that a reviewer is a person.
`reviewer_kind` records a CLAIM, and the machine-identity blocklist catches the specific cheap
mistake of putting a tool's name in the field — a determined mislabel would pass. The protection that
actually holds is procedural: a label is trainable only when a named human took responsibility for
it, and no agent, model or heuristic in this repository may enter that name.

### Double review and adjudication

~20% of the batch goes to a second reviewer. `agreement()` reports raw agreement AND Cohen's kappa,
per question and overall, because raw agreement on a corpus where almost everything is fine is high
by construction: 95% agreement between two people who both answered `ok` to everything is not
evidence that either was reading. Kappa is `null` where it is undefined rather than 0 or 1 —
substituting a value turns "not measurable" into a measurement.

`adjudicate()` assigns every reviewed (item, question) one explicit state:

```text
SINGLE                  one reviewer was asked
AGREE                   two reviewers, same answer
DISAGREE_UNADJUDICATED  two reviewers differ, nobody has ruled
ADJUDICATED             a third reviewer recorded a decision
UNRESOLVED              adjudication was attempted and reached no decision
NEEDS_DOMAIN_REVIEW     routed out of content QA
```

There is no automatic tie-break. Majority-wins and first-reviewer-wins are both a machine deciding
which human was right, and either would let the corpus contain a "human label" no human agreed to.
An adjudicator may not be one of the two parties, may not be anonymous, and may not be machine-shaped.
`DISAGREE_UNADJUDICATED` is a queue, not a result; only `AGREE` / `ADJUDICATED` / `SINGLE` carry a
value into the evaluation set.

### `CT1_HUMAN_EVAL_V1` and the three rates

[scripts/ct1/human_eval.py](scripts/ct1/human_eval.py) builds the immutable evaluation dataset and
computes the baseline's metrics against it.

The dataset carries its own provenance — batch, commits, catalogue digests, review schema, reviewers,
adjudication counts, coverage — and, less usually, everything it EXCLUDED and why: unadjudicated
disagreements, partly settled rows, stale rows, domain-review referrals. A dataset that lists only
what it contains cannot be audited for selection bias, because the rows somebody dropped are exactly
the ones worth knowing about. A published version is never overwritten; a correction is v2 with a
stated diff, so a number quoted last month still refers to something that exists.

`bad / 180` is not a defect rate. The batch over-samples flagged rows roughly sevenfold by design, so
three numbers are reported under three names that cannot be confused:

```text
BATCH METRIC      defective / reviewed.  True about THESE rows. Not prevalence.
HOLDOUT ESTIMATE  stratum rates re-weighted by the holdout population, with a
                  standard error. The flagged stratum was sampled exhaustively,
                  so it contributes zero sampling variance and nearly all the
                  uncertainty is honestly attributed to the 124-of-330 unflagged
                  sample.
CATALOGUE RATE    null, with the assumption written out. Getting from holdout to
                  catalogue needs a stated assumption this module will not make
                  silently.
```

An unsampled stratum makes the estimate `null`, not zero: its rate is unknown, and averaging over the
strata that happen to have data silently assumes the missing one looks like them.

Baseline check families and review questions are two vocabularies designed for different purposes, so
`CHECK_TO_QUESTION` states the join explicitly rather than assuming it. A family with no defensible
question — `unknown_contraindication_tag`, which a content reviewer cannot judge from the row — is
`UNMAPPED` and counted, not dropped.

### Leakage guards

[scripts/ct1/leakage_guard.py](scripts/ct1/leakage_guard.py), asserted by
[scripts/ct1/test_leakage.py](scripts/ct1/test_leakage.py) and mutation-proven.

`assert_split_disjoint` requires both splits non-empty and sharing nothing. Emptiness is checked
because it is the failure mode a disjointness test invites: two empty sets are disjoint, so a guard
that checks only the intersection passes loudest exactly when the split has stopped working.

`assert_trainable` refuses a machine-produced source — the self-training loop the label contract
already covers — and, the case that contract cannot see, a HUMAN label on a HOLDOUT row. That is the
dangerous one: it is a perfectly valid human label, it passes every existing check, and training on
it destroys the only evaluation this project has. Every label the importer produces carries
`evidence.split`, so the guard refuses it without being handed a second file — a guard that needs a
second file is a guard somebody will call without it.

The guard deliberately has NO check for "a reviewed label with no named reviewer": `Label.__post_init__`
makes that object impossible to construct, so a check here could never fire, and a branch that cannot
fail is a branch nobody knows is disconnected. A test asserts the contract instead.

`report()` returns counts alongside the verdict, and states what it does NOT prove — it is structural
only, and says nothing about a feature derived from the whole corpus, a threshold tuned against
holdout results, or a rule written after looking at holdout rows.

**Status.** The batch is BUILT and UNREVIEWED. `EVALUATION_LABEL_GAP` remains OPEN and closes only
when reviewed labels come back and are imported. Nothing in this section is evidence about the
baseline's precision or recall.

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
manifest must carry a commit that **resolves in this repository**. A pointer that resolves to
nothing would be worse than `UNKNOWN`, because it claims provenance exists.

The contract, stated exactly (R-05 tightened it — the first version checked that the recorded value
*looked* like a sha, which `deadbeefdeadbeefdeadbeefdeadbeefdeadbeef` also does):

```text
RECORDED_PER_BUILD  requires  git cat-file -e <manifest.source_commit>^{commit}  ->  0
```

Three things it deliberately does **not** require. The commit need not be an ancestor of `HEAD`: a
manifest built on a branch that was later rebased still records where it came from honestly, and
demanding reachability would push the next person to rewrite the manifest instead of keeping it
true. It is not a claim that the *artefact* was rebuilt at that commit — only that the revision the
builder read its inputs at is a real one. And it says nothing about the training code being any
good; provenance is not quality.

Because the check needs history, `.github/workflows/flutter.yml` pins `fetch-depth: 0` on the job
that runs the suite; a shallow checkout carries one commit and could never resolve the pointer.
`mobile/test/ci/workflow_gates_test.dart` asserts that depth, so removing it fails rather than
silently disarming the provenance check.

When git cannot answer at build time, `scripts/ct1/build_dataset.py` writes `UNKNOWN` — never a
plausible-looking placeholder — and the fence then rejects the `RECORDED_PER_BUILD` claim outright.

Mutation-proven three ways: a hex-shaped commit that names nothing turns the registry fence red;
removing `fetch-depth: 0` and commenting it out both turn the workflow fence red.

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

1. **Reviewed labels.** `BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED`. 180 rows from the holdout split,
   dealt into three packages, with the interface, the instructions, the importer, the adjudication
   workflow, the evaluation-dataset builder, the metrics pipeline and both leakage guards built and
   tested around the gap. This is the only blocker on `EVALUATION_READY`, and it needs a person, not
   a commit. It is a legitimate external-input boundary: everything downstream of it is ready and
   nothing downstream of it can be honestly simulated.
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
