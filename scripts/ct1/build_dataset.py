# -*- coding: utf-8 -*-
"""CT-1 dataset builder — reproducible by construction, not by convention.

    python scripts/ct1/build_dataset.py --out core/ml/datasets
    python -m pytest scripts/ct1/test_ct1.py -q

The registry records ``training_code_commit: UNKNOWN`` for both scanner models,
because the pipeline that produced them is not under version control and nobody
who lacks that directory can regenerate them. That is the failure this file
exists not to repeat, and it is cheaper to avoid now than to fix later.

## What makes it reproducible

Two claims, and they are different:

**Deterministic.** The same inputs produce byte-identical content. No clock, no
RNG, no set iteration order reaching the output. The split assigns each row by
hashing its stable id, so adding a row cannot reshuffle the rows already
assigned — the failure mode of ``random.shuffle`` with a fixed seed, which is
reproducible for a fixed corpus and silently is not the moment the corpus grows.

**Attested.** ``dataset_hash`` covers the content and deliberately excludes the
manifest's own timestamp and the build host, because a hash that changes when
nothing changed cannot be used to prove anything. Two builds an hour apart from
the same commit must produce the same hash, and the test asserts exactly that.

## No images

There is no image, no photograph and no camera data anywhere in this pipeline,
and that is a design constraint rather than a phase. The catalogue rows are
text and structure; the privacy question that blocks the scanner's CT loop
(``core/ml/CT_CANDIDATE_DECISION.md``) does not arise here, and the way to keep
it not arising is to never add the field.
"""
from __future__ import annotations

import argparse
import collections
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from baseline import DATA, REPO, corpus_observations, load, run_checks  # noqa: E402
from label_contract import (  # noqa: E402
    Label,
    LabelSource,
    assert_no_self_training,
    may_train_on,
)

SCHEMA_VERSION = 1
DATASET_ID = "content_qa_catalogue"

#: Rows a build refuses to include, and why. Recorded per row in the manifest
#: rather than silently dropped -- an excluded row that nobody can account for
#: is how a dataset quietly stops representing the thing it is named after.
EXCLUSION_REASONS = ("missing_id", "duplicate_id")


def git_commit() -> str:
    """The commit the inputs were read at, or an honest UNKNOWN."""
    try:
        out = subprocess.run(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"],
            capture_output=True, text=True, timeout=30, check=True,
        )
        return out.stdout.strip() or "UNKNOWN"
    except Exception:
        # Same word the model registry uses for the same situation. Never a
        # placeholder that looks like a real value.
        return "UNKNOWN"


def file_digest(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def source_ref(path: Path) -> str:
    """Repo-relative where possible, absolute where not.

    A build against a path outside the repository is a legitimate thing to do —
    a test does it, and so does anyone pointing this at an export — and it must
    not crash the builder. It is still recorded exactly as given, because a
    manifest that cannot say where its inputs came from is not a manifest.
    """
    try:
        return str(path.resolve().relative_to(REPO)).replace("\\", "/")
    except ValueError:
        return str(path.resolve()).replace("\\", "/")


def split_for(item_id: str, holdout_share: float = 0.2) -> str:
    """Stable per-row assignment.

    Hashed rather than shuffled, so a row's split is a property of the row and
    not of the corpus it arrived in. Adding rows tomorrow moves nobody, which
    is what lets an evaluation set stay comparable across builds.
    """
    h = int(hashlib.sha256(item_id.encode("utf-8")).hexdigest()[:8], 16)
    return "holdout" if (h % 10_000) < holdout_share * 10_000 else "train"


def build(en_path: Path, ru_path: Path, eq_path: Path,
          version: str) -> dict[str, Any]:
    en, ru, eq = load(en_path, ru_path, eq_path)

    included: list[dict[str, Any]] = []
    excluded: list[dict[str, str]] = []
    seen: set[str] = set()
    for row in en:
        rid = row.get("id")
        if not rid:
            excluded.append({"item_id": "", "reason": "missing_id"})
            continue
        if rid in seen:
            excluded.append({"item_id": rid, "reason": "duplicate_id"})
            continue
        seen.add(rid)
        included.append(row)

    labels = run_checks(en, ru, eq)
    by_item: dict[str, list[Label]] = collections.defaultdict(list)
    for l in labels:
        by_item[l.item_id].append(l)

    rows = []
    for row in included:
        rid = row["id"]
        rows.append({
            "item_id": rid,
            "split": split_for(rid),
            # Features are structural and textual. Listed explicitly so a new
            # field cannot join the dataset by being added to the catalogue.
            "features": {
                "title_len": len(row.get("title") or ""),
                "summary_len": len(row.get("summary") or ""),
                "steps_count": len(row.get("steps") or []),
                "steps_chars": sum(len(s) for s in row.get("steps") or []),
                "tips_count": len(row.get("tips") or []),
                "has_equipment": row.get("equipmentId") is not None,
                "equipment_id": row.get("equipmentId"),
                "difficulty": row.get("difficulty"),
                "vendor_group": row.get("vendorGroup"),
                "is_stretch": bool(row.get("isStretch")),
                "contraindication_count": len(row.get("contraindications") or []),
                "muscle_count": len(row.get("muscles") or []),
                "has_ru": rid in ru,
            },
            "labels": [l.to_json() for l in sorted(
                by_item.get(rid, []), key=lambda x: (x.check, str(x.value))
            )],
        })
    rows.sort(key=lambda r: r["item_id"])

    # The rule that cannot be forgotten, because it runs here rather than being
    # written down somewhere. Today it is vacuous -- there are no reviewed
    # labels at all -- and it must stay in place for the day there are.
    train_targets = [
        l for r in rows if r["split"] == "train"
        for l in by_item.get(r["item_id"], []) if may_train_on(l.source)
    ]
    assert_no_self_training(train_targets)

    content = {
        "schema_version": SCHEMA_VERSION,
        "dataset_id": DATASET_ID,
        "dataset_version": version,
        "rows": rows,
    }
    payload = json.dumps(content, ensure_ascii=False, sort_keys=True,
                         separators=(",", ":"))
    dataset_hash = hashlib.sha256(payload.encode("utf-8")).hexdigest()

    counts = collections.Counter(r["split"] for r in rows)
    label_sources = collections.Counter(
        l.source.value for r in rows for l in by_item.get(r["item_id"], [])
    )

    manifest = {
        "dataset_id": DATASET_ID,
        "dataset_version": version,
        "schema_version": SCHEMA_VERSION,
        "source": {
            "catalogue_en": source_ref(en_path),
            "catalogue_ru": source_ref(ru_path),
            "equipment": source_ref(eq_path),
            "sha256": {
                "catalogue_en": file_digest(en_path),
                "catalogue_ru": file_digest(ru_path),
                "equipment": file_digest(eq_path),
            },
        },
        "source_commit": git_commit(),
        "builder": "scripts/ct1/build_dataset.py",
        "rows_included": len(rows),
        "rows_excluded": len(excluded),
        "excluded": excluded,
        "exclusion_reasons": list(EXCLUSION_REASONS),
        "label_sources": dict(sorted(label_sources.items())),
        "reviewed_label_count": sum(
            n for s, n in label_sources.items()
            if may_train_on(LabelSource(s))
        ),
        "transforms": [
            "drop rows without an id",
            "drop the second and later occurrence of a duplicate id",
            "derive structural features; no free text is copied into features",
            "attach deterministic baseline labels per row",
        ],
        "normalisation": "none; feature values are counts, lengths and enums "
                         "taken verbatim from the catalogue",
        "split_strategy": "sha256(item_id) % 10000 < 2000 -> holdout; stable "
                          "under corpus growth",
        "splits": dict(sorted(counts.items())),
        "contains_images": False,
        "contains_personal_data": False,
        "dataset_hash": dataset_hash,
        # Below the hash line on purpose: nothing here is covered by
        # dataset_hash, because a hash that moves when nothing moved is not
        # evidence of anything.
        "built_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    }
    return {"content": content, "manifest": manifest,
            "corpus": corpus_observations(en)}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--en", type=Path, default=DATA / "exercises_vendor.json")
    ap.add_argument("--ru", type=Path, default=DATA / "exercises_vendor.ru.json")
    ap.add_argument("--equipment", type=Path, default=DATA / "equipment.json")
    ap.add_argument("--version", default="v1")
    ap.add_argument("--out", type=Path, default=REPO / "core" / "ml" / "datasets")
    args = ap.parse_args(argv)

    built = build(args.en, args.ru, args.equipment, args.version)
    target = args.out / f"{DATASET_ID}_{args.version}"
    target.mkdir(parents=True, exist_ok=True)
    (target / "manifest.json").write_text(
        json.dumps(built["manifest"], ensure_ascii=False, indent=2,
                   sort_keys=True) + "\n", encoding="utf-8")
    (target / "corpus_observations.json").write_text(
        json.dumps(built["corpus"], ensure_ascii=False, indent=2,
                   sort_keys=True) + "\n", encoding="utf-8")
    (target / "dataset.json").write_text(
        json.dumps(built["content"], ensure_ascii=False, indent=2,
                   sort_keys=True) + "\n", encoding="utf-8")

    m = built["manifest"]
    print(f"{m['dataset_id']} {m['dataset_version']}")
    print(f"  rows      {m['rows_included']} included, {m['rows_excluded']} excluded")
    print(f"  splits    {m['splits']}")
    print(f"  labels    {m['label_sources']}")
    print(f"  reviewed  {m['reviewed_label_count']}")
    print(f"  hash      {m['dataset_hash']}")
    print(f"  commit    {m['source_commit']}")
    print(f"  -> {target}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
