# -*- coding: utf-8 -*-
"""Measures the LIVE production Gemini equipment-recognition path's real accuracy
against real gym photos with human-built ground truth.

WHY THIS EXISTS

Before this script, zero accuracy measurement existed anywhere in the repo for
the Gemini vision-based equipment classifier that drives `ScanMatchCard` in the
scanner UI (`functions/src/ai_equipment_recognition.ts` /
`mobile/lib/features/scanner/scanner_page.dart`). `core/CURRENT_STATE.md`
recorded `CT1-human-labels: HUMAN_REVIEW_LABELS = 0` -- a real, open gap. This
script closes the "we have never measured it" part of that gap using real
photos the operator supplied (see `core/ml/eval/gym_photos_ground_truth_2026-09-17.json`).

WHAT IT DOES NOT DO

It does not call the Firebase Callable (`aiEquipmentRecognition`) itself --
that layer's auth/quota/App Check/observability wiring is a SEPARATE concern
already covered by the passed MVP1.G4 gate. This script calls Vertex AI's
`generateContent` REST endpoint directly, replicating the model/location/
prompt/generationConfig/safetySettings that `ai_gateway.ts` and
`ai_equipment_recognition.ts` build server-side, EXACTLY (see the constants
below -- each one cites the source line it mirrors). That is the one thing
this repo has never measured: does the model itself, called the way
production calls it, actually return the right machine name for a real photo.

AUTH

Uses the Firebase CLI's own stored OAuth refresh token via
`scripts/ops/firebase_api.access_token()` -- this machine has no
`gcloud auth application-default login` configured, and re-using the CLI's
already-granted credential is the same pattern that module documents for
Cloud Storage calls. Same account, same project, no new secret.

USAGE

    py -3 core/ml/eval/eval_live_equipment_recognition.py
    py -3 core/ml/eval/eval_live_equipment_recognition.py --limit 5   # smoke test
"""
from __future__ import annotations

import argparse
import base64
import json
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(REPO_ROOT / "scripts" / "ops"))
from firebase_api import access_token  # noqa: E402

MANIFEST = Path(__file__).resolve().parent / "gym_photos_ground_truth_2026-09-17.json"
RESULTS_OUT = Path(__file__).resolve().parent / f"eval_results_{time.strftime('%Y-%m-%d')}.json"

# --- Exact mirror of functions/src/ai_gateway.ts -----------------------------
PROJECT = "fitness-app-korostelev"          # ai_gateway.ts:139
LOCATION = "global"                          # ai_gateway.ts:132
MODEL = "gemini-3.6-flash"                   # ai_gateway.ts:85
SAFETY_CATEGORIES = [                        # ai_gateway.ts:97-100
    "HARM_CATEGORY_HARASSMENT",
    "HARM_CATEGORY_HATE_SPEECH",
    "HARM_CATEGORY_SEXUALLY_EXPLICIT",
    "HARM_CATEGORY_DANGEROUS_CONTENT",
]
SAFETY_THRESHOLD = "BLOCK_MEDIUM_AND_ABOVE"  # ai_gateway.ts:101

# --- Exact mirror of functions/src/ai_equipment_recognition.ts ---------------
CANONICAL_MACHINES = [
    "treadmill", "rowing machine", "squat rack", "bench press station",
    "cable machine", "leg press", "lat pulldown", "barbell", "dumbbells",
    "kettlebell", "elliptical trainer", "exercise bike", "recumbent bike",
    "stair climber", "air bike", "ski erg", "smith machine",
    "hack squat machine", "leg extension machine", "leg curl machine",
    "hip abductor machine", "glute kickback machine", "calf raise machine",
    "chest press machine", "pec deck", "shoulder press machine",
    "seated row machine", "t-bar row", "assisted pull-up machine",
    "pull-up bar", "dip station", "preacher curl bench",
    "biceps curl machine", "triceps extension machine", "ab crunch machine",
    "rotary torso machine", "back extension bench", "captain's chair",
    "flat bench", "ez curl bar", "weight plates", "resistance bands",
    "suspension trainer", "medicine ball", "battle ropes", "plyo box",
    "punching bag", "foam roller",
    "stability ball", "skipping rope", "ab wheel", "parallettes",
    "seated dip machine", "multi hip machine", "lateral raise machine",
    "sissy squat machine", "agility ladder", "mini trampoline",
    "balance board", "yoga blocks", "weighted sled", "ab mat", "bosu ball",
    "sliding discs", "sandbag", "gymnastic rings", "tyre",
    "vertical pole", "outdoor air walker",
    "push-up blocks", "aerobic step",
]


def build_prompt() -> str:
    """Verbatim copy of ai_equipment_recognition.ts buildPrompt()."""
    return (
        "You identify gym equipment. Look ONLY at the machine closest to the center of\n"
        "the photo; ignore machines at the edges — gyms are crowded and the user aimed\n"
        "the center of the frame at the one they mean.\n\n"
        'Answer with JSON only:\n'
        '{"machine": "<name from the list below, or unknown>", "confidence": <0.0-1.0>,\n'
        ' "alternatives": [{"machine": "<name>", "confidence": <0.0-1.0>}]}\n\n'
        '"confidence" is YOUR honest certainty; use low values when unsure. Give up to\n'
        "2 alternatives only when they are genuinely plausible. Machine list:\n"
        f"{', '.join(CANONICAL_MACHINES)}"
    )


def endpoint_url() -> str:
    # Global-endpoint models use the bare aiplatform.googleapis.com host (no
    # region prefix) -- ai_gateway.ts:114-131's own comment documents why this
    # project uses "global" rather than a regional location for this model.
    return (
        f"https://aiplatform.googleapis.com/v1/projects/{PROJECT}"
        f"/locations/{LOCATION}/publishers/google/models/{MODEL}:generateContent"
    )


def call_model(token: str, image_bytes: bytes, mime_type: str) -> dict:
    body = {
        "contents": [{
            "role": "user",
            "parts": [
                {"text": build_prompt()},
                {"inlineData": {"mimeType": mime_type, "data": base64.b64encode(image_bytes).decode()}},
            ],
        }],
        "generationConfig": {
            "temperature": 0,                       # ai_equipment_recognition.ts:154
            "maxOutputTokens": 256,                  # ai_equipment_recognition.ts:162
            "responseMimeType": "application/json",  # jsonResponse: true
            "thinkingConfig": {"thinkingBudget": 0},  # disableThinking: true
        },
        "safetySettings": [
            {"category": c, "threshold": SAFETY_THRESHOLD} for c in SAFETY_CATEGORIES
        ],
    }
    req = urllib.request.Request(
        endpoint_url(),
        data=json.dumps(body).encode(),
        method="POST",
        headers={"Authorization": f"Bearer {token}", "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read().decode("utf-8"))
    except urllib.error.HTTPError as e:
        return {"_httpError": e.code, "_body": e.read().decode("utf-8", "replace")[:1000]}


def extract_machine(response: dict) -> tuple[str | None, dict]:
    """Returns (machine_name_or_None, raw_parsed_json_or_error_info)."""
    if "_httpError" in response:
        return None, response
    try:
        text = response["candidates"][0]["content"]["parts"][0]["text"]
        parsed = json.loads(text)
        return parsed.get("machine"), parsed
    except (KeyError, IndexError, ValueError, TypeError) as e:
        return None, {"_parseError": str(e), "_raw": response}


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--limit", type=int, default=None, help="only run the first N cases (smoke test)")
    args = ap.parse_args()

    manifest = json.loads(MANIFEST.read_text("utf-8"))
    cases = manifest["cases"]
    if args.limit:
        cases = cases[: args.limit]

    print(f"Loading Firebase CLI access token...")
    token = access_token()

    results = []
    correct_high_mod = 0
    total_high_mod = 0
    correct_all = 0
    total_all = 0

    for i, case in enumerate(cases, 1):
        rel_path = case["file"]
        img_path = REPO_ROOT / rel_path
        if not img_path.is_file():
            print(f"[{i}/{len(cases)}] MISSING FILE: {rel_path}")
            continue

        mime = "image/jpeg"
        image_bytes = img_path.read_bytes()

        print(f"[{i}/{len(cases)}] {rel_path} (ground truth: {case['ground_truth']}, conf: {case['confidence']}) ...", end=" ")
        resp = call_model(token, image_bytes, mime)
        predicted, raw = extract_machine(resp)

        is_match = predicted == case["ground_truth"]
        print(f"-> predicted: {predicted!r} {'OK' if is_match else 'MISMATCH'}")

        total_all += 1
        correct_all += int(is_match)
        if case["confidence"] in ("HIGH", "MODERATE"):
            total_high_mod += 1
            correct_high_mod += int(is_match)

        results.append({
            "file": rel_path,
            "ground_truth": case["ground_truth"],
            "gt_confidence": case["confidence"],
            "predicted": predicted,
            "match": is_match,
            "raw_model_output": raw,
        })
        time.sleep(0.5)  # gentle pacing, avoid rate-limit throttling

    summary = {
        "generated": time.strftime("%Y-%m-%d %H:%M:%S"),
        "model": MODEL,
        "location": LOCATION,
        "project": PROJECT,
        "total_cases": total_all,
        "accuracy_all": correct_all / total_all if total_all else None,
        "accuracy_high_moderate_confidence_gt_only": (
            correct_high_mod / total_high_mod if total_high_mod else None
        ),
        "correct_all": correct_all,
        "correct_high_moderate": correct_high_mod,
        "total_high_moderate": total_high_mod,
        "results": results,
    }
    RESULTS_OUT.write_text(json.dumps(summary, indent=2, ensure_ascii=False), "utf-8")

    print("\n" + "=" * 70)
    print(f"TOTAL: {correct_all}/{total_all} correct ({summary['accuracy_all']:.1%})" if total_all else "no cases run")
    if total_high_mod:
        print(f"HIGH/MODERATE-confidence ground truth only: {correct_high_mod}/{total_high_mod} "
              f"({summary['accuracy_high_moderate_confidence_gt_only']:.1%})")
    print(f"Full results written to: {RESULTS_OUT}")


if __name__ == "__main__":
    main()
