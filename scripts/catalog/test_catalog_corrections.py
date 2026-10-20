# -*- coding: utf-8 -*-
"""Tests for the corrections layer, the shared consistency rules and the
purpose author.

    python -m pytest scripts/catalog/test_catalog_corrections.py -q
"""
from __future__ import annotations

import copy
import json
import re
from pathlib import Path

import pytest

import author_catalog_purposes as purposes
import catalog_corrections as cc
import catalog_rules as rules
from build_vendor_catalog import merge_rows

EN = json.loads(cc.EN_PATH.read_text(encoding="utf-8"))
RU = json.loads(cc.RU_PATH.read_text(encoding="utf-8"))
CORR = cc.load_corrections()
BY_ID = {r["id"]: r for r in EN}
CYR = re.compile(r"[а-яё]", re.I)
BANNED = re.compile(r"\b(best|safest|cure[sd]?|heal[s]?|prevent[s]?|guarantee[sd]?|painless)\b", re.I)


def test_shipped_catalogue_already_has_every_correction_applied() -> None:
    # If this fails, the asset was edited by hand or rebuilt without the layer.
    en, ru = copy.deepcopy(EN), copy.deepcopy(RU)
    changed = cc.apply(en, ru, CORR)
    assert changed == {"en_rows": 0, "en_fields": 0, "ru_rows": 0, "ru_fields": 0}


def test_apply_is_idempotent_and_restores_a_rebuild() -> None:
    rid = "ea_hold_the_world_med_ball_chest_press"
    rebuilt = copy.deepcopy(BY_ID[rid])
    rebuilt.update(muscles=[], primaryMuscles=[], steps=["x"], summary="x", isStretch=False)
    # build() regenerates these keys; the merge keeps equipmentId from disk.
    merged, _ = merge_rows([rebuilt], [BY_ID[rid]])
    ru = copy.deepcopy(RU)
    cc.apply(merged, ru, {rid: CORR[rid]})
    first = copy.deepcopy(merged)
    assert cc.apply(merged, ru, {rid: CORR[rid]}) == {
        "en_rows": 0, "en_fields": 0, "ru_rows": 0, "ru_fields": 0}
    assert merged == first
    assert merged[0]["equipmentId"] == "medicine_ball"


def test_unknown_field_is_rejected(tmp_path: Path) -> None:
    bad = tmp_path / "c.json"
    bad.write_text(json.dumps({"version": 1, "rows": {"ea_x": {"en": {"video": {}}}}}))
    with pytest.raises(ValueError):
        cc.load_corrections(bad)


def test_unknown_id_is_rejected() -> None:
    with pytest.raises(KeyError):
        cc.apply(copy.deepcopy(EN), copy.deepcopy(RU), {"ea_nope": {"en": {"title": "x"}}})


def test_every_row_but_the_quarantined_one_has_en_and_ru_purpose() -> None:
    missing = [r["id"] for r in EN if not (r.get("purpose") or "").strip()]
    assert missing == ["ea_major_groups_muscle_body"]
    for r in EN:
        if r["id"] in missing:
            continue
        ru_p = RU[r["id"]].get("purpose") or ""
        assert CYR.search(ru_p), f"{r['id']}: Russian purpose is not Russian"


def test_corrected_ru_steps_keep_the_en_shape_and_summary_invariant() -> None:
    for rid in CORR:
        row, o = BY_ID[rid], RU[rid]
        assert len(o["steps"]) == len(row["steps"]), rid
        assert row["summary"] == row["steps"][0], rid
        assert o.get("summary", o["steps"][0]) == o["steps"][0], rid


def test_authored_purposes_are_plain_unique_and_bounded() -> None:
    authored = {rid: c["en"]["purpose"] for rid, c in CORR.items() if "purpose" in c.get("en", {})}
    assert len(authored) >= 1480
    assert len(set(authored.values())) == len(authored), "duplicate purpose text"
    for rid, text in authored.items():
        assert 80 <= len(text) <= 520, (rid, len(text))
        assert not BANNED.search(text), (rid, text)
        assert "{" not in text and "}" not in text, rid
        assert "{" not in CORR[rid]["ru"]["purpose"], rid


def test_purpose_author_is_deterministic_and_uses_row_muscles() -> None:
    r = BY_ID["ea_barbell_full_squat"]
    a = purposes.author(r)
    assert a == purposes.author(r)
    assert "quadriceps" in a[1] or "glutes" in a[1]


def test_muscles_come_from_the_app_vocabulary() -> None:
    vocab = {"adductors", "back", "biceps", "calves", "chest", "core", "forearms", "glutes",
             "hamstrings", "lats", "lower_back", "quads", "shoulders", "traps", "triceps"}
    for rid, c in CORR.items():
        for key in ("muscles", "primaryMuscles"):
            assert set(c.get("en", {}).get(key, [])) <= vocab, rid


# --- shared rules -----------------------------------------------------------
def test_station_model_accepts_barbell_squat_on_rack_and_rejects_dumbbell_on_nothing() -> None:
    assert rules.title_equipment_ok("Barbell Squat Back POV", "squat_rack", "Barbell")
    assert rules.title_equipment_ok("Dumbbell Incline Press", "bench_press", "Dumbbells") is True
    assert not rules.title_equipment_ok("Arnold Press Dumbbell", "bench_press", "Dumbbells")
    assert not rules.title_equipment_ok("Band Pull Up", "squat_rack", "Resistance Band")
    assert rules.title_equipment_ok("Pull Apart Cable Resistance Band", "resistance_bands", "Resistance Band")


def test_title_vs_muscle_rule_knows_leg_curl_and_upright_row() -> None:
    assert rules.muscle_rule_violations("Seated Leg Curl Machine", "hamstrings glutes") == []
    assert rules.muscle_rule_violations("Kettlebell Calf Raise", "quads") == ["calf"]
    assert rules.muscle_rule_violations("Kettlebell Upright Row", "shoulders traps") == []


def test_truncated_vendor_filename_is_not_a_title_mismatch() -> None:
    assert rules.video_name_ok("Dumbbell External Rotation",
                               "exercises/men/Shoulders/dumbbell external rotatio.mp4")
    assert not rules.video_name_ok("Dumbbell Curl", "exercises/men/Shoulders/barbell squat.mp4")
