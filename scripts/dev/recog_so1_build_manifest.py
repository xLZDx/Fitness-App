"""Derive the SO1 observation manifest from the frozen RECOG-C1 arm manifest.

The manifest is the ONLY thing the SO1 runner is allowed to transmit. GPT-PM's
MAJOR 1 on plan revision 1 was that recording the hash of an image AFTER it was
sent is forensics, not a frozen-dataset rule: the expected digest has to exist
before the call so the runner can refuse a file whose bytes have changed. So
this script writes `observation_id, source_photo_id, arm, image_path,
expected_sha256` for all 104 observations, taking every digest from
`RECOG_C1_ARM_MANIFEST_2026-09-05.csv` -- arm A the original photograph's
digest, arm B the scanner-crop digest the same frozen file already records.

Nothing here recomputes a hash from the images to decide what is expected. The
frozen manifest decides; the images are verified AGAINST it, both here and again
in the runner immediately before each request. A corpus that has been moved,
re-encoded, or re-cropped therefore fails loudly rather than being measured
quietly.

`image_path` is deliberately relative to a root passed at run time rather than
baked in. The corpus lives outside the repository (the operator's photographs
are not committed -- only contact sheets are), currently in this session's
scratchpad, and a path recorded today would be wrong the moment that directory
is cleaned. The digest is the identity; the path is only a hint about where to
look, and the runner refuses on the digest, never on the path.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
ARM_MANIFEST = REPO / "core" / "plans" / "RECOG_C1_ARM_MANIFEST_2026-09-05.csv"
OUT = REPO / "core" / "plans" / "RECOG_SO1_OBSERVATION_MANIFEST_2026-09-07.csv"

FIELDS = ["observation_id", "source_photo_id", "arm", "image_path", "expected_sha256"]


def read_arm_manifest(path: Path) -> list[dict[str, str]]:
    rows = list(csv.DictReader(path.read_text("utf-8").splitlines()))
    if len(rows) != 52:
        raise SystemExit(f"{path.name}: expected 52 source photographs, found {len(rows)}")
    return rows


def build(rows: list[dict[str, str]]) -> list[dict[str, str]]:
    """One row per (photograph, arm). Arm A is the full frame, arm B the crop.

    `source_photo_id` is the arm-A digest, which RECOG-C1 already uses as the
    `image_id` in the ground truth -- so the pairing that the clustered
    permutation test depends on is the frozen one, not a new invention.
    """
    out: list[dict[str, str]] = []
    for r in rows:
        source = r["image_id_sha256_original"]
        for arm, digest in (("A", r["image_id_sha256_original"]), ("B", r["arm_b_sha256"])):
            if not digest or len(digest) != 64:
                raise SystemExit(f"{r['source_file']} arm {arm}: no usable sha256 in the frozen manifest")
            out.append(
                {
                    "observation_id": f"{source}:{arm}",
                    "source_photo_id": source,
                    "arm": arm,
                    "image_path": f"arm_{arm.lower()}/{r['source_file']}",
                    "expected_sha256": digest,
                }
            )
    return out


def write(rows: list[dict[str, str]], path: Path) -> None:
    # LF and QUOTE_ALL, matching the other frozen RECOG-C1 CSVs, so the sealed
    # digest survives a fresh checkout on a machine with core.autocrlf=true.
    with path.open("w", encoding="utf-8", newline="\n") as fh:
        w = csv.DictWriter(fh, fieldnames=FIELDS, quoting=csv.QUOTE_ALL, lineterminator="\n")
        w.writeheader()
        w.writerows(rows)


def verify_against_corpus(rows: list[dict[str, str]], root: Path) -> int:
    """Re-hash every image under `root` and compare with the frozen expectation.

    Returns the number of mismatches. A missing file counts as a mismatch: the
    point of this check is that the corpus on disk IS the frozen corpus, and
    "absent" fails that just as surely as "different".
    """
    bad = 0
    for r in rows:
        p = root / r["image_path"]
        if not p.is_file():
            print(f"  MISSING  {r['observation_id']}  {p}")
            bad += 1
            continue
        got = hashlib.sha256(p.read_bytes()).hexdigest()
        if got != r["expected_sha256"]:
            print(f"  MISMATCH {r['observation_id']}  expected {r['expected_sha256'][:16]}... got {got[:16]}...")
            bad += 1
    return bad


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="write the manifest to core/plans/")
    ap.add_argument("--verify-corpus", metavar="ROOT", help="re-hash the images under ROOT against the manifest")
    args = ap.parse_args(argv)

    rows = build(read_arm_manifest(ARM_MANIFEST))
    ids = [r["observation_id"] for r in rows]
    if len(set(ids)) != len(ids):
        raise SystemExit("duplicate observation_id -- the arm manifest is not what this script assumes")
    sources = {r["source_photo_id"] for r in rows}
    print(f"{len(rows)} observations across {len(sources)} source photographs")

    if args.write:
        write(rows, OUT)
        digest = hashlib.sha256(OUT.read_bytes()).hexdigest()
        print(f"wrote {OUT.relative_to(REPO)}  sha256 {digest}")

    if args.verify_corpus:
        root = Path(args.verify_corpus)
        print(f"verifying image bytes under {root}")
        bad = verify_against_corpus(rows, root)
        print("every image matches the frozen digest" if bad == 0 else f"{bad} observation(s) do NOT match")
        return 1 if bad else 0
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
