# -*- coding: utf-8 -*-
"""Ratchet on catalogue text completeness and text/metadata consistency.

Added 2026-10-13 by the full-project QA pass. It reads only the shipped files
under mobile/assets/data (no vendor zip, no network).

Each check has a BASELINE: the number of offending rows measured on
2026-10-13. A count ABOVE the baseline fails and prints the offending ids.
A count BELOW the baseline also fails with a "lower the baseline" message, so
fixes are locked in instead of leaving slack for the gap to grow back.

Checks with baseline 0 are hard invariants (every row has a summary, steps,
no placeholder text, a complete Russian overlay entry, poster files on disk).
The others are known content gaps or heuristic findings, not claims that the
rows are wrong; see the audit output for context.

Fixes are applied through scripts/catalog/catalog_corrections.json (see
catalog_corrections.py); consistency rules live in catalog_rules.py.
"""
from __future__ import annotations

import collections
import hashlib
import json
import re
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import catalog_rules as R  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
DATA = ROOT / "mobile" / "assets" / "data"
MOBILE = ROOT / "mobile"

MIN_TOTAL = 1887

BASELINE = {
    # hard invariants
    "missing_summary": 0,
    "missing_steps": 0,
    "empty_step_string": 0,
    "placeholder_text": 0,
    "video_without_description": 0,
    "ru_missing_entry": 0,
    "ru_missing_title": 0,
    "ru_missing_summary": 0,
    "ru_missing_steps": 0,
    "ru_steps_count_differs": 0,
    "ru_steps_identical_to_en": 0,
    "poster_file_missing": 0,
    # known gaps / heuristic findings
    "missing_purpose": 1,  # ea_major_groups_muscle_body, quarantined (not an exercise)
    "no_muscles": 2,  # quarantined row + ea_side_lying_parsva_savasana_variation (no working muscle)
    "steps_lt3": 1,  # ea_major_groups_muscle_body, quarantined
    "dup_steps_group_ids": 58,  # one movement spelled twice by the vendor; camera-view variants now carry a view cue
    "title_vs_video_name_mismatch": 0,
    "title_stretch_but_flag_false": 0,
    "steps_equipment_vs_equipmentId": 0,
    "title_equipment_vs_equipmentId": 0,
    "title_vs_muscles_mismatch": 0,
}

PLACEHOLDER = re.compile(r"lorem|todo|tbd|n/a|placeholder|coming soon|xxx|^\s*-+\s*$", re.I)


def _norm(s: str) -> str:
    return re.sub(r"[^a-z0-9]+", " ", s.lower()).strip()


def _blank(v) -> bool:
    return v is None or (isinstance(v, str) and not v.strip())


def _collect() -> tuple[int, dict[str, list[str]]]:
    rows = json.loads((DATA / "exercises_vendor.json").read_text(encoding="utf-8"))
    ru = json.loads((DATA / "exercises_vendor.ru.json").read_text(encoding="utf-8"))
    res: dict[str, list[str]] = collections.defaultdict(list)
    by_steps: dict[str, list[str]] = collections.defaultdict(list)

    for r in rows:
        i = r["id"]
        st = r.get("steps") or []
        has_desc = bool(st) or not _blank(r.get("summary"))
        v = r.get("video") or {}
        if _blank(r.get("summary")):
            res["missing_summary"].append(i)
        if not st:
            res["missing_steps"].append(i)
        if any(_blank(s) for s in st):
            res["empty_step_string"].append(i)
        if st and len(st) < 3:
            res["steps_lt3"].append(i)
        if _blank(r.get("purpose")):
            res["missing_purpose"].append(i)
        texts = st + [r.get("summary") or "", r.get("purpose") or ""]
        if any(PLACEHOLDER.search(s or "") for s in texts):
            res["placeholder_text"].append(i)
        if st:
            h = hashlib.md5("|".join(_norm(s) for s in st).encode()).hexdigest()
            by_steps[h].append(i)
        if v and not has_desc:
            res["video_without_description"].append(i)
        if not r.get("muscles") and not r.get("primaryMuscles"):
            res["no_muscles"].append(i)

        o = ru.get(i)
        if o is None:
            res["ru_missing_entry"].append(i)
        else:
            if _blank(o.get("title")):
                res["ru_missing_title"].append(i)
            if has_desc and _blank(o.get("summary")):
                res["ru_missing_summary"].append(i)
            if st and not (o.get("steps") or []):
                res["ru_missing_steps"].append(i)
            elif st and len(o.get("steps") or []) != len(st):
                res["ru_steps_count_differs"].append(i)
            if o.get("steps") and st and o["steps"] == st:
                res["ru_steps_identical_to_en"].append(i)

        for p in (r.get("poster") or {}).values():
            if not (MOBILE / p).exists():
                res["poster_file_missing"].append(i)

        if v.get("men") and not R.video_name_ok(r["title"], v["men"]):
            res["title_vs_video_name_mismatch"].append(i)

        eq = r.get("equipmentId")
        if R.steps_equipment_ok(st, r["title"], eq):
            res["steps_equipment_vs_equipmentId"].append(i)
        if not R.title_equipment_ok(r["title"], eq, r.get("equipmentLabel")):
            res["title_equipment_vs_equipmentId"].append(i)
        t = _norm(r["title"])
        if not r.get("isStretch") and re.search(r"\bstretch\b", t):
            res["title_stretch_but_flag_false"].append(i)

        m = " ".join((r.get("muscles") or []) + (r.get("primaryMuscles") or [])).lower()
        if m and R.muscle_rule_violations(r["title"], m):
            res["title_vs_muscles_mismatch"].append(i)

    res["dup_steps_group_ids"] = [i for ids in by_steps.values() if len(ids) > 1 for i in ids]
    return len(rows), res


class CatalogTextRatchet(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.total, cls.res = _collect()

    def test_row_count_not_shrunk(self) -> None:
        self.assertGreaterEqual(
            self.total, MIN_TOTAL,
            "rows disappeared; a smaller catalogue can lower every gap count without fixing anything")

    def test_no_gap_grows_and_fixes_are_locked_in(self) -> None:
        grown, shrunk = [], []
        for name, base in BASELINE.items():
            ids = self.res.get(name, [])
            if len(ids) > base:
                grown.append(f"{name}: {len(ids)} > baseline {base}; ids: {', '.join(ids[:40])}"
                             + (" ..." if len(ids) > 40 else ""))
            elif len(ids) < base:
                shrunk.append(f"{name}: {len(ids)} < baseline {base}")
        msg = []
        if grown:
            msg.append("GAPS GREW:\n  " + "\n  ".join(grown))
        if shrunk:
            msg.append("IMPROVED, lower BASELINE in this file to lock it in:\n  " + "\n  ".join(shrunk))
        self.assertFalse(grown or shrunk, "\n".join(msg))


if __name__ == "__main__":
    unittest.main()
