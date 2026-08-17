# -*- coding: utf-8 -*-
"""The training-run manifest — a validator, written before there is a run.

    python scripts/ml/training_run.py            # says what has been trained
    python -m pytest scripts/ml/test_ml_contracts.py -q

**NO REAL CT-1 CHALLENGER HAS BEEN TRAINED.** Nothing in this repository has
produced one, this module has never validated a real run, and its own CLI says
so rather than printing an empty table that reads like a clean history.

## Why a validator and not a framework

The two consumers a training framework would need do not exist: CT-1's champion
is a deterministic rule set and the scanner's pipeline lives outside this
repository entirely. Building an orchestrator for them would be a platform with
no users, and the brief is explicit about not doing that.

What DOES have an immediate use is the refusal. `core/ML_PLATFORM_ARCHITECTURE.md`
section 4 requires every production model version to resolve
`training_code_commit`, and `equipment_recognition` cannot — the code that
produced the model in the APK is at a path that is not a git checkout. That is
a live, recorded defect (ML-2a). This module is the thing that makes the same
defect impossible to repeat quietly for the next model: a run manifest that
cannot name a real commit is refused at the point it is written, not discovered
in an audit a year later.

## What it refuses, and why each one is the interesting case

* ``training_code_commit`` that is absent, ``UNKNOWN``, or not a commit that
  exists in this repository. The exact shape of ML-2a.
* a dataset version that is not in ``DATASET_REGISTRY.json``, or one whose
  status is ``UNRESOLVED``. Training on data nobody can address produces a
  model nobody can reproduce.
* an evaluation dataset that is the training dataset. A model measured on what
  it learned reports its memory.
* a ``result`` claimed without an ``evaluation_dataset``. "It got better" is
  not a measurement.
* a status outside the lifecycle, or one that skips ahead — the manifest may
  record ``TRAINED`` or ``EVALUATED`` and may not record ``CHAMPION``, because
  a training run is not a promotion decision.
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from dataset_registry import OUT as DATASET_REGISTRY  # noqa: E402
from lifecycle import TRANSITIONS  # noqa: E402

SCHEMA_VERSION = 1

#: Where completed run manifests would live. Deliberately not created: an empty
#: directory in the tree reads as "runs happen here and none have", which is
#: true but invites somebody to believe the pipeline exists.
RUNS = REPO / "core" / "ml" / "runs"

REQUIRED = (
    "run_id", "model_id", "candidate_version", "training_code_commit",
    "dataset_version", "config_hash", "seed", "environment",
    "started_at", "ended_at", "artifact_hash", "evaluation_dataset",
    "result", "status",
)

#: The only states a TRAINING RUN may claim. A run produces a model and
#: measures it; it does not promote one.
RUN_STATUSES = ("TRAINED", "EVALUATED", "FAILED", "REJECTED")


class TrainingRunError(RuntimeError):
    """A run manifest that would make an unreproducible model look traceable."""


def _commit_exists(sha: str) -> bool:
    if not re.fullmatch(r"[0-9a-f]{7,40}", sha or ""):
        return False
    try:
        subprocess.run(
            ["git", "-C", str(REPO), "cat-file", "-e", f"{sha}^{{commit}}"],
            capture_output=True, check=True,
        )
        return True
    except Exception:
        return False


def _datasets() -> dict[str, dict[str, Any]]:
    registry = json.loads(DATASET_REGISTRY.read_text(encoding="utf-8"))
    return {
        f"{e['dataset_id']}_{e['dataset_version']}": e
        for e in registry["datasets"]
    }


def validate(run: dict[str, Any]) -> dict[str, Any]:
    """Refuse a run manifest that cannot support the claims it makes."""
    missing = [f for f in REQUIRED if f not in run]
    if missing:
        raise TrainingRunError(
            f"{run.get('run_id')!r} is missing {missing}. A partly described "
            "run is worse than none: it looks recorded"
        )

    commit = run["training_code_commit"]
    if commit in (None, "", "UNKNOWN") or not _commit_exists(commit):
        raise TrainingRunError(
            f"training_code_commit={commit!r} does not name a commit in this "
            "repository. This is exactly ML-2a: the scanner model in the APK "
            "cannot be traced to the code that produced it, and it must not "
            "happen twice. Section 27 of the CT-1 brief: never UNKNOWN"
        )

    if run["status"] not in RUN_STATUSES:
        raise TrainingRunError(
            f"status {run['status']!r} is not one of {RUN_STATUSES}. A "
            + (
                "training run does not promote a model; a promotion is a "
                "separate human decision recorded in the model registry"
                if run["status"] in TRANSITIONS
                else "run may only report what it did"
            )
        )

    datasets = _datasets()
    train = run["dataset_version"]
    if train not in datasets:
        raise TrainingRunError(
            f"dataset_version={train!r} is not in DATASET_REGISTRY.json. "
            f"Known: {sorted(datasets)}. Training on data nobody can address "
            "produces a model nobody can reproduce"
        )
    if datasets[train]["status"] == "UNRESOLVED":
        raise TrainingRunError(
            f"dataset_version={train!r} is registered UNRESOLVED. Its bytes "
            "cannot be addressed or hashed, so a run against it cannot be "
            "reproduced and must not be recorded as if it could"
        )

    evaluation = run["evaluation_dataset"]
    if run["result"] is not None and not evaluation:
        raise TrainingRunError(
            f"{run['run_id']!r} reports a result with no evaluation_dataset. "
            "'It got better' is not a measurement"
        )
    if evaluation and evaluation == train:
        raise TrainingRunError(
            "evaluation_dataset is the training dataset. A model measured on "
            "what it learned reports its memory, not its generalisation"
        )
    if evaluation and evaluation not in datasets:
        raise TrainingRunError(
            f"evaluation_dataset={evaluation!r} is not in the dataset registry"
        )
    return run


def completed_runs() -> list[dict[str, Any]]:
    """Every run manifest on disk. Currently none, and that is stated."""
    if not RUNS.exists():
        return []
    return [
        json.loads(p.read_text(encoding="utf-8"))
        for p in sorted(RUNS.glob("*.json"))
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.parse_args(argv)
    runs = completed_runs()
    if not runs:
        print(
            "NO REAL CT-1 CHALLENGER TRAINED.\n"
            "  No training-run manifest exists in this repository. The CT-1\n"
            "  champion is a deterministic rule set, and a challenger has\n"
            "  nothing to learn from until human labels return:\n"
            "  BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED.\n\n"
            "  This module is the validator that will refuse the first run\n"
            "  manifest that cannot name a real training commit. It has never\n"
            "  validated a real run."
        )
        return 0
    for run in runs:
        validate(run)
        print(f"  {run['status']:10} {run['run_id']}  {run['model_id']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
