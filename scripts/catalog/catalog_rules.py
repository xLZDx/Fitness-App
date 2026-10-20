# -*- coding: utf-8 -*-
"""Text/metadata consistency rules shared by the corrections author and the ratchet.

The registry (`mobile/assets/data/equipment.json`) deliberately mixes generic
implements (Barbell, Dumbbells) with the stations they are used at (Squat rack,
Weight bench, Smith machine, Lat pulldown); `vendor_catalog_test.dart` pins
that a barbell squat links to `squat_rack`, not `barbell`. A naive "title says
dumbbell, so equipmentId must contain `dumbbell`" check therefore flags rows
that are right. These rules encode the station model once, so that the data fix
(`author_catalog_corrections.py`) and the check (`test_catalog_text_ratchet.py`)
cannot drift apart.
"""
from __future__ import annotations

import re

IMPLEMENT_KW = ("barbell", "dumbbell", "kettlebell", "cable", "band", "trx",
                "stability ball", "smith")
CANONICAL_IMPLEMENT_ID = {
    "barbell": "barbell", "dumbbell": "dumbbell", "kettlebell": "kettlebell",
    "cable": "cable_machine", "band": "resistance_bands", "trx": "trx",
    "stability ball": "stability_ball", "smith": "smith_machine",
}
BENCH_IDS = {"bench_press", "adjustable_bench", "preacher_curl_bench"}


def norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def title_implement(title: str) -> str | None:
    """First implement keyword named in [title] (same order as the old check)."""
    t = norm(title)
    if re.search(r"\bresistance bands?\b", t):
        return "band"  # "Cable Resistance Band" is a band, not a cable stack
    for kw in IMPLEMENT_KW:
        if re.search(r"\b" + kw + r"s?\b", t):
            return kw
    return None


def _plain_ok(kw: str, eq: str | None) -> bool:
    if not eq:
        return False
    if kw == "band":
        return eq == "resistance_bands"
    return any(k in eq for k in re.split(r"[_ ]", kw))


# A bench is in the movement itself, not just in the room.
BENCH_CUE = re.compile(
    r"bench|incline|decline|prone|lying|laying|hooklying|seated|supported|"
    r"preacher|zottman|knees|pull ?over|hip thrust|sit ?up|step ?up|"
    r"concentration|spider|wrist|skull ?crusher|tate|chest press|hex press|"
    r"fly|kickback|rear delt|row|split squat|kneeling|lap curl|"
    r"close grip press|spoto|anti gravity|leaning|flat", re.I)
BAND_BENCH_CUE = re.compile(r"bench|incline|decline|lying|prone|seated", re.I)
RACK_CUE = re.compile(r"rack|squat|support|leaning|lunge|press|rack pull", re.I)


def title_equipment_ok(title: str, eq: str | None, label: str | None) -> bool:
    kw = title_implement(title)
    if kw is None or _plain_ok(kw, eq):
        return True
    if not eq:
        return False
    t, lab = norm(title), norm(label or "")
    if eq in BENCH_IDS:
        cue = BAND_BENCH_CUE if kw == "band" else BENCH_CUE
        return bool(cue.search(t))
    if eq == "squat_rack":
        return kw in ("barbell", "dumbbell") and bool(RACK_CUE.search(t))
    if eq == "smith_machine":
        return "smith" in t or "smith" in lab
    if eq == "ez_curl_bar":
        return bool(re.search(r"\bez\b", t))
    if eq == "plyo_box":
        return "box" in lab or "box" in t
    if eq == "sissy_squat_machine":
        return "sissy" in t
    if eq == "pullup_bar":
        return bool(re.search(r"chin up|pull up", t))
    if eq == "weight_plates":
        return "plate" in t or "plate" in lab
    if kw == "cable":
        return eq in ("lat_pulldown", "seated_row_machine", "cable_machine", "ski_erg")
    return False


STEPS_KW = ("barbell", "dumbbell", "kettlebell", "cable", "band", "trx",
            "stability ball", "medicine ball", "foam roller", "smith")


def steps_equipment_ok(steps: list[str], title: str, eq: str | None) -> list[str]:
    """Implement words the steps use that the row's equipmentId cannot explain."""
    txt = norm(" ".join(steps))
    txt = re.sub(r"\bas if [^,.]*", " ", txt)  # a simile is not a requirement
    t = norm(title)
    bad = []
    for kw in STEPS_KW:
        if not re.search(r"\b" + kw + r"s?\b", txt):
            continue
        ok = _plain_ok(kw, eq) if kw != "medicine ball" else bool(eq and "medicine" in eq)
        if kw == "foam roller":
            ok = ok or bool(eq and "foam" in eq)
        if not ok and eq:
            if kw == "cable" and eq in ("resistance_bands", "lat_pulldown", "seated_row_machine",
                                         "cable_machine", "ski_erg"):
                ok = True  # the vendor calls an elastic band "the cable"
            elif kw == "barbell" and eq in {"smith_machine", "ez_curl_bar", "squat_rack"} | BENCH_IDS:
                ok = True
        if not ok and re.search(r"\b" + kw + r"s?\b", t) and eq is not None:
            ok = True  # named in the title: judged by the title rule instead
        if not ok:
            bad.append(kw)
            break
    return bad


# `title keyword -> muscle words that make the tags plausible`. A leg curl is a
# hamstring exercise and an upright row is a delt/trap one; the first version of
# this heuristic read "curl" as "biceps" and "row" as "back" only.
def muscle_rule_violations(title: str, muscles: str) -> list[str]:
    t = norm(title)
    m = muscles.lower()
    rules = [
        ("curl", ["bicep", "brachi", "forearm", "arm"], r"\bcurl\b(?! up)"),
        ("squat", ["quad", "glute", "leg", "thigh", "ham", "calf", "hip"], r"\bsquat"),
        ("row", ["back", "lat", "trap", "rhomb", "delt", "rear"], r"\brow\b"),
        ("bench press", ["chest", "pec", "tricep", "delt"], r"\bbench press"),
        ("crunch", ["ab", "core", "oblique"], r"\bcrunch"),
        ("calf", ["calf", "calves", "gastroc", "soleus", "leg"], r"\bcalf\b"),
        ("deadlift", ["glute", "ham", "back", "leg", "quad", "erector", "lower"], r"\bdeadlift"),
        ("tricep", ["tricep", "arm"], r"\btricep"),
    ]
    out = []
    for name, ok_words, pat in rules:
        if not re.search(pat, t):
            continue
        if name == "curl" and re.search(r"\b(leg|hamstring|nordic)\b[^.]*\bcurl\b", t):
            ok_words = ok_words + ["ham"]  # leg/hamstring curl: hamstrings
        if name == "squat" and re.search(r"squat (cage|rack)", t) and "squat" not in t.replace("squat cage", "").replace("squat rack", ""):
            continue  # the squat cage is where a press is done
        if name == "row" and re.search(r"upright row", t):
            ok_words = ok_words + ["shoulder"]
        if not any(w in m for w in ok_words):
            out.append(name)
    return out


def video_name_ok(title: str, video_men: str) -> bool:
    """Vendor filenames are sometimes cut mid-word (`...external rotatio.mp4`)."""
    t = norm(title)
    base = norm(video_men.split("/")[-1][:-4])
    if base == t:
        return True
    tt, bb = set(t.split()), set(base.split())
    if tt <= bb or bb <= tt:
        return True
    return t.startswith(base) or base.startswith(t)
