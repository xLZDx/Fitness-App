# -*- coding: utf-8 -*-
"""The dataset registry — derived from the artefacts, never typed by hand.

    python scripts/ml/dataset_registry.py --write
    python scripts/ml/dataset_registry.py --check     # CI
    python -m pytest scripts/ml/test_ml_contracts.py -q

``MODEL_REGISTRY.json`` answers "what models exist and may they ship".
Nothing answered "what data exists, where did it come from, and is the file on
disk the one it claims to be" — so a model card could cite
``training_dataset_version: content_qa_catalogue_v1`` and nobody could check
that the thing under that name today is the thing that was trained on.

## Generated, and that is the point

Every field below is READ from a real artefact. Nothing is typed. A registry
somebody maintains by hand is a registry that is wrong the first time somebody
rebuilds a dataset and forgets, and the failure is silent because the registry
is the thing you would check.

``--check`` re-derives and compares against the committed file, so drift is a
CI failure rather than a discovery. This is the same contract the CT-1 dataset
and review batch already hold themselves to.

## What it deliberately does NOT record

A dataset it cannot measure. The scanner's training corpus lives outside this
repository at a path that is not a git checkout, so `equipment_recognition`'s
training data is registered as ``UNRESOLVED`` with the reason — not omitted,
and not given a plausible-looking placeholder. An entry that says UNKNOWN is
evidence; an entry that quietly is not there is not.

## Two consumers

``content_qa`` (CT-1) and ``equipment_recognition`` (scanner). Both are in the
model registry, both need to name a dataset version in a model card, and
exactly one of them can currently do so honestly — which is itself the most
useful thing this file records.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from pathlib import Path
from typing import Any

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "core" / "ml" / "DATASET_REGISTRY.json"

SCHEMA_VERSION = 1

#: Fields every entry must resolve. Named here so a new entry cannot be added
#: with half of them; `_validate` refuses one that is missing any.
REQUIRED = (
    "dataset_id", "dataset_version", "purpose", "status", "source_commit",
    "schema_version", "sources", "row_count", "splits", "label_schema",
    "label_provenance", "artifact", "created_at",
)

#: Statuses an entry may carry.
#:
#: `UNRESOLVED` is not a failure state to be cleaned up later. It is the honest
#: record of a dataset this repository cannot describe, and deleting it would
#: turn "we know this is untraceable" into "we never looked".
STATUSES = ("AVAILABLE", "SUPERSEDED", "UNRESOLVED")


class DatasetRegistryError(RuntimeError):
    """A registry entry that would let an unverifiable claim look verified."""


def _digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def _git_commit() -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "UNKNOWN"


def _last_commit_touching(path: str) -> str:
    """The commit a source file last changed at. Stable until the file changes."""
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO), "log", "-1", "--format=%H", "--", path],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
        return out or "UNKNOWN"
    except Exception:
        return "UNKNOWN"


def _ct1_catalogue() -> dict[str, Any]:
    """The CT-1 base dataset, read from its own manifest and its own bytes."""
    root = REPO / "core" / "ml" / "datasets" / "content_qa_catalogue_v1"
    manifest = json.loads((root / "manifest.json").read_text(encoding="utf-8"))
    data = root / "dataset.json"
    return {
        "dataset_id": manifest["dataset_id"],
        "dataset_version": manifest["dataset_version"],
        "purpose": "CT-1 content QA: the base corpus both splits are drawn from",
        "status": "AVAILABLE",
        "source_commit": manifest["source_commit"],
        "schema_version": manifest["schema_version"],
        "sources": manifest["source"],
        "row_count": manifest["rows_included"],
        "rows_excluded": manifest["rows_excluded"],
        "splits": manifest["splits"],
        "split_strategy": manifest["split_strategy"],
        "transforms": manifest["transforms"],
        "label_schema": "scripts/ct1/label_contract.py :: LabelSource",
        "label_provenance": {
            **manifest["label_sources"],
            "reviewed_label_count": manifest["reviewed_label_count"],
            "note": (
                "Every label is machine-produced. None may be a training "
                "target; see label_contract.TRAINABLE_SOURCES."
            ),
        },
        "artifact": {
            "path": str(data.relative_to(REPO)).replace("\\", "/"),
            "sha256": _digest(data),
            "bytes": data.stat().st_size,
            "dataset_hash": manifest["dataset_hash"],
        },
        "created_at": manifest["built_at"],
        "contains_personal_data": manifest["contains_personal_data"],
        "contains_images": manifest["contains_images"],
        "builder": manifest["builder"],
    }


def _review_batches() -> list[dict[str, Any]]:
    """Every review batch on disk, live and superseded, read from its manifest."""
    sys.path.insert(0, str(REPO / "scripts" / "ct1"))
    from review_batch import BATCH_ID as LIVE  # noqa: E402

    root = REPO / "core" / "ml" / "review"
    out = []
    for d in sorted(p for p in root.iterdir() if p.is_dir()):
        path = d / "manifest.json"
        if not path.exists():
            continue
        m = json.loads(path.read_text(encoding="utf-8"))
        items = d / "items.json"
        live = m["batch_id"] == LIVE
        out.append({
            "dataset_id": m["batch_id"].lower(),
            "dataset_version": f"v{m.get('review_schema_version', 1)}",
            "purpose": (
                "CT-1 human review batch, holdout split. Its returned labels "
                "become CT1_HUMAN_EVAL and may NEVER be trained on."
            ),
            "status": "AVAILABLE" if live else "SUPERSEDED",
            "superseded_by": None if live else LIVE,
            "source_commit": m["source_commit"],
            "schema_version": m["schema_version"],
            "sources": m["source"],
            "row_count": m["size"],
            "splits": {m["split"]: m["size"]},
            "sampling": m["sampling"],
            "label_schema": (
                f"{len(m['questions'])} questions x {len(m['verdicts'])} verdicts"
                + (f" + {len(m['reason_codes'])} reason codes"
                   if "reason_codes" in m else "")
            ),
            "label_provenance": {
                "returned_human_labels": 0,
                "note": (
                    "BLOCKER = HUMAN_REVIEW_LABELS_REQUIRED. Built and "
                    "unreviewed; no human label exists in this repository."
                ),
            },
            "artifact": {
                "path": str(items.relative_to(REPO)).replace("\\", "/"),
                "sha256": _digest(items),
                "bytes": items.stat().st_size,
            },
            "created_at": None,
            "may_train_on": False,
        })
    return out


def _clinical_worklist() -> dict[str, Any] | None:
    """The clinician-facing worklist, if one has been issued.

    Registered for the same reason the review batches are: it is a real
    artefact somebody could cite, and the number that matters about it is a
    ZERO. `returned_clinical_labels: 0` is the honest record that D1 is open;
    leaving it out of the registry would make "what data exists" silent about
    the one dataset whose absence blocks the largest open decision.
    """
    root = REPO / "core" / "review" / "worklist"
    meta_path, sheet = root / "worklist.meta.json", root / "worklist.csv"
    if not meta_path.exists() or not sheet.exists():
        return None
    meta = json.loads(meta_path.read_text(encoding="utf-8"))
    return {
        "dataset_id": "clinical_contraindication_worklist",
        "dataset_version": f"v{meta['schema_version']}",
        "purpose": (
            "The row-level worklist issued for external clinical validation of "
            "the contraindication tags. Answers D1/H3; not a training corpus."
        ),
        "status": "AVAILABLE",
        # The commit the SOURCE last changed at, not the one the worklist was
        # generated at. `handoff_commit` moves with every commit, and a moving
        # field inside a re-derived payload would fail `--check` on every
        # commit -- a drift alarm that fires constantly is one nobody reads.
        "source_commit": _last_commit_touching(
            "mobile/assets/data/exercises_vendor.json"
        ),
        "schema_version": meta["schema_version"],
        "sources": {
            "catalogue": "mobile/assets/data/exercises_vendor.json",
            "catalogue_sha256": meta["catalogue_sha256"],
            "vocabulary": "scripts/catalog/injury_regions.json",
        },
        "row_count": meta["counts"]["total"],
        "splits": {
            "tagged": meta["counts"]["tagged"],
            "untagged": meta["counts"]["untagged"],
        },
        "label_schema": (
            f"{len(meta['dispositions'])} dispositions x "
            f"{len(meta['regions'])} region tags"
        ),
        "label_provenance": {
            "returned_clinical_labels": 0,
            "note": (
                "D1 = EXTERNAL_CLINICAL_VALIDATION_REQUIRED; H3 = HOLD. The "
                "sheet has been issued and nothing has come back. No clinical "
                "label exists in this repository, and none may be "
                "manufactured -- label_contract.CLINICALLY_VALIDATED_LABEL "
                "raises on construction."
            ),
        },
        "artifact": {
            "path": str(sheet.relative_to(REPO)).replace("\\", "/"),
            "sha256": _digest(sheet),
            "bytes": sheet.stat().st_size,
        },
        "created_at": None,
        "may_train_on": False,
    }


def _scanner_unresolved() -> dict[str, Any]:
    """The scanner's training corpus: present and hashed, but bound to nothing.

    Do not read UNRESOLVED as "lost". ``scripts/ml/scanner_provenance.py``
    measured the corpus on 2026-08-18 -- 1,741 files, manifest 411189bc..., and
    the shipped ``equipment_v1.tflite`` byte-identical to the pipeline's own
    build output. What is unresolved is a VERSION, not the data: the pipeline
    sits at a path that is not a git checkout, so no commit names any of it.

    The distinction decides what the work is. The earlier wording here sent a
    reader off to plan a re-crawl; the truth is that ``git init`` plus a
    recorded hash closes v1.
    """
    return {
        "dataset_id": "equipment_recognition_training",
        "dataset_version": "UNRESOLVED",
        "purpose": "Trained equipment_recognition v1 (CHAMPION) and v2 (EVALUATED)",
        "status": "UNRESOLVED",
        "source_commit": "UNRESOLVED",
        "schema_version": None,
        "sources": {
            "note": (
                "The pipeline lives at D:/tools/equipment-model/, which is not "
                "a git repository, so no commit addresses the corpus that "
                "produced the model in the APK. The corpus itself is intact "
                "and has been hashed: 1,741 files, manifest 411189bc..., "
                "measured 2026-08-18 by scripts/ml/scanner_provenance.py, "
                "which also verifies that the shipped equipment_v1.tflite is "
                "byte-identical to the pipeline's own out/equipment_v1.tflite. "
                "UNRESOLVED here means unversioned, NOT missing."
            ),
            "measured_by": "scripts/ml/scanner_provenance.py",
        },
        "row_count": None,
        "splits": None,
        "label_schema": "UNRESOLVED",
        "label_provenance": {
            "note": (
                "Unknown. Recorded as UNKNOWN rather than omitted: an entry "
                "that says it cannot be traced is evidence, and one that is "
                "silently absent is not."
            ),
        },
        "artifact": None,
        "created_at": None,
        "blocks": "ML-2a",
        "consequence": (
            "equipment_recognition cannot resolve training_dataset_version or "
            "training_code_commit, so neither version satisfies the registry "
            "contract in core/ML_PLATFORM_ARCHITECTURE.md section 4."
        ),
    }


def _joint_rom_reference() -> dict[str, Any]:
    """The joint range-of-motion reference — a shipped asset, not training data.

    It is registered here for the one thing this registry does that nothing
    else does: bind a name to bytes, so `--check` fails when the file on disk
    stops being the file the entry describes. That matters more than usual for
    this artifact, because it is a hand-editable JSON sitting in
    `mobile/assets/data/` where a well-meaning edit would look permanent and
    would in fact be reverted by the next builder run.

    `created_at` is None and that is deliberate rather than missing: the
    builder writes no timestamp, because a timestamp is exactly what would
    stop two runs producing byte-identical output.
    """
    path = REPO / "mobile" / "assets" / "data" / "joint_rom_reference.json"
    if not path.is_file():
        return None
    doc = json.loads(path.read_text("utf-8"))
    rows = doc.get("rows", [])
    return {
        "dataset_id": "joint_rom_reference",
        "dataset_version": doc.get("schema", "joint_rom_reference/v1").split("/")[-1],
        "purpose": (
            "Advisory plausibility bounds for joint range of motion. NOT "
            "exercise thresholds (those are measured from MM-Fit) and NOT a "
            "clinical instrument: the artifact carries clinical_use=false."
        ),
        "status": "AVAILABLE",
        "source_commit": _last_commit_touching(
            "scripts/catalog/build_joint_rom_reference.py"),
        "schema_version": doc.get("schema"),
        "sources": {
            "built_by": "scripts/catalog/build_joint_rom_reference.py",
            "note": (
                "Values recorded in core/DECISION_LOG.md on 2026-08-08 from an "
                "operator poster photograph plus an article, kept there as a "
                "SECOND source for plausibility bounds. They match the "
                "benchmarks the usual clinical references publish, which is "
                "not the same as being cited from one — hence clinical_use="
                "false and no third-party table reproduced."
            ),
        },
        "row_count": len(rows),
        "splits": None,
        "label_schema": sorted({k for r in rows for k in r}),
        "label_provenance": (
            "Per-row `provenance` field, carried on every row rather than "
            "asserted once for the file."
        ),
        "artifact": {
            "path": "mobile/assets/data/joint_rom_reference.json",
            "sha256": _digest(path),
        },
        "created_at": None,
    }


def build() -> dict[str, Any]:
    entries = [
        e for e in
        (_ct1_catalogue(), *_review_batches(), _clinical_worklist(),
         _scanner_unresolved(), _joint_rom_reference())
        if e is not None
    ]
    for e in entries:
        _validate(e)
    return {
        "$comment": [
            "GENERATED by scripts/ml/dataset_registry.py. Do not hand-edit:",
            "every field is read from a real artefact, and CI re-derives this",
            "file and fails on any difference. A hand-typed correction would",
            "be reverted by the next run and would have looked authoritative",
            "in the meantime.",
        ],
        "schema_version": SCHEMA_VERSION,
        "registry_commit": _git_commit(),
        "statuses": list(STATUSES),
        "required_fields": list(REQUIRED),
        "datasets": entries,
        "training_eligibility": (
            "A dataset being registered says nothing about whether it may be "
            "trained on. Holdout-derived data never may: see "
            "scripts/ct1/leakage_guard.py, which refuses any label carrying "
            "split=holdout regardless of how good the label is."
        ),
    }


def _validate(entry: dict[str, Any]) -> None:
    missing = [f for f in REQUIRED if f not in entry]
    if missing:
        raise DatasetRegistryError(
            f"{entry.get('dataset_id')!r} is missing {missing}. A partly "
            "described dataset is worse than an absent one: it looks checked"
        )
    if entry["status"] not in STATUSES:
        raise DatasetRegistryError(
            f"{entry['dataset_id']!r}: status {entry['status']!r} is not one "
            f"of {STATUSES}"
        )
    if entry["status"] == "AVAILABLE":
        artifact = entry.get("artifact") or {}
        if not artifact.get("sha256"):
            raise DatasetRegistryError(
                f"{entry['dataset_id']!r} is AVAILABLE with no artefact "
                "digest. Available means somebody can fetch the bytes and "
                "check they are the right ones"
            )
        path = REPO / artifact["path"]
        if not path.exists():
            raise DatasetRegistryError(
                f"{entry['dataset_id']!r} points at {artifact['path']}, which "
                "is not there"
            )
        if _digest(path) != artifact["sha256"]:
            raise DatasetRegistryError(
                f"{entry['dataset_id']!r}: the file at {artifact['path']} is "
                "not the one this entry describes. Either the dataset was "
                "rebuilt without the registry being regenerated, or it was "
                "edited in place"
            )


def _dump(payload: dict[str, Any]) -> str:
    return json.dumps(payload, ensure_ascii=False, indent=2, sort_keys=True) + "\n"


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--out", default=str(OUT))
    args = ap.parse_args(argv)

    payload = build()
    text = _dump(payload)
    path = Path(args.out)

    if args.check:
        if not path.exists():
            print(f"{path} does not exist; run with --write", file=sys.stderr)
            return 1
        committed = path.read_text(encoding="utf-8")
        # `registry_commit` moves with every commit and is not a claim about
        # the data, so it is excluded from the comparison the way the review
        # batch excludes `source_commit`.
        a = json.loads(committed); b = json.loads(text)
        a.pop("registry_commit", None); b.pop("registry_commit", None)
        if a != b:
            print(
                "DATASET_REGISTRY.json does not match what the artefacts say. "
                "Either a dataset changed without the registry being "
                "regenerated, or the registry was hand-edited.",
                file=sys.stderr,
            )
            return 1
        print(f"registry matches: {len(payload['datasets'])} datasets")
        return 0

    if args.write:
        path.write_text(text, encoding="utf-8")
        print(f"-> {path}")

    for e in payload["datasets"]:
        rows = e["row_count"]
        print(f"  {e['status']:11} {e['dataset_id']:32} "
              f"{'' if rows is None else str(rows) + ' rows'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
