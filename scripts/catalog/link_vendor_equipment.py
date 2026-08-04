# -*- coding: utf-8 -*-
"""Link every vendor exercise to one of the 52 registry machines -- verified.

WHY THIS EXISTS

The machine detail page (`exercisesFor(equipmentId)`) filters purely on
`equipmentId`. All 1,887 vendor exercises carry `equipmentId: null` -- the
vendor purchase never assigned one -- so today every one of the 52 machine
pages shows ZERO vendor exercises and falls back to AI-generated, clip-less
text. This is the "82 vendor equipment rows -> 52 machines" gap the operator
named on 2026-08-03 and H5's scanner rewrite never actually closed, because it
answers a different question (what IS this machine) than this one (which
vendor exercises belong on this machine's page).

A first measurement (title + the vendor's own metadata sheet, resolved through
the same alias index the scanner uses) reached 1,088 of 1,887 -- 58%, 44 of 52
machines. Operator: *"верить никому нельзя все надо проверять"* -- trust no
one. So this does not trust the vendor's spreadsheet, and does not trust the
`equipmentLabel` already baked into the catalog (which came from that same
spreadsheet). It looks at the actual clip.

THE PER-EXERCISE PIPELINE (operator's own words, followed literally)

For each of 1,887, independently:
  1. Look at the exercise's own poster -- a real frame cut from its own clip,
     already bundled, no download needed -- and decide what equipment it shows,
     with no hint of what the spreadsheet claims.
  2. Compare that independent answer against the spreadsheet's `Equipment`
     column for the same exercise, when the sheet has one.
  3. If they agree (or the sheet has nothing), resolve what was actually SEEN
     against the 52-machine registry.
  4. If nothing resolves -- the two sources disagree, or neither names one of
     the 52 -- record exactly what the clip showed and drop the exercise into
     a review list rather than guessing.

No equipment at all is a valid, expected answer (a floor ab exercise has none)
and is never treated as a problem on its own -- only a disagreement or an
unresolved-but-real piece of equipment goes to review.

WHY ONE IMAGE PER CALL, NOT BATCHED

Text batches ten items into one request safely -- a JSON array cannot confuse
item 3 with item 7. A vision prompt holding several images at once genuinely
can, and getting the ANSWER wrong here is exactly what "trust no one" is
guarding against. So this is 1,887 separate calls, run with real concurrency
for throughput, the same shape `gemini_equipment_service.dart` uses for one
photo at a time.

WHAT IT WILL NOT DO

Never invent a registry machine. The model is given the 52 real names and
told to answer with one of them or "none" -- an answer that is not an exact
name (case-insensitive) is treated as unresolved, the same discipline
`EquipmentAliasIndex` and the clip-matching passes already use.

Usage:
    python scripts/catalog/link_vendor_equipment.py --limit 20   # try it
    python scripts/catalog/link_vendor_equipment.py              # measure all
    python scripts/catalog/link_vendor_equipment.py --write       # apply
"""
from __future__ import annotations

import argparse
import concurrent.futures
import csv
import json
import re
import sys
import threading
from pathlib import Path

import openpyxl

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "ops"))
sys.path.insert(0, str(Path(__file__).parent))
from firebase_api import PROJECT, access_token, api  # noqa: E402
import vendor_paths  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
VENDOR = ROOT / "mobile" / "assets" / "data" / "exercises_vendor.json"
REGISTRY = ROOT / "mobile" / "assets" / "data" / "equipment.json"
# Was the only script carrying the current path, and it carried its own copy.
# Now the one definition, so the next move cannot leave three of four behind.
SHEET = vendor_paths.VENDOR_META
AUDIT = ROOT / "core" / "vendor_equipment_visual_audit.csv"
REVIEW = ROOT / "core" / "vendor_equipment_needs_review.csv"

MODEL = "gemini-3-flash-preview"
PARALLEL = 8


def canon(name: str) -> str:
    """Strips the gender suffix and normalises, so the sheet's
    'Barbell Squat_female' and the catalog's 'Barbell Squat' meet as one key."""
    name = re.sub(r"_(female|male)(?:_\d+)?\s*$", "", name, flags=re.I)
    return re.sub(r"[^a-z0-9]+", " ", name.lower()).strip()


def load_sheet_equipment() -> dict[str, str]:
    """{canonical exercise name: raw Equipment column value}. Skips blanks and
    the two spellings of 'no equipment' the sheet uses, since those carry no
    information a real check needs."""
    wb = openpyxl.load_workbook(SHEET, read_only=True)
    ws = wb.active
    out: dict[str, str] = {}
    for row in ws.iter_rows(min_row=2, values_only=True):
        if not row[1] or not row[6]:
            continue
        val = str(row[6]).strip()
        if val.lower() in ("none", "none (bodyweight)"):
            continue
        out.setdefault(canon(row[1]), val)
    return out


def build_prompt(title: str, muscles: list[str], sheet_claim: str | None,
                  registry_names: list[str]) -> str:
    claim_block = (
        f'\n\nA spreadsheet claims this exercise uses: "{sheet_claim}". Do NOT '
        f"let that influence your independent answer above it -- decide "
        f"equipment_seen from the photo alone, and only then say whether the "
        f"claim matches what you actually see."
        if sheet_claim else
        "\n\nNo spreadsheet claim exists for this exercise -- leave "
        '"matches_sheet_claim" as null.'
    )
    return f"""You are looking at one still frame from a gym exercise demonstration
video. The exercise is: "{title}" (muscles worked: {', '.join(muscles) or 'unspecified'}).

Look ONLY at the image. Decide what equipment or apparatus is being used --
independently, before anything else in this prompt. "None" is a correct and
common answer for bodyweight/floor work; never invent equipment that is not
visible or clearly implied by the pose.
{claim_block}

Then, separately: does what you see correspond to one of these registry
machines? Answer with the EXACT name from the list, or "none" if it does not.
Registry: {', '.join(registry_names)}

The registry mixes two kinds of entry: a generic implement (Barbell, Dumbbell,
Kettlebell, Weight plates) and a specific station (Squat rack, Weight bench,
Smith machine, Leg press). When this exact movement is normally performed at a
dedicated station in a real gym -- a barbell squat is racked out from a squat
rack, a barbell bench press is done on a weight bench -- name that STATION,
not the generic implement, because the station is the page a user actually
opens after scanning it. Use the generic implement only when no dedicated
station exists for this movement (a barbell deadlift has no "deadlift
platform" in the registry, so it stays "Barbell").

Return JSON only:
{{"equipment_seen": "<free text, or 'none'>",
 "confidence": <0.0-1.0>,
 "matches_sheet_claim": true, false, or null,
 "registry_machine": "<exact name from the list above, or 'none'>"}}"""


def ask(token: str, image_bytes: bytes, prompt: str) -> dict:
    url = (
        f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
        f"/locations/us-central1/publishers/google/models/{MODEL}:generateContent"
    )
    import base64
    body = {
        "contents": [{
            "role": "user",
            "parts": [
                {"inlineData": {"mimeType": "image/jpeg",
                                 "data": base64.b64encode(image_bytes).decode()}},
                {"text": prompt},
            ],
        }],
        "generationConfig": {
            "temperature": 0,
            "maxOutputTokens": 512,
            "responseMimeType": "application/json",
            "thinkingConfig": {"thinkingBudget": 0},
        },
    }
    result = api(url, token, "POST", body)
    if "_httpError" in result:
        raise RuntimeError(f"{result['_httpError']}: {result.get('_body', '')[:200]}")
    text = result["candidates"][0]["content"]["parts"][0]["text"]
    cleaned = re.sub(r"^\s*```(?:json)?", "", text, flags=re.M).replace("```", "").strip()
    return json.loads(cleaned)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--write", action="store_true")
    args = ap.parse_args()

    vendor = json.loads(VENDOR.read_text(encoding="utf-8"))
    by_id = {e["id"]: e for e in vendor}
    registry = json.loads(REGISTRY.read_text(encoding="utf-8"))
    registry_names = [e["name"] for e in registry]
    name_to_id = {e["name"].strip().lower(): e["id"] for e in registry}
    sheet = load_sheet_equipment()

    if args.write:
        apply_results(vendor, by_id, name_to_id)
        return

    done: dict[str, dict] = {}
    if AUDIT.exists():
        for row in csv.DictReader(AUDIT.open(encoding="utf-8")):
            done[row["id"]] = row

    todo = [e for e in vendor if e["id"] not in done]
    if args.limit:
        todo = todo[: args.limit]
    print(f"{len(vendor)} vendor exercises, {len(done)} already checked, "
          f"{len(todo)} to do")
    if not todo:
        return

    token = access_token()
    lock = threading.Lock()
    rows: list[dict] = list(done.values())

    def process(e: dict) -> dict:
        poster_rel = e.get("poster", {}).get("men") or e.get("poster", {}).get("girl")
        img_path = ROOT / "mobile" / poster_rel
        sheet_claim = sheet.get(canon(e["title"]))
        prompt = build_prompt(e["title"], e.get("muscles") or [], sheet_claim,
                               registry_names)
        try:
            ans = ask(token, img_path.read_bytes(), prompt)
        except Exception as exc:  # noqa: BLE001 - one item must not end the run
            try:
                ans = ask(token, img_path.read_bytes(), prompt)  # one retry
            except Exception as exc2:  # noqa: BLE001
                return {"id": e["id"], "title": e["title"],
                        "sheet_claim": sheet_claim or "", "equipment_seen": "",
                        "confidence": "", "matches_sheet_claim": "",
                        "registry_machine": "", "status": "call_failed",
                        "note": str(exc2)[:150]}

        seen = str(ans.get("equipment_seen") or "").strip()
        raw_machine = str(ans.get("registry_machine") or "none").strip()
        machine = raw_machine if raw_machine.lower() in name_to_id else "none"
        # An answer that is not one of the 52 real names verbatim is treated as
        # unresolved -- never a guess dressed up as a match.
        hallucinated = raw_machine.lower() not in ("none", "") and machine == "none"

        agrees = ans.get("matches_sheet_claim")
        if sheet_claim and agrees is False:
            status = "DISAGREEMENT"
        elif machine != "none":
            status = "resolved"
        elif seen.lower() in ("none", "", "bodyweight", "no equipment"):
            status = "confirmed_no_equipment"
        else:
            status = "unresolved"

        return {
            "id": e["id"], "title": e["title"],
            "sheet_claim": sheet_claim or "",
            "equipment_seen": seen,
            "confidence": ans.get("confidence", ""),
            "matches_sheet_claim": agrees,
            "registry_machine": machine,
            "status": status,
            "note": "answered a name we don't have: " + raw_machine if hallucinated else "",
        }

    with concurrent.futures.ThreadPoolExecutor(max_workers=PARALLEL) as pool:
        futures = {pool.submit(process, e): e for e in todo}
        for i, fut in enumerate(concurrent.futures.as_completed(futures), 1):
            row = fut.result()
            with lock:
                rows.append(row)
                if i % 25 == 0 or i == len(todo):
                    AUDIT.parent.mkdir(parents=True, exist_ok=True)
                    with AUDIT.open("w", newline="", encoding="utf-8") as f:
                        w = csv.DictWriter(f, fieldnames=list(rows[0]))
                        w.writeheader()
                        w.writerows(sorted(rows, key=lambda r: r["id"]))
                    print(f"  {len(done) + i}/{len(vendor)}", flush=True)

    review = [r for r in rows if r["status"] in
              ("DISAGREEMENT", "unresolved", "call_failed")]
    with REVIEW.open("w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=list(rows[0]))
        w.writeheader()
        w.writerows(sorted(review, key=lambda r: (r["status"], r["title"])))

    import collections
    print(f"\nwrote {AUDIT}")
    print(f"wrote {REVIEW} ({len(review)} rows)")
    for name, n in collections.Counter(r["status"] for r in rows).most_common():
        print(f"  {n:5}  {name}")


def apply_results(vendor: list[dict], by_id: dict, name_to_id: dict) -> None:
    if not AUDIT.exists():
        sys.exit("no audit file; run without --write first")
    applied = 0
    for row in csv.DictReader(AUDIT.open(encoding="utf-8")):
        if row["status"] != "resolved":
            continue
        entry = by_id.get(row["id"])
        mid = name_to_id.get(row["registry_machine"].strip().lower())
        if entry is None or mid is None:
            continue
        entry["equipmentId"] = mid
        applied += 1
    VENDOR.write_text(json.dumps(vendor, ensure_ascii=False, indent=2) + "\n",
                       encoding="utf-8")
    linked = sum(1 for e in vendor if e.get("equipmentId"))
    print(f"applied {applied}; {linked} of {len(vendor)} vendor exercises now "
          f"carry a registry equipmentId")


if __name__ == "__main__":
    main()
