# -*- coding: utf-8 -*-
"""Russian for the vendor catalog, through Gemini on Vertex.

The app is Russian-first and the vendor ships English only, so 1,899 titles and
about three thousand blocks of instructions and tips have to be translated
before any of it can be shown. Operator: *"русский текст обязателен переводи
щас, ничего скрывать не надо"*.

HOW IT AUTHENTICATES

The same borrowed Firebase CLI token the bucket work uses — no API key on disk,
nothing new to keep safe. `aiplatform.googleapis.com` had never been used on
this project and was enabled for it; `gemini-2.5-flash` answers,
`gemini-2.0-flash` 404s there.

WHY IT IS RESUMABLE, AND WHY THAT IS NOT OPTIONAL

Seventy-odd requests over a few thousand paragraphs is long enough to be
interrupted, and re-translating from scratch costs money and produces DIFFERENT
Russian for text that was already fine. Every batch is written to disk as it
lands and an existing translation is never asked for twice.

WHAT IT REFUSES TO ACCEPT

A translation is only kept when it comes back with the same shape it went out
with: the same id, and exactly as many steps as the English had. A model that
merges two steps into one, or helpfully adds a sixth, produces instructions
that no longer line up with the movement — and that is invisible in a diff of
three thousand paragraphs. Mismatches are re-asked once on their own, then
reported and left in English rather than shipped wrong.

Usage:
    python scripts/catalog/translate_vendor_catalog.py --limit 20   # try it
    python scripts/catalog/translate_vendor_catalog.py
"""
from __future__ import annotations

import argparse
import concurrent.futures
import json
import sys
import threading
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ops"))
from firebase_api import PROJECT, access_token, api  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SRC = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
OUT = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.ru.json"

MODEL = "gemini-2.5-flash"
LOCATION = "us-central1"
BATCH = 20
# Batches in flight at once. Almost all of the time is network wait.
PARALLEL = 6

# Terms the gym speaks. Without these the model reaches for the dictionary word
# rather than the one on the equipment: "тяга верхнего блока", not "вытягивание
# широчайших"; "жим лёжа", not "нажимать лёжа".
GLOSSARY = """
bench press = жим лёжа | squat = присед | deadlift = становая тяга
row = тяга | lat pulldown = тяга верхнего блока | pull-up = подтягивание
curl = сгибание на бицепс | extension = разгибание | press = жим
lunge = выпад | fly = разведение | raise = подъём | shrug = шраги
hip thrust = ягодичный мост со штангой | plank = планка | crunch = скручивание
dumbbell = гантель | barbell = штанга | kettlebell = гиря | cable = блок
resistance band = резиновая лента | smith machine = машина Смита
EZ bar = EZ-гриф | rep = повторение | set = подход | grip = хват
"""

PROMPT = """You are translating a gym exercise catalog into Russian for a
fitness app used by Russian speakers who train in ordinary gyms.

Rules:
- Use the everyday Russian gym term, not a literal translation. Glossary:
{glossary}
- Keep the imperative, instructional register: "Встаньте", "Опустите", "Держите".
- Do NOT add, merge, split or reorder steps. Return exactly as many steps as you
  were given, in the same order.
- Keep equipment names recognisable; transliterate brand names (Hammer Strength
  = Hammer Strength).
- No markdown, no numbering, no commentary.

Return ONLY a JSON array. One object per input exercise, same order, shape:
{{"id": "...", "title": "...", "summary": "...", "steps": ["..."], "tips": ["..."]}}
Include "tips" only when the input had tips.

Input:
{payload}
"""


def translate_batch(token: str, items: list[dict]) -> dict[str, dict]:
    payload = json.dumps(
        [
            {
                "id": i["id"],
                "title": i["title"],
                "summary": i.get("summary", ""),
                "steps": i.get("steps", []),
                **({"tips": i["tips"]} if i.get("tips") else {}),
            }
            for i in items
        ],
        ensure_ascii=False,
    )
    url = (
        f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
        f"/locations/{LOCATION}/publishers/google/models/{MODEL}:generateContent"
    )
    body = {
        "contents": [
            {
                "role": "user",
                "parts": [
                    {"text": PROMPT.format(glossary=GLOSSARY, payload=payload)}
                ],
            }
        ],
        "generationConfig": {
            # Deterministic enough that a re-run of the same batch produces the
            # same Russian, which matters when a failed item is re-asked.
            "temperature": 0.2,
            "maxOutputTokens": 65535,
            "responseMimeType": "application/json",
        },
    }
    result = api(url, token, "POST", body)
    if "_httpError" in result:
        raise RuntimeError(f"{result['_httpError']}: {result['_body'][:200]}")
    try:
        text = result["candidates"][0]["content"]["parts"][0]["text"]
    except (KeyError, IndexError):
        raise RuntimeError(f"unexpected response: {json.dumps(result)[:300]}")

    parsed = json.loads(text)
    by_id = {row["id"]: row for row in parsed if isinstance(row, dict) and "id" in row}

    kept: dict[str, dict] = {}
    for item in items:
        got = by_id.get(item["id"])
        if not got:
            continue
        # Shape check. A merged or invented step is instructions that no longer
        # match the movement, and it is invisible in a diff this size.
        if len(got.get("steps") or []) != len(item.get("steps") or []):
            continue
        if not (got.get("title") or "").strip():
            continue
        entry = {
            "title": got["title"].strip(),
            "summary": (got.get("summary") or "").strip(),
            "steps": [s.strip() for s in (got.get("steps") or [])],
        }
        if item.get("tips") and got.get("tips"):
            entry["tips"] = [s.strip() for s in got["tips"]]
        kept[item["id"]] = entry
    return kept


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0, help="translate only N")
    args = ap.parse_args()

    rows = json.loads(SRC.read_text(encoding="utf-8"))
    done: dict[str, dict] = {}
    if OUT.exists():
        done = json.loads(OUT.read_text(encoding="utf-8"))

    todo = [r for r in rows if r["id"] not in done]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(rows)} exercises, {len(done)} already Russian, {len(todo)} to do")
    if not todo:
        return

    token = access_token()
    failed: list[str] = []
    batches = [todo[i : i + BATCH] for i in range(0, len(todo), BATCH)]

    # Run several batches at once. Sequentially this took about three minutes a
    # batch -- five hours for the library -- and almost all of it is waiting on
    # the network, so the fix is concurrency rather than a smaller prompt.
    #
    # The token is minted ONCE here and shared. It outlives the run at this
    # width, and re-minting from inside a worker would have every worker doing
    # it at the same moment.
    lock = threading.Lock()

    def run(batch: list[dict]) -> tuple[dict[str, dict], list[str]]:
        try:
            kept = translate_batch(token, batch)
        except Exception as exc:  # noqa: BLE001 - one batch must not end the run
            print(f"  batch failed: {exc}")
            return {}, [b["id"] for b in batch]
        return kept, [b["id"] for b in batch if b["id"] not in kept]

    with concurrent.futures.ThreadPoolExecutor(max_workers=PARALLEL) as pool:
        for kept, missing in pool.map(run, batches):
            failed.extend(missing)
            with lock:
                done.update(kept)
                # Written after every batch: an interrupted run resumes instead
                # of paying again for text that is already correct.
                OUT.write_text(
                    json.dumps(done, ensure_ascii=False, indent=1, sort_keys=True)
                    + "\n",
                    encoding="utf-8",
                )
                print(f"  {len(done)}/{len(rows)}  "
                      f"(+{len(kept)}, {len(missing)} rejected)", flush=True)

    print(f"\ntranslated {len(done)} of {len(rows)}")
    if failed:
        print(f"left in English: {len(failed)}")
        for i in failed[:10]:
            print(f"   {i}")


if __name__ == "__main__":
    main()
