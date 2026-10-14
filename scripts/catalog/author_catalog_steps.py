# -*- coding: utf-8 -*-
"""Per-variant steps for rows that share byte-identical steps (audit item 4).

83 ids in 38 groups had identical steps. Two different situations hide there:

* the vendor spelled one movement twice (`Archer Step Back` / `Archer Stepback`,
  `Barbell Back Wide Shrug` / `...Shrugs`, `Dumbbell External Rotatio` /
  `...Rotation`): the steps are CORRECT to be identical and inventing a
  difference would make one of two true texts less true. Left as is; the
  ratchet records the remaining count.
* the vendor filmed one movement from several camera positions (`Side POV`,
  `Front View`, `Behind View`, `360 Degrees`, `Side Angle`, `Back Side Pov`):
  the clip a user sees differs, so the text that goes with it should say what
  that view is for. A one-sentence viewing cue is added to the LAST step (step
  count unchanged, so the Russian overlay keeps the same shape).

Left/right Bulgarian split squats already name the working leg in their steps.
"""
from __future__ import annotations

import collections
import hashlib
import re

CUES = {
    "around": (
        "This clip circles the movement, so watch it from every side before you try it.",
        "Этот ролик обходит движение по кругу, поэтому посмотрите его со всех сторон, прежде чем пробовать.",
    ),
    "side": (
        "In this side view, watch the alignment of the spine and hips from the profile.",
        "В этом виде сбоку следите за положением позвоночника и таза в профиль.",
    ),
    "front": (
        "In this front view, check that both sides move evenly and the shoulders and knees stay level.",
        "В этом виде спереди проверяйте, что обе стороны работают равномерно, а плечи и колени остаются на одном уровне.",
    ),
    "rear": (
        "In this rear view, check that both sides move evenly and the body does not drift to one side.",
        "В этом виде сзади проверяйте, что обе стороны работают равномерно и тело не уходит в сторону.",
    ),
}
VIEW_PATTERNS = [
    ("around", re.compile(r"\b360\b", re.I)),
    ("rear", re.compile(r"back side pov|behind view|\(back\)|\bsquat\(back\)", re.I)),
    ("front", re.compile(r"front pov|front view|front-back view", re.I)),
    ("side", re.compile(r"side pov|side view|side angle", re.I)),
]


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def _append(last: str, cue: str) -> str:
    last = last.rstrip()
    return last + (" " if last.endswith((".", "!", "?")) else ". ") + cue


def view_of(title: str) -> str | None:
    for name, pat in VIEW_PATTERNS:
        if pat.search(title):
            return name
    return None


def add(corr: dict, rows: list[dict], ru: dict) -> int:
    groups = collections.defaultdict(list)
    for r in rows:
        if r.get("steps"):
            h = hashlib.md5("|".join(_norm(s) for s in r["steps"]).encode()).hexdigest()
            groups[h].append(r)
    n = 0
    for members in groups.values():
        if len(members) < 2:
            continue
        for r in members:
            view = view_of(r["title"])
            if not view:
                continue
            rid = r["id"]
            en_cue, ru_cue = CUES[view]
            en_steps = list(r["steps"])
            en_steps[-1] = _append(en_steps[-1], en_cue)
            ru_steps = list(ru[rid]["steps"])
            ru_steps[-1] = _append(ru_steps[-1], ru_cue)
            slot_en = corr.setdefault(rid, {}).setdefault("en", {})
            slot_ru = corr[rid].setdefault("ru", {})
            if "steps" not in slot_en:
                slot_en["steps"] = en_steps
                slot_ru["steps"] = ru_steps
                n += 1
    return n
