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
| Dependency pin | **UNKNOWN** | No `requirements*.txt`, `*.toml` or lockfile at the pipeline root. The venv `D:/tools/ml-train-env` exists but is not a pin. |

**v1 is closable on every field except the training log and the dependency pin.** Dataset, trainer,
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
| Dependency pin absent | A freeze of `D:/tools/ml-train-env`, which requires that environment to still be intact | operator |
| Bitwise reproducibility | An actual rerun on the pinned corpus with the pinned seed | operator — see the reproducibility disposition in the decision log |
