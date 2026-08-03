# -*- coding: utf-8 -*-
"""Find a licensed clip for every legacy exercise that still has none.

WHY NOT MORE NAME MATCHING

The importer matched on words and it was not good enough. It chose
`Archer push up` for "Push-Up" while `Normal Push-up` sat in the same library,
`Kipping Pull Up` for "Pullups" while `pull up normal grip` did, and
`Barbell Silverback Shrug` -- a BENT-OVER shrug -- for "Barbell Shrug". Word
overlap cannot tell one exercise from another because in this domain almost
every added word IS the difference.

Operator: *"сравнивай названия не только один в один но и по смыслу и
содержанию"*.

So this shortlists by name and then asks the model which candidate IS the same
exercise, given our title and our own instructions -- the steps describe the
movement, which is exactly what a filename cannot.

WHAT IT WILL NOT DO

`none` is always an offered answer and the prompt says so twice. A model asked
to choose from a list will choose from the list, and a wrong demonstration
teaches a wrong movement -- worse than no demonstration, which is the rule the
whole catalog is built on.

Every accepted answer is then put through `disqualifying()`, the same guard the
importer uses. Here it does NOT reject -- it FLAGS. The guard was written to
catch a word-overlap heuristic that had no idea what an exercise was, and
against a reasoned answer it produces false alarms: it blocked
`Calf Press On The Leg Press Machine -> Calf raise leg press machine` for
adding the movement "raise", and `Narrow Stance Leg Press -> leg press machine
close stance` for adding the equipment "machine", when a leg press IS a machine.

So a guard hit means the two judgements disagree, and disagreement is exactly
where a frame should be pulled and looked at. Those rows land as `review`.

Usage:
    python scripts/catalog/match_legacy_semantic.py --limit 20   # try it
    python scripts/catalog/match_legacy_semantic.py              # propose all
    python scripts/catalog/match_legacy_semantic.py --write      # apply
"""
from __future__ import annotations

import argparse
import concurrent.futures
import csv
import difflib
import json
import sys
import threading
import urllib.parse
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import PROJECT, access_token, api  # noqa: E402
from import_bundle_clips import disqualifying, load_plan, norm  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
CATALOG = ROOT / "mobile" / "assets" / "data" / "exercises.json"
PROPOSALS = ROOT / "core" / "legacy_match_proposals.csv"

MODEL = "gemini-2.5-flash"
LOCATION = "us-central1"
SHORTLIST = 30
BATCH = 6
PARALLEL = 6

PROMPT = """You are matching exercises in a fitness app's catalog to clips in a
purchased animation library.

For each exercise below, decide which candidate clip demonstrates THE SAME
EXERCISE. Judge by the movement, not by the words: the same exercise can be
named differently, and a name that looks close can be a different exercise.

Rules:
- "Normal Push-up" and "Push-Up" are the same. "Archer push up" is NOT -- it is
  a different, harder movement.
- A different piece of equipment is a different exercise: a machine leg curl is
  not a bodyweight leg curl, a barbell press is not a bodyweight press.
- A named variant is a different exercise: staggered, curtsy, kipping, twisting,
  unilateral, silverback (which means bent-over), front vs back squat.
- A different body position is a different exercise: a floor fly is not a bench
  fly, a pulldown is not a pull-up.

If no candidate is the same exercise, answer "none". Answering "none" is
correct and expected -- the library genuinely does not contain everything.
Never pick the closest one just to have an answer.

Return ONLY a JSON array, one object per exercise, same order:
[{{"id": "...", "choice": "<exact candidate string, or none>",
   "confidence": <0.0-1.0>, "why": "<max 12 words>"}}]

Exercises:
{payload}
"""


def shortlist(title: str, steps: list[str], vendor: dict[str, str]) -> list[str]:
    """The [SHORTLIST] vendor titles most worth asking about.

    Ranked by token overlap AND by sequence similarity: overlap alone buries a
    clip whose name is phrased differently, which is the failure this whole
    script exists to correct.
    """
    ours = set(norm(title))
    scored = []
    for stem, real in vendor.items():
        theirs = set(stem.split())
        if not theirs:
            continue
        overlap = len(ours & theirs) / len(ours | theirs)
        ratio = difflib.SequenceMatcher(None, title.lower(), real.lower()).ratio()
        scored.append((overlap * 2 + ratio, real))
    scored.sort(reverse=True)
    return [real for _, real in scored[:SHORTLIST]]


def ask(token: str, items: list[dict]) -> list[dict]:
    payload = json.dumps(items, ensure_ascii=False, indent=1)
    url = (
        f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
        f"/locations/{LOCATION}/publishers/google/models/{MODEL}:generateContent"
    )
    body = {
        "contents": [{"role": "user", "parts": [{"text": PROMPT.format(payload=payload)}]}],
        "generationConfig": {
            "temperature": 0.0,
            "maxOutputTokens": 65535,
            "responseMimeType": "application/json",
        },
    }
    result = api(url, token, "POST", body)
    if "_httpError" in result:
        raise RuntimeError(f"{result['_httpError']}: {result['_body'][:200]}")
    text = result["candidates"][0]["content"]["parts"][0]["text"]
    parsed = json.loads(text)
    return [r for r in parsed if isinstance(r, dict) and "id" in r]


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--write", action="store_true",
                    help="apply the proposals already in the CSV")
    args = ap.parse_args()

    catalog = json.loads(CATALOG.read_text(encoding="utf-8"))
    by_id = {e["id"]: e for e in catalog}
    plan = load_plan()
    vendor = {
        stem: urllib.parse.unquote(
            (keys.get("men") or keys.get("girl")).rsplit("/", 1)[-1]
        )[:-4]
        for stem, keys in plan.items()
    }
    by_real = {real.lower(): stem for stem, real in vendor.items()}

    if args.write:
        apply_proposals(catalog, by_id, plan, by_real, vendor)
        return

    todo = [e for e in catalog if not e.get("video")]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(todo)} exercises with no clip; asking about each")

    batches = []
    for i in range(0, len(todo), BATCH):
        chunk = todo[i : i + BATCH]
        batches.append([
            {
                "id": e["id"],
                "exercise": e["title"],
                "instructions": (e.get("steps") or [])[:3],
                "candidates": shortlist(e["title"], e.get("steps") or [], vendor),
            }
            for e in chunk
        ])

    token = access_token()
    lock = threading.Lock()
    answers: list[dict] = []

    def run(batch):
        # Retried once: the failure seen in practice is a malformed JSON reply,
        # which a second attempt at temperature 0 usually does not repeat. A
        # batch that fails twice is dropped rather than ending the run -- its
        # exercises simply keep no clip, which is the safe direction.
        for attempt in (1, 2):
            try:
                return ask(token, batch)
            except Exception as exc:  # noqa: BLE001
                if attempt == 2:
                    print(f"  batch failed twice, skipped: {exc}")
                    return []
        return []

    with concurrent.futures.ThreadPoolExecutor(max_workers=PARALLEL) as pool:
        for got in pool.map(run, batches):
            with lock:
                answers.extend(got)
                print(f"  {len(answers)}/{len(todo)}", flush=True)

    rows = []
    for a in answers:
        entry = by_id.get(a["id"])
        if entry is None:
            continue
        choice = str(a.get("choice") or "none").strip()
        stem = by_real.get(choice.lower(), "")
        verdict, reason = "proposed", str(a.get("why") or "")[:80]
        if choice.lower() == "none" or not choice:
            verdict, stem = "none", ""
        elif not stem:
            # The model wrote a title that is not in the library. Not applied:
            # an invented filename cannot be signed and would 404 on the phone.
            verdict, reason = "hallucinated", f"no such clip: {choice[:60]}"
        else:
            blocked = disqualifying(set(norm(entry["title"])), set(stem.split()))
            if blocked:
                # Flagged, not rejected: see the module docstring. The model and
                # the guard disagree, and that is a reason to look at a frame.
                verdict, reason = "review", blocked
        rows.append({
            "id": a["id"], "title": entry["title"], "verdict": verdict,
            "chosen_clip": choice if verdict in ("proposed", "review") else "",
            "vendor_stem": stem if verdict in ("proposed", "review") else "",
            "confidence": a.get("confidence", ""), "why": reason,
        })

    rows.sort(key=lambda r: (r["verdict"], r["title"]))
    with PROPOSALS.open("w", newline="", encoding="utf-8") as fh:
        w = csv.DictWriter(fh, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(rows)

    import collections
    print(f"\nwrote {PROPOSALS}")
    for name, n in collections.Counter(r["verdict"] for r in rows).most_common():
        print(f"  {n:4}  {name}")
    print("\nnothing applied -- rerun with --write")


def apply_proposals(catalog, by_id, plan, by_real, vendor) -> None:
    if not PROPOSALS.exists():
        sys.exit("no proposals file; run without --write first")
    applied = 0
    for row in csv.DictReader(PROPOSALS.open(encoding="utf-8")):
        if row["verdict"] != "proposed":
            continue
        entry = by_id.get(row["id"])
        keys = plan.get(row["vendor_stem"])
        if entry is None or not keys:
            continue
        video = dict(entry.get("video") or {})
        for body in ("girl", "men"):
            if body in keys:
                video[body] = keys[body]
        entry["video"] = video
        applied += 1
    CATALOG.write_text(
        json.dumps(catalog, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    playable = sum(1 for e in catalog if e.get("video"))
    print(f"applied {applied}; {playable} of {len(catalog)} legacy exercises now play")


if __name__ == "__main__":
    main()
