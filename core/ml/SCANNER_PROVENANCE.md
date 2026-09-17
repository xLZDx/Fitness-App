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
effectively all of the ~2 GB.

**Corrected 2026-08-18.** This section previously priced the source at 13,884 bytes, being the two
trainers, and claimed five orders of magnitude. Re-measured on disk: the pipeline root holds **15
Python files totalling 80,271 bytes**, and the framing was wrong to stop at the trainers —
`attach_metadata.py` (4,474 B) is load-bearing for the shipped artefact's labels and
`eval_on_gym_photos.py` (4,475 B) produced both the 0/18 and 1/18 real-world numbers. Add ~62 KB of
provenance JSON and `train_v2.log` at 1,317,222 B. So the true ratio is **about four orders of
magnitude, not five**.

The conclusion is unchanged and the correction is recorded anyway: an argument that survives a 6x
error in its own headline number was not resting on that number, and a decision package whose
measurements are not re-checked is the artefact this whole document exists to distrust.

A third tree was missed entirely: **`dataset_v2_thin/`, 462 files**, in neither pinned manifest
(`scanner_provenance.PINNED` pins only `dataset` and `dataset_v2`). It is the dropped-8-classes tree
the only surviving log actually describes. With `fresh_test/`, that is 518 files outside both
manifests — they must be content-addressed under any snapshot option, and today they are
unaccounted for.

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

**Corrected 2026-08-18: that hazard is CONDITIONAL, not present.** The paragraph above read as a
live defect and it is not one. `_last_commit_touching` runs `git -C str(REPO)` where `REPO` is
`Path(__file__).resolve().parents[2]` — measured as `D:\Repo\_wt-formcoach`, this repository
(`scripts/ml/dataset_registry.py:50`, `:93`). It cannot be pointed anywhere else. The substitution
becomes reachable only if scanner source is snapshotted **into this repository**, or if that helper
is parameterised. Both are choices, so the disqualifying condition stands — but it disqualifies
those two shapes specifically, and an architecture that keeps the snapshot in a separate repository
avoids the hazard by construction rather than by adding a marker to defend against it.

That marker does not exist yet, and building it is **local Python work in this worktree** —
`scripts/ml/dataset_registry.py:89` — not something the operator has to supply. It is deliberately
not built in advance, because it is only needed if a snapshot is chosen and would otherwise be
engineering performed to look busy. It was recorded here with the residual marker for
`scanner-pipeline-location` so that choosing A, B or C carried its own precondition rather than
discovering it afterwards. **Resolved by non-applicability, 2026-09-17, marker retired:** S-1 was
decided as the separate-repository shape (`core/decisions/scanner-pipeline-location.md`), not the
snapshot-into-this-repository shape — the row this marker actually gated (see the table below).
This marker never activated and this module never needed the machine-readable recovery marker.

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

### The council's answer, and where it beat the recommendation above (2026-08-18)

Two independent lenses — MLOps/repository-architecture and data-governance/licensing/provenance —
were run without sight of each other. **Both rejected the recommendation above in the same place,
for reasons neither could have got from the other.**

#### The recommendation was wrong to put the workspace inside the evidence tree

"A source-only, recovery-labelled snapshot **at** the pipeline root … forward work committed on top
of the recovery root" puts the working repository inside the thing being preserved. That tree has
**already destroyed provenance once by being written in place**: `train_v2.py` writes to a fixed
output path, so a 37-class run landed on top of the 29-class one and produced the only CONTRADICTED
field in this document. The 2026-08-18 reproduction had to copy the trainer and change exactly one
line so `out/` would not be overwritten again. That is measured proof, not preference: **the
evidence tree and the workspace cannot be the same directory.**

A second cost the recommendation carried: `git init` at the pipeline root flips `probe()` to
`FOUND_VERSIONED_PIPELINE` and turns the pin assertions red asymmetrically — green on CI, where the
directory test skips, failing only on the one machine that holds the corpus. The alternative
eliminates that by construction instead of managing it.

And a subtler, permanent loss. `is_git_repository: False`, measured 2026-08-18, **can never be
re-established by any later probe**. Initialising git at the pipeline root destroys the evidence
that the pipeline was never versioned — which is one of the few facts about this programme that is
cleanly true.

#### Recommended architecture

**An immutable recovered-evidence tree, a separate clean training repository, and corpora addressed
by content outside normal git.** Three artefacts, three lifetimes, none pretending to be another.

| | Enters git | Stays out |
|---|---|---|
| **Source** | 15 Python files, 80,271 bytes | — |
| **Provenance** | ~62 KB of dataset JSON, `out/labels.txt`, `out_v2/labels.json`, `out/metadata.json` | — |
| **Logs** | `train_v2.log` (1,317,222 B), labelled as the log of a superseded run | — |
| **Corpora** | — | `dataset/` (1,741), `dataset_v2/` (90,817), `dataset_v2_thin/` (462), `fresh_test/`, `_roboflow_raw/` |
| **Models** | — | `out/*.tflite`, `out_v2/*.tflite` — `artifact_in_repository: false` is the existing precedent |

`train_v2.log` is committed rather than pruned because it is irreplaceable and deleting it is the
fiction this document forbids: it is the only surviving record of a run whose artefact contradicts
it, and that contradiction is evidence.

#### First-commit semantics: anchor on digests, not on ancestry

The first commit must contain every recovered file **at a digest that already appears in
`scanner_provenance.PINNED`, published 2026-08-18**, plus a tracked machine-readable recovery
manifest, and nothing else authored.

This is stronger than the ordering argument the recommendation above rested on. Commit dates are
forgeable — `GIT_COMMITTER_DATE` sets them — and "structurally after" is only as good as the dates.
**A commit whose every blob matches a digest published earlier, in a different repository, cannot be
the history that produced v1**, and no amount of rewriting changes that. The corollary is the useful
half: any commit introducing a byte with no 2026-08-18 digest is provably forward work, and the
boundary is readable by tooling without anyone reading prose.

The manifest carries `provenance: RECOVERED_UNVERSIONED_SOURCE`, `recovered_at`, `recovered_from`,
`is_git_repository_before_recovery: false`, per-file sha256, and `training_code_commit: UNKNOWN` per
model version. The recovery commit is **not** permitted to fill `training_code_commit`:
`training_run.validate` rejects `UNKNOWN` today and must go on rejecting it, because closing that
field needs a repo-qualified schema change nobody has authorised.

#### What the governance lens added, and it is the more urgent half

**Licensing does not choose between A/B/C/D. It chooses whether image bytes may cross the machine
boundary at all** — and only a source-only shape is unaffected by the answer. Obligations attach to
distribution, not to holding bytes you already lawfully hold, so keeping the corpus local is
licence-neutral and any hosted remote is a transfer to a third party.

Two findings sharpen the picture materially, and both are worse than this document previously said:

* **`dataset/` is not "licence UNKNOWN" in the sense of pending.** It was assembled by Bing image
  search, and no per-image source record was kept — files land as sequential indices, with no
  sidecar. The origin URLs were discarded at download time and cannot be recovered by inspection,
  only by re-crawling, which produces a different corpus. The correct status is **presumptively
  all-rights-reserved third-party photographs whose owners are no longer identifiable**. That makes
  public distribution a blocker rather than a risk: you cannot publish, and you also cannot clear,
  images whose rightsholders you cannot name. **And this is the corpus behind the model this app
  currently ships.** The exposure is live today, independent of any decision taken here.
* **The CC BY 4.0 attribution data was never retained.** All 332 dataset records carry
  `workspace`/`project`/`images` and no licence string, licence URI, source URL, creator or version.
  So the "CC BY 4.0" claim in `MODEL_REGISTRY.json` rests on a filter that ran at fetch time and
  whose output was discarded. Reconstructing it is cheap **today** — re-query the API — and may
  become impossible later, because Universe projects and licences can be changed or withdrawn by
  their owners. `dataset_v2` cannot be redistributed in any form until that manifest exists,
  together with a crop-to-source mapping and a stated "changes made" record covering bbox cropping,
  class remapping and negative mining.

#### What survives if the programme stops

The forward half of any recommendation is contingent on the operator's third question. The
preservation half is not, and one obligation gets **stronger** rather than weaker: `dataset/` and
its manifest must be preserved for as long as v1 ships, because it is the only evidence of what the
distributed model was trained on if a rights claim ever arrives. Deleting it converts an answerable
question into an unanswerable one.

#### What is engineering's after all

The council found three items misfiled as operator decisions. They are recorded, not built —
building them before the decision is taken is constructing infrastructure for a choice nobody has
made:

1. **Whether the evidence tree is also the workspace** is forced by the overwrite evidence above,
   not chosen. Engineering's, and now answered: no.
2. **The scope of "source"** was a measurement error, corrected above.
3. **The reachability of the `git log` substitution** is a fact, corrected above.

### Three decisions, not one (2026-08-18)

The package above reads as one question with sub-parts. It is three, and collapsing them is how a
storage-format choice quietly decides whether a research programme continues.

| | Question | Owner | Depends on |
|---|---|---|---|
| **S-1** | Where does the pipeline **source** live? | Operator | nothing |
| **S-2** | May the **corpora** leave this machine? | Operator, with legal exposure | nothing |
| **S-3** | Does the scanner **programme** continue? | Operator / product | nothing |

They are independent in both directions. S-1 can be answered while S-2 stays no — that is the
recommended combination. S-3 can be *retire* and S-1 still needs an answer, because the preservation
obligation survives the programme: v1 ships today, and `dataset/` is the only evidence of what it
was trained on if a rights claim ever arrives.

#### S-2 has an answer that is nearly forced

`CORPUS_LICENSE_STATUS`, on current evidence:

| Corpus | Files | Status | Basis |
|---|---|---|---|
| `dataset/` | 1,741 | **RESTRICTED** | Assembled by Bing image search with no per-image source record. Origin URLs were discarded at download time and cannot be recovered by inspection. Not "unknown, pending" — **presumptively all-rights-reserved photographs whose owners are no longer identifiable.** |
| `dataset_v2/` | 90,817 | **KNOWN_OK, unevidenced** | CC BY 4.0 by a filter that ran at fetch time and whose output was not retained: all 332 dataset records carry workspace/project/images and no licence string, URI, creator or version. |
| `dataset_v2_thin/` | 462 | **UNKNOWN** | In neither pinned manifest. |
| `fresh_test/` | 12 | **UNKNOWN** | In neither pinned manifest. |

Obligations attach to **distribution**, not to holding bytes already lawfully held. So keeping the
corpus local is licence-neutral; any hosted remote is a transfer to a third party. On the evidence
above, **no option that uploads image bytes anywhere is recommendable**, and that is a finding about
the corpus rather than a preference about git.

#### S-1's recommended architecture

**An immutable recovered-evidence tree, a separate clean training repository, and corpora addressed
by content.** Detailed above; the decisive reason is that the pipeline root has already destroyed
provenance once by being written in place, so the evidence tree and the workspace cannot be the same
directory.

#### The migration package, so that "yes" is executable

Nothing below is performed here — it is what a `yes` authorizes, written out so the yes is informed.

| | |
|---|---|
| **Target** | A new repository at a path the operator names. `D:/tools/equipment-model` stays exactly as it is and becomes read-only evidence. Nothing is moved; source is **copied**. |
| **Enters git** | 15 root `*.py` (80,271 B); `datasets_cc_by.json`, `datasets_usable.json`, `datasets_round2.json`, `diversity_before.json`, `gym_photos_truth.json` (~62 KB); `out/labels.txt`, `out_v2/labels.json`, `out/metadata.json`; `train_v2.log` (1,317,222 B), labelled as the log of a superseded run. |
| **Never enters git** | `dataset/`, `dataset_v2/`, `dataset_v2_thin/`, `fresh_test/`, `_roboflow_raw/`, `out/*.tflite`, `out_v2/*.tflite`, `__pycache__/`. `artifact_in_repository: false` is the existing precedent. |
| **Corpus manifest** | Per-corpus sha256 file lists, committed. The bytes stay put; the manifest is what travels. `dataset_v2_thin/` and `fresh_test/` must be pinned first — today they are in neither manifest. |
| **First commit** | Only files whose digests already appear in `scanner_provenance.PINNED`, published 2026-08-18, plus `RECOVERY.json`. Nothing else authored. |
| **No-fake-ancestry rule** | The anchor is **digests, not dates**. A commit whose every blob matches a digest published earlier in a different repository cannot be the history that produced v1, and unlike commit dates — settable with `GIT_COMMITTER_DATE` — that is not forgeable. Corollary: any commit introducing a byte with no 2026-08-18 digest is provably forward work. |
| **`training_code_commit`** | Stays `UNKNOWN`. `training_run.validate` rejects `UNKNOWN` and must go on rejecting it; the recovery commit is not permitted to fill that field. |
| **CI bootstrap** | One job: verify every file listed in `RECOVERY.json` still matches its digest, and fail if a listed file changed without the manifest changing in the same commit. |
| **Rollback** | Delete the new repository. Nothing was moved, so there is nothing to restore. |
| **Post-migration validation** | `pytest scripts/ml` green here, with the pin and registry updated **in the same change** — see the CI-asymmetry hazard below. |

#### Which residuals each option activates

No hidden downstream work: choosing an architecture is choosing its prerequisites.

| Choice | Activates | Required before migration is complete |
|---|---|---|
| **S-1 = recommended** (separate repo) | the residual marker for `scanner-pipeline-location` — the CI-asymmetric pin assertion — **DONE, 2026-09-17, marker retired** | `test_the_pin_is_dated` asserts `is_git_repository is False` unconditionally while the probing test skips on CI; `test_the_pipeline_is_still_not_a_git_repository`'s docstring and `scanner_provenance.py`'s own module docstring were updated in the same change as `D:/Repo/equipment-model-pipeline`'s creation to record that a separate repository now exists without changing `PIPELINE_ROOT`'s own classification. |
| **S-1 = snapshot into this repository** | Both residuals, including the machine-readable recovery marker | **Yes**, and this is the shape that makes the marker mandatory: `_last_commit_touching` runs `git -C` against *this* worktree, so the substitution only becomes reachable here. |
| **S-1 = leave in place** | Neither | — |
| **S-2 = any upload** | A CC BY 4.0 attribution manifest, a crop-to-source mapping, and a "changes made" record | **Yes**, and it must be reconstructed by re-querying the API, which may stop being possible. |
| **S-3 = retire** | Nothing new | The preservation half of S-1 still stands. |

### A migration hazard, pre-recorded

`test_the_pipeline_is_still_not_a_git_repository` is `@needs_pipeline` and therefore **skips on
CI**, while `test_the_pin_is_dated` asserts `is_git_repository is False` everywhere. A `git init`
turns the suite red asymmetrically: green on CI, failing only on the one machine that holds the
directory. The pin and the registry must be updated in the *same* change as any snapshot, or the
repository asserts something false for the length of the gap.

This too is local work — a test change in `scripts/ml/test_scanner_provenance.py:88` — and it too
was a rider on the decision rather than work due before one existed: the residual marker for
`scanner-pipeline-location`, **done 2026-09-17, marker retired** in the same commit that created
`D:/Repo/equipment-model-pipeline`.

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
environment recipe rather than a result. **Disposition: `BLOCKED_BY_WINDOWS_PACKAGE`.

**Overturned 2026-08-18.** That disposition was wrong, and the way it was wrong is the
point: `pip install tflite-support` was attempted INSIDE a container, failed with
`CERTIFICATE_VERIFY_FAILED`, and the conclusion drawn was that this host cannot reach
PyPI. The host reaches PyPI fine — the interception CA is in the Windows trust store and
absent from `python:3-slim`'s bundle, so a property of the container was generalised into
a property of the environment. Downloading the manylinux wheels on the host and
installing them offline in the container needs no TLS bypass, no `--trusted-host` and no
widening of the stub. The genuine `_pywrap_metadata_version` then computes **`1.0.0`** for
the shipped `equipment_v1.tflite` — the same value the stub stamped — with `labels.txt`
intact and normalisation `mean=[0.0] std=[1.0]`. Recipe:
`scripts/ml/metadata_validation_recipe.md`. Result: `core/ml/METADATA_VALIDATION.json`,
`VALIDATED_MATCH`.

The stub was still a stub. The genuine function rejects an empty buffer; the stub answers
`1.0.0` for anything. Being right by luck about one artefact is not a process.**

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
