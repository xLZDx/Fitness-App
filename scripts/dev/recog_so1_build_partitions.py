"""RECOG-SO1 revision 2: split the frozen observation list into four partitions.

WHY FOUR. Revision 1's run proved arithmetically that the experiment does not
fit in one day on this tier. A clean 104-observation pass with zero retries
costs 2,153 x 104 = 223,962 input tokens against an organisation-wide ceiling of
200,000 tokens per day. Four partitions, at least 24 hours apart, is what makes
the same 104 observations fit inside a limit they cannot fit inside at once.

THE ALLOCATION IS GENERATED, NOT DESCRIBED. Within each ground-truth kind,
sources are ordered by the ascending hex of sha256(source_photo_id) and dealt
round-robin with a per-kind offset:

    partition = (index + offset) mod 4      offset 0 for canonical_single
                                            offset 2 for multiple

The two offsets differ because 26 sources dealt four ways gives 7, 7, 6, 6 --
not 6.5 each. With both kinds at offset 0 the partitions would hold 14, 14, 12,
12 sources, not 13 apiece. Offsetting `multiple` by 2 lands its two sevens on
canonical_single's two sixes. The generated counts are 7+6 / 7+6 / 6+7 / 6+7:
13 sources and 26 observations per partition, 26 canonical_single and 26
multiple in total.

Ordering by the hash of the source id rather than by position in the manifest
makes the allocation a property of the corpus rather than of the file, so a
row-shuffled input regenerates byte-identical output.

BLINDNESS IS PRESERVED BY EMITTING FOUR SEPARATE FILES. Each partition manifest
carries EXACTLY the columns revision 1's closed schema allows and not one more.
No `partition` column and no `kind` column is written, because the runner's
input must stay free of anything derived from the ground truth -- and partition
membership is derived from the ground truth. The partition is named by the file
the runner is pointed at, never by a field inside it.

This program reads the ground truth. The RUNNER never does.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import io
import sys
from collections import defaultdict
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
PLANS = REPO / "core" / "plans"

MANIFEST = PLANS / "RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv"
GROUND_TRUTH = PLANS / "RECOG_C1_GROUND_TRUTH_2026-09-05.csv"

#: Identical to the runner's own closed schema. Written in this order.
COLUMNS = ["observation_id", "source_photo_id", "arm", "image_path", "expected_sha256"]

PARTITIONS = 4
OFFSETS = {"canonical_single": 0, "multiple": 2}

#: What the algorithm must produce, stated here so the assertion is a
#: pre-registered expectation rather than a description of whatever came out.
EXPECTED_SOURCES_PER_PARTITION = {
    1: {"canonical_single": 7, "multiple": 6},
    2: {"canonical_single": 7, "multiple": 6},
    3: {"canonical_single": 6, "multiple": 7},
    4: {"canonical_single": 6, "multiple": 7},
}


def source_order_key(source_photo_id: str) -> str:
    return hashlib.sha256(source_photo_id.encode("utf-8")).hexdigest()


def load_kinds(ground_truth: Path) -> dict[str, str]:
    """source_photo_id -> ground-truth kind, refusing any source whose two arms disagree."""
    kinds: dict[str, set[str]] = defaultdict(set)
    for r in csv.DictReader(ground_truth.read_text("utf-8").splitlines()):
        kinds[r["image_id"]].add(r["gt_kind"])
    out: dict[str, str] = {}
    for source, values in kinds.items():
        if len(values) != 1:
            raise SystemExit(
                f"{source}: ground truth gives it {sorted(values)} across arms. The partition "
                "algorithm carries both arms of a source together, which is only licensed while "
                "kind is a property of the photograph."
            )
        out[source] = next(iter(values))
    return out


def assign(sources_by_kind: dict[str, list[str]]) -> dict[str, int]:
    """source_photo_id -> partition number (1-based)."""
    assignment: dict[str, int] = {}
    for kind, sources in sources_by_kind.items():
        offset = OFFSETS[kind]
        for index, source in enumerate(sorted(sources, key=source_order_key)):
            assignment[source] = ((index + offset) % PARTITIONS) + 1
    return assignment


def build(manifest: Path, ground_truth: Path) -> tuple[dict[int, str], dict[int, dict[str, int]]]:
    """Return (partition -> CSV text, partition -> per-kind source counts)."""
    rows = list(csv.DictReader(manifest.read_text("utf-8").splitlines()))
    if not rows:
        raise SystemExit(f"{manifest.name}: empty")
    present = set(rows[0])
    if present != set(COLUMNS):
        raise SystemExit(
            f"{manifest.name}: expected exactly {COLUMNS}, found {sorted(present)}. "
            "A partition manifest must carry the runner's closed schema unchanged."
        )

    kinds = load_kinds(ground_truth)
    sources_by_kind: dict[str, list[str]] = defaultdict(list)
    for source in {r["source_photo_id"] for r in rows}:
        if source not in kinds:
            raise SystemExit(f"{source}: in the observation manifest but absent from the ground truth")
        sources_by_kind[kinds[source]].append(source)

    assignment = assign(sources_by_kind)

    # Rows are emitted in the INPUT manifest's own order within each partition,
    # except that the input order itself is normalised by sorting on the two
    # frozen identity fields -- so a row-shuffled input cannot change the bytes.
    texts: dict[int, str] = {}
    counts: dict[int, dict[str, int]] = {}
    for partition in range(1, PARTITIONS + 1):
        mine = [r for r in rows if assignment[r["source_photo_id"]] == partition]
        mine.sort(key=lambda r: (source_order_key(r["source_photo_id"]), r["arm"]))
        buf = io.StringIO(newline="")
        writer = csv.DictWriter(buf, fieldnames=COLUMNS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        writer.writeheader()
        for r in mine:
            writer.writerow({c: r[c] for c in COLUMNS})
        texts[partition] = buf.getvalue()
        counts[partition] = {
            kind: len({r["source_photo_id"] for r in mine if kinds[r["source_photo_id"]] == kind})
            for kind in sorted(OFFSETS)
        }
    return texts, counts


def check(counts: dict[int, dict[str, int]], texts: dict[int, str]) -> list[str]:
    """Every claim the pre-registration makes about the partitions, as assertions."""
    problems: list[str] = []
    for partition, expected in EXPECTED_SOURCES_PER_PARTITION.items():
        got = counts[partition]
        if got != expected:
            problems.append(f"partition {partition}: expected sources {expected}, generated {got}")
        n_sources = sum(got.values())
        if n_sources != 13:
            problems.append(f"partition {partition}: {n_sources} sources, expected 13")
        n_rows = len(texts[partition].strip().splitlines()) - 1
        if n_rows != 26:
            problems.append(f"partition {partition}: {n_rows} observations, expected 26")
    for kind in sorted(OFFSETS):
        total = sum(counts[p][kind] for p in counts)
        if total != 26:
            problems.append(f"{kind}: {total} sources across all partitions, expected 26")
    return problems


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--out-dir", default=str(PLANS), help="where the four partition manifests are written")
    ap.add_argument("--check", action="store_true", help="verify existing files match a fresh generation")
    args = ap.parse_args(argv)

    texts, counts = build(MANIFEST, GROUND_TRUTH)
    problems = check(counts, texts)
    if problems:
        print("REFUSED: the generated partitions do not match the pre-registered allocation.")
        for p in problems:
            print("  " + p)
        return 2

    out_dir = Path(args.out_dir)
    changed = False
    for partition, text in sorted(texts.items()):
        path = out_dir / f"RECOG_SO1_PARTITION_{partition}_R2_2026-09-08.csv"
        if args.check:
            if not path.is_file():
                print(f"MISSING {path.name}")
                changed = True
            elif path.read_text("utf-8") != text:
                print(f"DIFFERS {path.name}")
                changed = True
        else:
            path.write_text(text, encoding="utf-8", newline="")
        c = counts[partition]
        print(
            f"partition {partition}: canonical_single {c['canonical_single']} + multiple {c['multiple']} "
            f"= {sum(c.values())} sources, {len(text.strip().splitlines()) - 1} observations"
        )
    for kind in sorted(OFFSETS):
        print(f"  total {kind}: {sum(counts[p][kind] for p in counts)} sources")
    if args.check and changed:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
