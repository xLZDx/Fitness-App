# -*- coding: utf-8 -*-
"""ML-2a — where the scanner model actually came from, and what is still missing.

    python scripts/ml/scanner_provenance.py            # probe and classify
    python scripts/ml/scanner_provenance.py --contract # the recovery contract
    python -m pytest scripts/ml/test_scanner_provenance.py -q

The dataset registry recorded ``equipment_recognition_training`` as
``UNRESOLVED`` with the note that the pipeline *"lives at
D:/tools/equipment-model/, which is not a git repository"* and that the corpus
*"cannot be addressed, hashed or rebuilt from here"*.

The first half is true and now independently verified. **The second half was
misleading and is corrected here.** The corpus is not lost: 1,741 files sit in
``dataset/``, untouched since the day v1 was trained, and the shipped
``equipment_v1.tflite`` is byte-identical to the pipeline's own build output.
What is missing is not the data — it is a repository, a commit, and a record
binding one to the other.

That distinction changes what the work is. A reader of the old note plans a
re-crawl. The truth is that ``git init`` plus a recorded hash closes v1.

## Why a pin plus a probe, rather than reading the directory

``D:/tools/equipment-model`` is on one machine and in no checkout. A registry
field computed from it would differ on every other machine and CI would fail on
a difference that means nothing. So the measurements below are PINNED — taken
once, dated, and committed — and ``probe()`` re-verifies them when the path
happens to be present. On a machine without it, the probe reports
``NOT_PRESENT_ON_THIS_MACHINE`` and does not fail. Same contract as the
catalogue digest in the clinical handoff: the pin is the claim, the probe is
the check, and absence is reported rather than guessed.

## What this module does NOT do

It does not import the pipeline, copy it into this repository, or promote
anything. ``D3 = CLOSED`` and ``PRODUCTION_IMAGE_COLLECTION = DISABLED`` are
untouched: a reproducible v2 would still not be a challenger, and this module
has no opinion about whether v2 should ship. It records provenance.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]

#: Where the pipeline was found. Overridable so a second machine can verify.
PIPELINE_ROOT = Path(
    os.environ.get("SPTR_SCANNER_PIPELINE", r"D:/tools/equipment-model")
)

#: The shipped artefact, which IS in this repository.
SHIPPED_MODEL = REPO / "mobile" / "assets" / "models" / "equipment_v1.tflite"

#: Outcomes. Named so a report cannot blur "we looked and it is unversioned"
#: into "we could not find it".
CLASSIFICATIONS = (
    "FOUND_VERSIONED_PIPELINE",
    "FOUND_UNVERSIONED_PIPELINE",
    "FOUND_PARTIAL_PROVENANCE",
    "FOUND_ONLY_ARTEFACTS",
    "NOT_FOUND",
    "NOT_PRESENT_ON_THIS_MACHINE",
)

#: Measured 2026-08-18 against `D:/tools/equipment-model`, by the functions in
#: this module. Every value is reproducible by running the module on a machine
#: that has the directory; none of it is transcribed from a report.
PINNED: dict[str, Any] = {
    "measured_at": "2026-08-18",
    "root": "D:/tools/equipment-model",
    "is_git_repository": False,
    "artifacts": {
        "out/equipment_v1.tflite": {
            "bytes": 4496661,
            "sha256": "6f159ec32cd6c010c5319cb3436b22e97ce07ee72ff6f05daf02d3a2c7e696e3",
        },
        "out_v2/equipment_v2.tflite": {
            "bytes": 4564876,
            "sha256": "d642effced67d0aef4f17273f8c6e7e4ebf90aa3452576ec1cde75ed52f74848",
        },
        "out/labels.txt": {
            "bytes": 117,
            "sha256": "ff51b4a912922a00b60d89ea455cf0fad5eeb2e63ce4d89680572c52cf4c99fd",
        },
        "out_v2/labels.json": {
            "bytes": 774,
            "sha256": "4bf5a41c7d2acb266323fb786ac2a8ffa8d46e1cd41cef27fe9c20e125dee36d",
        },
        "train_export.py": {
            "bytes": 6656,
            "sha256": "2424fea990a7b2057ae6e0670ba903323f1d1c3ea61300b13e668fdbf51596ac",
        },
        "train_v2.py": {
            "bytes": 7228,
            "sha256": "81f79ac8fe1c1766d66fb52b03503d898d68d323dfc73fa96cfe7cc04046603e",
        },
        # The pre-metadata export. Pinned because the 2026-08-18 reproduction
        # produces this artefact and not the final one -- the metadata step
        # cannot run in the current venv -- so this is the only file the two
        # runs can be compared on.
        "out/equipment_v1_nometa.tflite": {
            "bytes": 4495700,
            "sha256": "37733e2e277b5d24df3aa0eb4bc5eee3481cf34227fda4fe4c9905892f38eed3",
        },
    },
    "corpora": {
        # `manifest` is sha256 over (relative posix path, NUL, file sha256, LF)
        # for every file, sorted by path -- see `corpus_manifest`. Stated as an
        # algorithm rather than a number somebody could not reproduce.
        "dataset": {"files": 1741, "manifest": (
            "411189bc811c4ca7e6dcfddc7ef6cdf601d2ca2e13ede6b0615ac7ec8808e2b6"
        )},
        "dataset_v2": {"files": 90817, "manifest": (
            "b228f19874e8aff1dd2163d7767fae226be1d21bb439edf1b6ecec586816731e"
        )},
    },
}

#: What re-running the recovered v1 trainer actually produced, 2026-08-18.
#:
#: Recorded as data rather than only as prose in `core/ml/SCANNER_PROVENANCE.md`,
#: because a reproduction result is a measurement this repository now owns and a
#: number living only in a paragraph is a number nothing can check.
#:
#: The disposition is METRIC_REPRODUCIBLE. The trainer printed
#: `FINAL val_accuracy=0.617`, matching the registry. The WEIGHTS differ and
#: always will: `train_export.py` seeds only the train/validation split, so the
#: classifier head is initialised from an unseeded global RNG. Bitwise
#: reproduction is impossible by construction and is not a gap effort can close.
REPRODUCTION_2026_08_18 = {
    "disposition": "METRIC_REPRODUCIBLE",
    "val_accuracy": 0.617,
    "artifacts": {
        # Same byte count as the historical export, different weights.
        "out/equipment_v1_nometa.tflite": {
            "bytes": 4495700,
            "sha256": (
                "b6b37af8e191f253a0adbf9fb43a5180da70d35e271f295e26d086a69bef1260"
            ),
        },
        # Bitwise identical to the historical file.
        "out/labels.txt": {
            "bytes": 117,
            "sha256": (
                "ff51b4a912922a00b60d89ea455cf0fad5eeb2e63ce4d89680572c52cf4c99fd"
            ),
        },
    },
    "environment": {
        "python": "3.11.9",
        "tensorflow": "2.15.1",
        "keras": "2.15.0",
        "numpy": "1.26.4",
        "mediapipe": "1.0.0",
        "gpu": False,
        # Read from D:/tools/ml-train-env. No pin file exists anywhere, so this
        # is RECOVERED_CURRENT_ENVIRONMENT and not a proven original.
        "source": "RECOVERED_CURRENT_ENVIRONMENT",
    },
    "blocked_step": "metadata attachment (mediapipe stub does not cover "
                    "GetMinimumMetadataParserVersion on this venv)",
}

#: The one fact that makes v1 recoverable rather than merely documented.
SHIPPED_MODEL_SHA256 = (
    "6f159ec32cd6c010c5319cb3436b22e97ce07ee72ff6f05daf02d3a2c7e696e3"
)


class ProvenanceError(RuntimeError):
    """A provenance claim that the bytes on disk do not support."""


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def corpus_manifest(root: Path) -> tuple[int, str]:
    """A deterministic digest over a directory tree: (file count, sha256).

    Path-inclusive on purpose. A digest over file contents alone would be
    identical after a rename, and a rename in a class-per-directory image
    corpus changes the LABEL of every file under it.
    """
    files = sorted(
        (p for p in root.rglob("*") if p.is_file()),
        key=lambda p: p.relative_to(root).as_posix(),
    )
    h = hashlib.sha256()
    for p in files:
        h.update(p.relative_to(root).as_posix().encode("utf-8"))
        h.update(b"\0")
        h.update(_digest(p).encode("ascii"))
        h.update(b"\n")
    return len(files), h.hexdigest()


def probe(root: Path | None = None) -> dict[str, Any]:
    """Classify the pipeline, verifying the pin where the bytes are reachable."""
    root = Path(root or PIPELINE_ROOT)
    shipped = {
        "path": str(SHIPPED_MODEL.relative_to(REPO)).replace("\\", "/"),
        "sha256": _digest(SHIPPED_MODEL) if SHIPPED_MODEL.exists() else None,
        "matches_pin": (
            SHIPPED_MODEL.exists() and _digest(SHIPPED_MODEL) == SHIPPED_MODEL_SHA256
        ),
    }

    if not root.exists():
        return {
            "classification": "NOT_PRESENT_ON_THIS_MACHINE",
            "root": str(root),
            "shipped_model": shipped,
            "pinned": PINNED,
            "verified": [],
            "mismatches": [],
            "note": (
                f"{root} is not on this machine, so the pin below could not be "
                "re-verified here. That is expected: the pipeline is in no "
                "checkout. Absence of the directory is NOT evidence that the "
                "pipeline is gone -- it is evidence that this machine is not "
                "the one it is on."
            ),
        }

    verified: list[str] = []
    mismatches: list[dict[str, Any]] = []
    for name, pin in PINNED["artifacts"].items():
        path = root / name
        if not path.exists():
            mismatches.append({"artifact": name, "problem": "absent"})
            continue
        got = _digest(path)
        if got == pin["sha256"] and path.stat().st_size == pin["bytes"]:
            verified.append(name)
        else:
            mismatches.append({
                "artifact": name, "problem": "changed",
                "pinned": pin["sha256"][:16], "found": got[:16],
            })

    for name, pin in PINNED["corpora"].items():
        path = root / name
        if not path.exists():
            mismatches.append({"corpus": name, "problem": "absent"})
            continue
        count, manifest = corpus_manifest(path)
        if manifest == pin["manifest"] and count == pin["files"]:
            verified.append(f"{name}/ ({count} files)")
        else:
            mismatches.append({
                "corpus": name, "problem": "changed",
                "pinned_files": pin["files"], "found_files": count,
                "pinned": pin["manifest"][:16], "found": manifest[:16],
            })

    is_git = (root / ".git").exists()
    return {
        "classification": (
            "FOUND_VERSIONED_PIPELINE" if is_git
            else "FOUND_UNVERSIONED_PIPELINE"
        ),
        "root": str(root),
        "is_git_repository": is_git,
        "shipped_model": shipped,
        "verified": verified,
        "mismatches": mismatches,
        "pinned": PINNED,
    }


#: What must exist before `training_run.validate` would accept a manifest for
#: either scanner version. Exact, because "pipeline missing" is not actionable.
RECOVERY_CONTRACT: dict[str, Any] = {
    "blocks": "ML-2a",
    "why_it_is_open": (
        "core/ML_PLATFORM_ARCHITECTURE.md section 4 requires every production "
        "model version to resolve training_code_commit. Neither scanner "
        "version can: the code that produced them is at a path that is not a "
        "git checkout, so there is no commit to name. "
        "scripts/ml/training_run.py refuses a run manifest in that shape."
    ),
    "what_is_NOT_missing": [
        "The v1 training corpus. 1,741 files in dataset/, manifest pinned "
        "above, and nothing in it was modified after v1 was built.",
        "The v1 entry point. train_export.py is a complete, self-contained "
        "trainer with its hyperparameters and its seed as literals.",
        "The v1 artefact chain. mobile/assets/models/equipment_v1.tflite is "
        "BYTE-IDENTICAL to the pipeline's own out/equipment_v1.tflite, so the "
        "shipped model and the build output are provably the same file.",
    ],
    "required_to_close": [
        {
            "item": "REPOSITORY",
            "state": "MISSING",
            "required": (
                "git init at D:/tools/equipment-model, or move it into a "
                "repository. This was once described as the whole of ML-2a "
                "for v1 -- a directory and a commit. It is not: see COMMIT "
                "below, and the operator decisions in SCANNER_PROVENANCE.md "
                "about where 2 GB of possibly-unredistributable images may "
                "live."
            ),
        },
        {
            "item": "COMMIT",
            "state": "MISSING_AND_UNOBTAINABLE_RETROACTIVELY",
            "required": (
                "A commit that CONTAINS train_export.py at the pinned digest "
                "2424fea9... AND a validator that can see it. This item used "
                "to say the first commit after `git init` satisfies it. That "
                "was wrong, and wrong in the direction that wastes somebody's "
                "afternoon: `training_run._commit_exists` resolves a sha with "
                "`git -C <this repository>`, so a commit made in the pipeline "
                "directory does not exist as far as `validate` is concerned "
                "and `training_code_commit` is rejected exactly as before. "
                "Closing this needs the commit AND a repo-qualified "
                "`training_code_commit` (repository identity plus sha), which "
                "is a schema change nobody has authorised yet."
            ),
        },
        {
            "item": "DATASET_ID",
            "state": "MISSING_AS_A_RECORD",
            "required": (
                "A dataset registry entry binding manifest 411189bc... to "
                "equipment_recognition v1. The bytes exist; nothing names them."
            ),
        },
        {
            "item": "DEPENDENCY_PIN",
            "state": "MISSING",
            "required": (
                "A requirements freeze. D:/tools/ml-train-env is a venv, and a "
                "venv is not a lockfile -- no TensorFlow or Keras version is "
                "recorded anywhere, so a rebuild would not be a rebuild."
            ),
        },
        {
            "item": "RUN_RECORD_FOR_V2",
            "state": "MISSING_AND_CONTRADICTED",
            "required": (
                "The only log, train_v2.log, records a 29-CLASS run "
                "(`DROPPED 8 classes`, `training 29 classes`, `Found 54914 "
                "files`). The registered v2 artefact carries 37 labels in "
                "out_v2/labels.json. So the one run record on disk describes a "
                "DIFFERENT MODEL from the one the registry names, and the "
                "registered artefact has no run record at all. v2 needs a "
                "fresh, logged run -- not a retro-fitted manifest."
            ),
        },
        {
            "item": "V2_LABEL_SOURCE",
            "state": "UNVERSIONED_THIRD_COPY",
            "required": (
                "classes.py reads the equipment catalogue from "
                "D:/test 2/Fitness App/... -- a third, unversioned copy of "
                "this project, at an unrecorded revision. v2's label set was "
                "generated from it. Repoint at the real catalogue before any "
                "v2 work."
            ),
        },
    ],
    "does_not_close": (
        "Closing ML-2a makes the scanner REPRODUCIBLE. It does not make v2 a "
        "challenger, does not promote anything, and does not reopen D3: "
        "PRODUCTION_IMAGE_COLLECTION stays DISABLED and a reproducible model "
        "is still only TRAINED."
    ),
}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--contract", action="store_true",
                    help="print the recovery contract")
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--root", default=None)
    args = ap.parse_args(argv)

    if args.contract:
        print(json.dumps(RECOVERY_CONTRACT, ensure_ascii=False, indent=2))
        return 0

    result = probe(args.root)
    if args.json:
        print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
        return 0

    print(f"  {result['classification']}")
    print(f"  root            {result['root']}")
    shipped = result["shipped_model"]
    print(f"  shipped model   {shipped['sha256'][:16] if shipped['sha256'] else '?'}"
          f"...  matches pin: {shipped['matches_pin']}")
    if result["verified"]:
        print(f"  verified        {len(result['verified'])} pinned objects")
        for v in result["verified"]:
            print(f"                    {v}")
    if result.get("mismatches"):
        print("  MISMATCHES:")
        for m in result["mismatches"]:
            print(f"                    {m}")
    if result.get("note"):
        print(f"\n  {result['note']}")
    print(f"\n  ML-2a stays OPEN. {len(RECOVERY_CONTRACT['required_to_close'])} "
          "items required to close; run --contract to read them.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
