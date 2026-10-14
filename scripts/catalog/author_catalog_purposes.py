# -*- coding: utf-8 -*-
"""Authors `purpose` (en + ru) for every row that has none (audit item 2).

Composition per row, all from the tables in `author_purpose_data.py`:

    sentence 1  movement FAMILY phrasing (picked by hash of the id), with the
                row's own primary muscles substituted for {m}
    sentence 2  the first title MODIFIER that applies (grip, stance, angle,
                tempo, unilateral ...), family-aware for incline/decline
    sentence 3  the IMPLEMENT sentence (from the title/label), or "needs no
                equipment" for bodyweight rows -- dropped when the text would
                run past ~400 characters

The 403 existing purposes are never touched (rows with a purpose are skipped).
Style follows them: two to three plain sentences, no medical claims, no
superlatives. Russian is built from fixed phrases, never by inflecting titles.
"""
from __future__ import annotations

import hashlib
import re

import author_purpose_data as D
from catalog_rules import norm

MAX_LEN = 400


def _h(rid: str, salt: str = "") -> int:
    return int(hashlib.md5((rid + salt).encode()).hexdigest(), 16)


def _join(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " and " + items[-1]


def _join_ru(items: list[str]) -> str:
    return items[0] if len(items) == 1 else ", ".join(items[:-1]) + " и " + items[-1]


def muscle_phrases(row: dict) -> tuple[str, str]:
    tags = (row.get("primaryMuscles") or row.get("muscles") or [])[:3]
    if not tags:
        return "your target muscles", "целевые мышцы"
    return ("your " + _join([D.MU_EN[t] for t in tags]), _join_ru([D.MU_RU[t] for t in tags]))


def secondary_phrases(row: dict) -> tuple[str, str] | None:
    prim = set((row.get("primaryMuscles") or row.get("muscles") or [])[:3])
    rest = [t for t in (row.get("muscles") or []) if t not in prim][:2]
    if not rest:
        return None
    return ("It also brings in your " + _join([D.MU_EN[t] for t in rest]) + ".",
            "Дополнительно задействует " + _join_ru([D.MU_RU[t] for t in rest]) + ".")


STRENGTH_OVERRIDE = re.compile(r"push up|pushup|plank|lunge|squat|crunch|bridge|raise|\brow\b|press|dog\b.*(sprint|lunge)")
NOTES = [
    (r"\bleft\b", ("This version is shown on the left side; repeat on the right to keep both sides even.",
                   "Этот вариант показан на левую сторону; повторите на правую, чтобы нагрузка была равной.")),
    (r"\bright\b", ("This version is shown on the right side; repeat on the left to keep both sides even.",
                    "Этот вариант показан на правую сторону; повторите на левую, чтобы нагрузка была равной.")),
    (r"side pov|side view|side angle", ("This clip is filmed from the side, so the body line and the movement path are easy to follow.",
                                        "Ролик снят сбоку, поэтому линию тела и траекторию движения легко проследить.")),
    (r"front pov|front view|front back view", ("This clip is filmed from the front, so you can check that both sides move evenly.",
                                               "Ролик снят спереди, так что видно, что обе стороны работают равномерно.")),
    (r"back pov|behind view|back side pov|rear view|\(back\)|squat back$|back view", ("This clip is filmed from behind, which shows whether the body stays level.",
                                                                                    "Ролик снят сзади и показывает, остаётся ли тело ровным.")),
    (r"\b360\b", ("This clip circles the movement, so it can be studied from every angle.",
                  "Ролик обходит движение по кругу, поэтому его можно изучить со всех сторон.")),
    (r"version 2|version2|\b2\b$|\bv 2\b", ("This is a second take of the same exercise, a further reference for the technique.",
                                           "Это второй ролик того же упражнения — ещё один ориентир по технике.")),
]


def classify(row: dict, title: str, shift: int = 0) -> tuple[str, list[tuple[str, str]]]:
    t = norm(title)
    for key, pat, phrases in D.FAMILIES:
        if re.search(pat, t):
            if key == "stretch" and not row.get("isStretch"):
                continue
            if key == "pose_hold" and not (re.search(r"\bpose\b", t) or (
                    row.get("isStretch") and not STRENGTH_OVERRIDE.search(t))):
                continue
            return key, phrases
    group = row.get("vendorGroup")
    en, ru = D.GROUP_FALLBACK[group]
    return "fallback:" + str(group), [(en, ru)]


def modifiers_all(title: str, family: str) -> list[tuple[str, str]]:
    t = norm(title)
    out = []
    for pat, val in D.MODIFIERS:
        if re.search(pat, t):
            v = (val.get(family) or val[None]) if isinstance(val, dict) else val
            if v not in out:
                out.append(v)
    return out


def note_for(title: str) -> tuple[str, str] | None:
    t = norm(title)
    for pat, val in NOTES:
        if re.search(pat, t):
            return val
    return None


def equipment_clause(row: dict) -> tuple[str, str]:
    t = norm(row["title"] + " " + (row.get("equipmentLabel") or ""))
    eq = row.get("equipmentId") or ""
    for pat, val in D.EQUIPMENT:
        if re.search(pat, t) or re.search(pat, eq.replace("_", " ")):
            return val
    return D.BODYWEIGHT if not row.get("equipmentId") else ("", "")


def author(row: dict, attempt: int = 0, ru_title: str = "") -> tuple[str, str, str]:
    """attempt 0 is the base text; higher attempts add distinguishing material
    until the text is unique among the rows authored so far."""
    rid = row["id"]
    family, phrases = classify(row, row["title"])
    m_en, m_ru = muscle_phrases(row)
    s1_en, s1_ru = phrases[(_h(rid) + (1 if attempt == 1 else 0)) % len(phrases)]
    en = [s1_en.format(m=m_en)]
    ru = [s1_ru.format(m=m_ru)]
    mods = modifiers_all(row["title"], family)
    if mods:
        en.append(mods[0][0]); ru.append(mods[0][1])
    note = note_for(row["title"])
    if note:
        en.append(note[0]); ru.append(note[1])
    if attempt >= 2 and len(mods) > 1:
        en.append(mods[1][0]); ru.append(mods[1][1])
    if attempt >= 3:
        sec = secondary_phrases(row)
        if sec:
            en.append(sec[0]); ru.append(sec[1])
    if attempt >= 5:
        # Last resort: name the variation. The Russian title is quoted as-is,
        # never inflected.
        en.append('This entry is the "' + row["title"] + '" variation.')
        ru.append("Это вариант «" + (ru_title or row["title"]) + "».")
    if attempt >= 6:
        en.append("It is listed twice under the same name; both listings are the same exercise.")
        ru.append("Упражнение значится в каталоге дважды под одним названием; обе записи описывают одно и то же.")
    eq = equipment_clause(row)
    if eq[0] and not (row.get("isStretch") and eq == D.BODYWEIGHT):
        if len(" ".join(en)) + len(eq[0]) < MAX_LEN or not mods:
            en.append(eq[0]); ru.append(eq[1])
    return family, " ".join(en), " ".join(ru)


def author_unique(row: dict, seen: set[str], ru_title: str = "") -> tuple[str, str, str]:
    for attempt in range(7):
        f, en, ru = author(row, attempt, ru_title)
        if en not in seen:
            seen.add(en)
            return f, en, ru
    raise RuntimeError(f"cannot make a unique purpose for {row['id']}")


def quarantined_ids() -> set[str]:
    import json
    from catalog_corrections import DATA
    return {q["id"] for q in json.loads((DATA / "exercises_quarantine.json").read_text(encoding="utf-8"))}


def add(corr: dict, rows: list[dict], ru: dict) -> int:
    """(Re)author every purpose that is not curated.

    A row is curated when its shipped purpose differs from the one this tool
    wrote into the corrections file (the 403 hand-written ones). Everything
    else is regenerated deterministically, so the output does not depend on how
    many times the corrections have already been applied.
    """
    skip = quarantined_ids()  # withheld rows are not exercises; they get no purpose
    mine = {rid: c.get("en", {}).get("purpose") for rid, c in corr.items()}
    curated = {r["id"] for r in rows
               if r.get("purpose") and r["purpose"] != mine.get(r["id"])}
    seen = {r["purpose"] for r in rows if r["id"] in curated}
    n = 0
    for r in rows:
        if r["id"] in skip or r["id"] in curated:
            continue
        _, en, ruu = author_unique(r, seen, (ru.get(r["id"]) or {}).get("title", ""))
        corr.setdefault(r["id"], {}).setdefault("en", {})["purpose"] = en
        corr[r["id"]].setdefault("ru", {})["purpose"] = ruu
        n += 1
    return n
