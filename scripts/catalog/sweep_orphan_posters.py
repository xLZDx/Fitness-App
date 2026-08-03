# -*- coding: utf-8 -*-
"""Delete the poster stills that no clip stands behind any more.

WHY THIS MATTERS MORE THAN DISK SPACE

A poster is cut FROM its clip -- `ExerciseItem.poster` says so: *"Cut from the
clip itself, so the poster IS the video's first frame"*. So a still cut from an
unlicensed clip is a frame of unlicensed footage, shipped inside the APK. When
`relicense_legacy_catalog.py` removed the scaffold clips it left 485 such
stills referenced by the catalog and on disk.

They are also unreachable: the app only ever draws a poster underneath its own
video, and H1 already hides an exercise that has no video. So every one of
these is a file that cannot be displayed and should not be distributed.

WHAT IT DOES

1. Drops any `poster` entry whose body has no matching `video` body, in BOTH
   catalogs -- they share `assets/posters/{girl,men}/` and a sweep that read
   only one would delete the other's stills.
2. Deletes every `.jpg` under `assets/posters/` that neither catalog names.

Usage:
    python scripts/catalog/sweep_orphan_posters.py           # measure
    python scripts/catalog/sweep_orphan_posters.py --write
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "mobile" / "assets"
CATALOGS = [ASSETS / "data" / "exercises.json", ASSETS / "data" / "exercises_vendor.json"]
POSTERS = ASSETS / "posters"


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    referenced: set[Path] = set()
    dropped = 0

    for path in CATALOGS:
        catalog = json.loads(path.read_text(encoding="utf-8"))
        for entry in catalog:
            poster = entry.get("poster") or {}
            if not poster:
                continue
            video = entry.get("video") or {}
            keep = {b: p for b, p in poster.items() if b in video}
            dropped += len(poster) - len(keep)
            if keep:
                entry["poster"] = keep
            else:
                entry.pop("poster", None)
            for rel in keep.values():
                # Catalog paths are 'assets/posters/...' relative to mobile/.
                referenced.add((ROOT / "mobile" / rel).resolve())
        if args.write:
            path.write_text(
                json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
            )

    on_disk = sorted(POSTERS.rglob("*.jpg"))
    orphans = [p for p in on_disk if p.resolve() not in referenced]
    freed = sum(p.stat().st_size for p in orphans)

    print(f"  {dropped:5}  poster references dropped (their clip is gone)")
    print(f"  {len(on_disk):5}  poster files on disk")
    print(f"  {len(orphans):5}  referenced by neither catalog -> delete")
    print(f"  {freed / 1e6:5.1f} MB freed")

    if args.write:
        for p in orphans:
            p.unlink()
        for d in sorted(POSTERS.rglob("*"), reverse=True):
            if d.is_dir() and not any(d.iterdir()):
                d.rmdir()
        print(f"\ndeleted {len(orphans)} files")
    else:
        print("\nnothing written -- pass --write to apply")


if __name__ == "__main__":
    main()
