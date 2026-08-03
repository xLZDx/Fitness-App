# -*- coding: utf-8 -*-
"""A bundled still for every vendor clip, cut from the clip itself.

Same job and the same reasoning as `make_posters.py`, at eleven times the
scale, so it is its own script rather than a flag: this one reads the vendor
catalog, works from the transcoded tree, and runs its ffmpeg calls in parallel
because 2,563 sequential extractions is twenty minutes of one core.

WHY BUNDLED, AGAIN

Operator, on the original library: *"мы договаривались что превью картинка
будет сразу а видео подтягивать потом, но этого нет если нет интернета то даже
изначальной картинки не будет"*. Hosting the poster next to the clip fixes the
first half and not the second. These ship inside the app so the first frame is
instant, free, and there with the phone in aeroplane mode.

THE SIZE QUESTION, MEASURED RATHER THAN ASSUMED

The existing 694 posters weigh 3.68 MB — about 5.3 KB each, because these are
3D renders on flat white and JPEG has almost nothing to encode. 2,563 of them
projects to roughly 14 MB against a 241 MB APK.

That is affordable but it is not nothing, so the script prints the real total
and the mean when it finishes. If a future library is photographic rather than
rendered, the same count would cost five times as much and this arithmetic
stops working — which is why the number is printed rather than assumed.

WHY 0.5 SECONDS IN

Frame zero of these renders is often the model standing still before the
movement starts, and on a few it is a blank white flash. Half a second in is
past that on every clip sampled and still the start of the repetition.
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
POSTERS = ROOT / "mobile" / "assets" / "posters"
BUNDLE = Path("D:/bundle/720")

WIDTH = 400
QUALITY = 5  # ffmpeg -q:v, 2 best .. 31 worst


def cut(src: Path, dst: Path) -> tuple[Path, str]:
    dst.parent.mkdir(parents=True, exist_ok=True)
    # Written under a temporary name and renamed on success, for the same
    # reason the transcoder does it: a killed run must not leave a truncated
    # JPEG that the next run counts as done.
    tmp = dst.with_suffix(".partial.jpg")
    result = subprocess.run(
        ["ffmpeg", "-v", "error", "-ss", "0.5", "-i", str(src),
         "-frames:v", "1", "-vf", f"scale={WIDTH}:-2",
         "-q:v", str(QUALITY), str(tmp), "-y"],
        capture_output=True, text=True)
    if result.returncode != 0 or not tmp.exists() or tmp.stat().st_size == 0:
        tmp.unlink(missing_ok=True)
        return dst, result.stderr.strip()[:160] or "ffmpeg produced nothing"
    tmp.replace(dst)
    return dst, ""


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jobs", type=int, default=12)
    ap.add_argument("--limit", type=int, default=0)
    args = ap.parse_args()

    rows = json.loads(CATALOG.read_text(encoding="utf-8"))
    work: list[tuple[Path, Path, str, str]] = []
    for row in rows:
        for body, key in sorted((row.get("video") or {}).items()):
            src = BUNDLE / key
            rel = f"assets/posters/{body}/{row['id']}.jpg"
            work.append((src, ROOT / "mobile" / rel, row["id"], body))
    if args.limit:
        work = work[: args.limit]

    todo = [w for w in work if not (w[1].exists() and w[1].stat().st_size > 0)]
    print(f"{len(work)} posters wanted, {len(work) - len(todo)} already there, "
          f"{len(todo)} to cut, {args.jobs} at a time")

    missing_source = [w for w in todo if not w[0].exists()]
    if missing_source:
        print(f"  {len(missing_source)} have no clip on disk — skipped")
        for w in missing_source[:5]:
            print(f"    {w[0]}")
    todo = [w for w in todo if w[0].exists()]

    made = failed = 0
    with concurrent.futures.ThreadPoolExecutor(max_workers=args.jobs) as pool:
        futures = {pool.submit(cut, s, d): (s, d, i, b) for s, d, i, b in todo}
        for fut in concurrent.futures.as_completed(futures):
            _, _, exercise_id, body = futures[fut]
            _, err = fut.result()
            if err:
                failed += 1
                print(f"  FAILED {exercise_id}/{body}: {err}")
                continue
            made += 1
            if made % 200 == 0:
                print(f"  {made}/{len(todo)}", flush=True)

    # The poster map goes back into the catalog, keyed the same way as `video`.
    for row in rows:
        poster = {}
        for body in (row.get("video") or {}):
            rel = f"assets/posters/{body}/{row['id']}.jpg"
            if (ROOT / "mobile" / rel).exists():
                poster[body] = rel
        if poster:
            row["poster"] = poster
    CATALOG.write_text(
        json.dumps(rows, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    total = sum(f.stat().st_size for f in POSTERS.rglob("*.jpg"))
    count = sum(1 for _ in POSTERS.rglob("*.jpg"))
    print(f"\ncut {made}, failed {failed}")
    print(f"{sum(1 for r in rows if r.get('poster'))} vendor exercises carry a poster")
    print(f"{count} poster files, {total / 2**20:.2f} MB total, "
          f"{total / max(1, count) / 1024:.1f} KB each")


if __name__ == "__main__":
    main()
