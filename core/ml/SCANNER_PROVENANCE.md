# Equipment scanner: what is actually known about each model

`scripts/ml/scanner_provenance.py` pins the BYTES — six artefacts and two corpora, with digests it
re-verifies against disk. This file is the other half: field by field, what is a measured fact, what
is derived from one, what is genuinely unknown, and what the evidence contradicts.

The distinction ML-2a exists to preserve is that the scanner corpus was never lost. It is
**unversioned**, which is a different problem with a different fix. Nothing below should be read as
restoring the earlier "missing" language.

Measured 2026-08-18 against `D:/tools/equipment-model` (not a git repository — verified: no `.git`
at that path or above it).

Legend: **FACT** = read from bytes on disk. **DERIVED** = computed from a fact, with the derivation
named. **UNKNOWN** = not determinable from any evidence available here. **CONTRADICTED** = two
sources disagree and neither has been shown to be authoritative.

## v1 — `equipment_v1.tflite`, CHAMPION, bundled in the app

| Field | Basis | Value |
|---|---|---|
| Shipped artifact | FACT | `mobile/assets/models/equipment_v1.tflite`, 4,496,661 B, sha256 `6f159ec3…e696e3` |
| Pipeline output | FACT | `D:/tools/equipment-model/out/equipment_v1.tflite`, same size, same sha256 |
| **Shipped == built** | **DERIVED** | The two digests above are equal. This is the single fact that makes v1 recoverable rather than merely documented: the APK's model is the recovered pipeline's output, byte for byte. |
| Trainer | FACT | `train_export.py`, 6,656 B, sha256 `2424fea9…1596ac` |
| Architecture | FACT | MobileNetV2 transfer learning (`train_export.py:58-59`) |
| Seed | FACT | `SEED = 20260729` (`train_export.py:22`) |
| Hyperparameters | FACT | `IMG = 224`, `BATCH = 32` (`:20-21`); `validation_split=0.15` (`:38`); 10 epochs head (`:79`) then 6 fine-tune (`:88`) |
| Label set | FACT | `out/labels.txt`, 117 B, sha256 `ff51b4a9…4c99fd`; 10 classes, order enforced by `class_names=LABELS` (`train_export.py:33`) |
| Dataset | FACT | `dataset/`, 1,741 files across 10 class directories |
| Dataset digest | FACT | corpus manifest sha256 `411189bc…08e2b6`, algorithm defined at `scripts/ml/scanner_provenance.py:131-148` |
| Evaluation report | FACT | `mobile/assets/models/README.md` — genuine measurement (n=30 gym photos, per-class top-1/top-3 table, abstention counts) |
| Metrics | FACT | `top_1 = 0.617`, `top_3 = 0.835` (`core/ml/MODEL_REGISTRY.json:90-93`) |
| **Training log** | **UNKNOWN** | **Absent.** The only `.log` under the pipeline root is `train_v2.log`. Nothing records the actual v1 run: no loss curve, no wall-clock, no environment. |
| Training code commit | **UNKNOWN** | The pipeline has never been in version control. This must stay UNKNOWN — see below. |
| Dependency pin, HISTORICAL | **UNKNOWN** | No `requirements*.txt`, `*.toml` or lockfile at the pipeline root, and none existed when v1 was trained. What versions the 2026-07-29 run used is not determinable from anything here, and a pin captured in 2026 cannot reach backwards to answer it. |
| Dependency pin, RECOVERED | FACT | `core/ml/pins/ml_train_env_recovered_2026-08-18.txt` — 58 packages frozen from `D:/tools/ml-train-env` while it was still intact. Reproduces v1's headline metric; does **not** establish the historical row above. |

**v1 is closable on every field except the training log and the HISTORICAL dependency pin.** Dataset, trainer,
architecture, seed, hyperparameters, label set, output artifact, shipped identity and evaluation are
all measured facts.

## v2 — `equipment_v2.tflite`, EVALUATED, NOT SHIPPED

| Field | Basis | Value |
|---|---|---|
| Artifact | FACT | `D:/tools/equipment-model/out_v2/equipment_v2.tflite`, 4,564,876 B, sha256 `d642effc…f74848`. Not in the repository. |
| Trainer | FACT | `train_v2.py`, 7,228 B, sha256 `81f79ac8…46603e` |
| Architecture | FACT | MobileNetV2 transfer learning, same as v1 (`train_v2.py:3`, `:81`) |
| Seed | FACT | `SEED = 1337` (`train_v2.py:36`) |
| Hyperparameters | FACT | `IMG = 224`, `BATCH = 32` (`:34-35`); `validation_split=0.15` (`:73`); defaults 6 epochs then 4 fine-tune (`:98-99`) — **defaults, not a record of what was passed** |
| Label set | FACT | `out_v2/labels.json`, 774 B, sha256 `4bf5a41c…dee36d`, **37 entries** including a trained `none` |
| Dataset | FACT | `dataset_v2/`, 90,817 files; manifest sha256 `b228f198…16731e` |
| **Class count** | **CONTRADICTED** | See below. |
| Metrics | FACT | `top_3_real_world = 0.28` (`MODEL_REGISTRY.json:142-144`) |
| Training log | **CONTRADICTED** | `train_v2.log` exists but does not describe the registered artifact. |
| Training code commit | **UNKNOWN** | As v1. |

### The 29-vs-37 contradiction, and why it is not repaired

`train_v2.log` records a **29-class** run: `DROPPED 8 classes under 150 images -> dataset_v2_thin/`
(`:4`), `training 29 classes` (`:15`), `Found 54914 files belonging to 29 classes` (`:17`, `:21`).
The registered artifact's own `labels.json` carries **37** labels.

The decision log already records the mechanism: `train_v2.py` writes to a fixed output path, so a
later 37-class run landed on top of the earlier 29-class one. The log was not overwritten with it.

That makes the honest status **`train_v2.log` is the log of a superseded run, not of the registered
artifact** — so v2's training log is not merely missing, it is present and misleading, which is
worse. It is left in place and labelled rather than deleted or re-pointed: deleting evidence to
remove a contradiction is how a provenance record becomes fiction, and assigning the 29-class log to
the 37-label artifact would be inventing the very link that does not exist.

**Only new evidence may resolve this** — a 37-class training log, or a rerun. Not a choice between
the two numbers.

## What must never be written here

The pipeline was never in version control, so there is no commit that produced either model. The
registry says `"training_code_commit": "UNKNOWN"` for both, and that is the correct value, not a gap
to be filled.

If the recovered pipeline is ever snapshotted into a repository, the first commit is a **recovery**
event and must say so — `RECOVERED_UNVERSIONED_SOURCE`, captured on a date, from a path, with the
historical training revision still UNKNOWN. A model that already exists was not trained by a commit
created after it. Historical training provenance and present recovery provenance are two different
facts and collapsing them would make this file worthless.

## Remaining external action

| Gap | What would close it | Who |
|---|---|---|
| Pipeline unversioned | A snapshot under the recovery semantics above, or a decision to keep it outside and rely on the pinned digests | operator — it is 92k dataset files and ~2 GB, and where that lives is theirs |
| v1 training log absent | Nothing. The run happened and was not logged. A rerun would produce a NEW log, not the original one | nobody — record as permanently unknown |
| v2 class-count contradiction | A 37-class training log, or a reproducible rerun | whoever holds the pipeline |
| Dependency pin absent | **CLOSED 2026-08-18** by `core/ml/pins/ml_train_env_recovered_2026-08-18.txt` -- the environment was still intact, so it was frozen. Recovered, not historical: see the note below | nobody, now |
| Bitwise reproducibility | Nothing. It is impossible by construction — see below | nobody |
| The v1 metadata step | A mediapipe/venv combination where the stub covers the code path | whoever holds the pipeline |


### The dependency pin, recovered 2026-08-18

The row above asked for a freeze of `D:/tools/ml-train-env` "which requires that environment to
still be intact". It was intact, so it was frozen:
`core/ml/pins/ml_train_env_recovered_2026-08-18.txt`, 58 packages, Python 3.11.9, sha256 of the
package list `6ae6e7db…`. `tensorflow-cpu==2.15.1`, `keras==2.15.0`, `numpy==1.26.4`,
`mediapipe==1.0.0` — the same versions this file already recorded as READ FROM the venv, now
recorded outside it.

What closed is narrow and should not be overstated. Until this, those versions existed in one
directory on one machine and nowhere else; a reinstall, a disk failure or a single unattended
upgrade would have destroyed the only description of what reproduces v1. The list now survives its
environment.

What did NOT close is the historical claim. Nothing establishes that these were the versions v1 was
trained with on 2026-07-29 — no pin file existed then, and writing one now cannot reach backwards.
That stays `UNKNOWN`. A recovered environment filed as though it were the original pin is precisely
the substitution this document exists to prevent, so the file says so in its own header rather than
relying on this paragraph being read.

## Where the pipeline should live — decision package (2026-08-18)

The row above says the pipeline is unversioned and that where it lives is the operator's. That was
true and unhelpful: it named an owner without giving them anything to decide. This is the package.

### The measurement that settles the scope

1,741 + 90,817 = **92,558** — the two image corpora account for the entire file count and
effectively all of the ~2 GB. The two trainers that would answer `training_code_commit` are 6,656
and 7,228 bytes. **Value per byte differs by about five orders of magnitude between the source and
the corpus**, so any option that treats the tree as one indivisible unit pays corpus cost to
preserve source value.

### The options, and why three of them lose

| | Preserves | Loses | Cost | Reversibility | If the disk dies tomorrow |
|---|---|---|---|---|---|
| **A** snapshot everything + new clean repo | all bytes, contradiction frozen intact | simplicity; two repos with a link nothing enforces | ~4 GB on disk; 90k-file git operations forever | high | **still lost** — a local `git init` is not a backup |
| **B** source-only + corpus content-addressed | the 13,884 bytes that answer the commit question; corpus by manifest | corpus BYTES, unless separately replicated | sub-MB repo | highest | source survives; corpus survives only at the external location |
| **C** Git LFS for the whole tree | all bytes | operational sanity; adds a failure mode where missing LFS objects read as a tampered corpus | highest; no LFS configured anywhere today | **lowest** — de-LFS-ing means history rewrite | no better than D without a remote |
| **D** leave in place, rely on pins | the *claims*, rigorously | every trainer, both corpora, `metadata.json`, `train_v2.log`, v2's artefact | zero | trivial as a decision, **irreversible in consequence** | v1 becomes a shipped binary with a recipe nobody can run |

### Recommendation: B's scope with A's labelling, in one repository

A source-only, recovery-labelled snapshot **at** the pipeline root, corpora content-addressed
externally, and any forward work committed on top of the recovery root rather than in a separate
"clean" repo — so that every later commit is structurally, unforgeably *after* the recovery, which
is the ordering this document already demands.

Three things make it dominate rather than merely appeal:

* It is the only shape whose **structure states the truth**. The source was recovered and can be
  versioned; the corpus was never lost, is unversioned, and is addressed by manifests already
  committed here. A and C imply the bytes travel with a clone.
* It **generalises an accepted precedent** instead of inventing one: `artifact_in_repository: false`
  is already load-bearing in `MODEL_REGISTRY.json` for exactly this reason.
* It is the **cheapest to reverse** and forecloses nothing; a sub-MB repo can be upgraded later,
  whereas C cannot be undone without rewriting history.

### The disqualifying condition, stated so it is not skipped

**Any snapshot design is disqualified unless the recovery marker is machine-readable.**
`dataset_registry._last_commit_touching` derives `source_commit` from `git log -1 -- <path>`. Point
that at a snapshot repository and it returns the *recovery* commit as the commit that produced the
file — precisely the substitution this document forbids. A `RECOVERY:` commit message does not fix
it, because nothing reads commit messages. The marker has to be a tracked file that tooling
consults before it consults `git log`.

### What the operator must decide — engineering cannot

**1. Where the corpus physically lives, and who keeps it alive.** Every option's "disk dies
tomorrow" answer collapses to the same sentence: a local repository is not a backup. Until a second
physical location exists, choosing between A/B/C/D is choosing a storage format for data that has
one copy.

**2. Whether the corpora may leave this machine at all — and this can override decision 1.**
`dataset/` is *"1741 web-crawled photos"* with licence UNKNOWN. `dataset_v2/` is *"55,466 crops from
CC BY 4.0 Roboflow datasets"*, which is attributable but carries attribution obligations on
redistribution. Pushing either to a hosted remote is a licensing question with legal exposure, not
an engineering one. If the crawled images may not leave, the answer narrows to *source-only repo,
corpus stays local, and the single-copy risk is accepted* — and that acceptance must be recorded as
a decision rather than arrived at by default.

**3. Whether the scanner programme continues at all.** Both models are useless on real gym photos —
historical top-3 `0/18`, reproduced `1/18`. If v1 ships as-is and there is no v3, the forward half
of the recommendation is unjustified engineering and the correct scope is *preserve the evidence,
do not build a training platform*. The preservation half is correct under either answer.

### One correction this package forced

`RECOVERY_CONTRACT` used to say the first commit after `git init` satisfies the COMMIT item, and
that ML-2a for v1 was "a directory and a commit". Both were wrong.
`training_run._commit_exists` resolves a sha with `git -C <this repository>`, so a commit made in
the pipeline directory does not exist as far as `validate` is concerned, and `training_code_commit`
is rejected exactly as before. Closing it needs the commit **and** a repo-qualified
`training_code_commit`, which is a schema change nobody has authorised. The contract now says so.

### A migration hazard, pre-recorded

`test_the_pipeline_is_still_not_a_git_repository` is `@needs_pipeline` and therefore **skips on
CI**, while `test_the_pin_is_dated` asserts `is_git_repository is False` everywhere. A `git init`
turns the suite red asymmetrically: green on CI, failing only on the one machine that holds the
directory. The pin and the registry must be updated in the *same* change as any snapshot, or the
repository asserts something false for the length of the gap.

## v1 reproducibility: ATTEMPTED, and the result is METRIC_REPRODUCIBLE

Run 2026-08-18 on this machine. The recovered trainer was copied and **exactly one
line changed** — the output directory — so the historical `out/` could not be
overwritten. Verified: all four artefacts in `D:/tools/equipment-model/out` carry
the same sha256 after the run as before it.

**Environment** (read from the venv, not assumed): Python 3.11.9, tensorflow-cpu
2.15.1, keras 2.15.0, numpy 1.26.4, mediapipe 1.0.0, no CUDA and no GPU visible.
No pin file of any kind exists; every version above is RECOVERABLE from
`D:/tools/ml-train-env` and from that directory alone.

| Result | Basis | |
|---|---|---|
| Metric | **FACT** | The trainer printed `FINAL val_accuracy=0.617`. `MODEL_REGISTRY.json` records `top_1: 0.617`, and `mobile/assets/models/README.md:19-21` defines it as the held-out 15% stratified split evaluated on the exported `.tflite`, n=261. **Reproduced.** |
| `labels.txt` | **FACT** | sha256 `ff51b4a9…4c99fd` — bitwise identical to the historical file. |
| Model weights | **FACT** | `b6b37af8…ef1260` vs historical `37733e2e…38eed3`. Different. Byte count identical at 4,495,700. |
| Metadata step | **BLOCKED_BY_WINDOWS_PACKAGE** | `AttributeError: module '_pywrap_metadata_version' has no attribute 'GetMinimumMetadataParserVersion'`. The trainer stubs that module because mediapipe on Windows ships no C extension; the stub does not cover the path `load_metadata_buffer` takes. So no final `equipment_v1.tflite` was produced by this run. |

### The metadata step, traced (2026-08-18)

The row above said `BLOCKED_BY_DEPENDENCIES`, which named a symptom. A bounded probe established
what the requirement actually is, and turned up something about the SHIPPED artefact that had not
been written down.

**What the step needs.** `attach_metadata.py` (in `D:/tools/equipment-model`, outside this
worktree) reads `out/equipment_v1_nometa.tflite` and uses
`mediapipe.tasks.python.metadata.metadata_writers.image_classifier` to embed the label set and the
normalisation parameters, then writes `out/equipment_v1.tflite`. This is **not** merely packaging.
The app loads the model through ML Kit's `LocalLabelerOptions`
(`mobile/lib/features/visual_equipment/data/mlkit_live_equipment_service.dart`), which reads its
labels out of the embedded metadata — a model without it produces no usable labels. Training,
conversion and the metric evaluation do not need it, which is why `METRIC_REPRODUCIBLE` was
reachable without it.

**Classification: `WINDOWS_PACKAGE_GAP`.** `tflite-support` publishes no Windows wheels. The
metadata writers still exist inside `mediapipe` 1.0.0, but that build ships them without the
`_pywrap_metadata_version` C extension. Probed for a genuine environment rather than assumed:
`tflite_support` is absent from `D:/tools/ml-train-env` and from the system interpreter, and the
Docker images already present locally are generic `python:3-slim`/`python:3.12-slim` with nothing
installed. Obtaining the real tool means a network install into a Linux container, which is an
environment recipe rather than a result. **Disposition: `BLOCKED_BY_WINDOWS_PACKAGE`.**

**What the probe found in the shipped model — `FACT`, and new.** `attach_metadata.py` does not fail
for want of a stub; it *installs* one, `_install_pywrap_stub`, which exposes
`GetMinimumMetadataParserVersion` as a function returning the literal string `"1.0.0"`. And
`D:/tools/equipment-model/out/metadata.json` records `min_parser_version: 1.0.0`. So the minimum
metadata parser version embedded in the `equipment_v1.tflite` this app ships was **stamped by a
stub, not computed by the library**. For a plain image classifier carrying labels and normalisation
that floor is probably correct — but probably is the whole point: nobody computed it, so nobody
knows, and the artefact states it as though someone had.

This is recorded and deliberately **not fixed**. Fixing it means running the genuine tool, which is
the blocked step. Widening the stub until the current error goes away would mean inventing a second
metadata parser version and stamping that into a shipped artefact too — the fabrication this
programme exists to refuse, and the reason the obvious workaround stays refused.

No artefact was modified by this probe. The shipped champion, the registry, the v2 status, D3 and
`PRODUCTION_IMAGE_COLLECTION = DISABLED` are all untouched.

**Disposition: `METRIC_REPRODUCIBLE`. Not `BITWISE_REPRODUCIBLE`, and it never could
have been.** The trainer seeds only the train/validation split — `SEED = 20260729`
is passed to `image_dataset_from_directory`. There is no `tf.keras.utils.set_random_seed`,
no `tf.random.set_seed`, and no `TF_DETERMINISTIC_OPS`, so the classifier head is
initialised from an unseeded global RNG and CPU reductions are not forced
deterministic. Two runs of this pipeline cannot produce the same weights. That is a
property of the recovered trainer, not a defect in the environment, and it means
bitwise reproduction should never be listed as a gap that effort could close.

**The metadata failure is itself provenance evidence.** The historical run completed
that step — `out/metadata.json` exists, 1,714 bytes — and the current venv cannot.
So `D:/tools/ml-train-env` is close enough to reproduce the headline metric and *not*
identical to the environment that finished the pipeline. The venv is
`RECOVERED_CURRENT_ENVIRONMENT`, never `PROVEN_ORIGINAL_TRAINING_ENVIRONMENT`.

### A cross-check that was not the point of the run

Both models were then put through the pipeline's own `eval_on_gym_photos.py` against
its own truth file — same script, same 30 photos, same label set.

The **historical** artefact scored top-3 `0/18` on the labelled photos, with top-1
confidence `min 0.215 · median 0.437 · max 0.897`. Those three numbers are exactly
the ones `core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md:21` records, and which
`METRIC_PROVENANCE.md` lists as NOT_LOCATABLE because the source states them under
Russian labels. **They are now independently confirmed by re-measurement.** That does
not make them machine-locatable and does not change their audit verdict — the locator
still cannot read a Russian metric name, and inventing a translation table is still
forbidden. It does mean the document is telling the truth.

The **reproduced** model scored top-3 `1/18`, confidence `min 0.205 · median 0.544 ·
max 0.889`. Both models are useless on real gym photos, which is B1's whole finding.
The two runs agree on the conclusion and not on the digits, which is precisely what
"metric-reproducible but not bitwise" means.
