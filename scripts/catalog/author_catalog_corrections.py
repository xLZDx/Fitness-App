# -*- coding: utf-8 -*-
"""One-shot authoring tool for `catalog_corrections.json` (provenance, not CI).

Reads the shipped catalogue, derives the corrections for the gaps found by the
2026-10-13 audit and MERGES them into `catalog_corrections.json` (existing
entries win per field, so hand edits to the JSON are never lost).

    python scripts/catalog/author_catalog_corrections.py            # report
    python scripts/catalog/author_catalog_corrections.py --write

Sections (each its own function so a partial run is possible):
    muscles   rows with neither `muscles` nor `primaryMuscles`
    equipment equipmentId / equipmentLabel / isStretch against title and steps
    muscle_fixes   title-vs-muscle disagreements
    steps     per-variant steps for rows sharing identical steps (author_catalog_steps.py)
    purposes  missing `purpose`, en + ru (author_catalog_purposes.py)
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import catalog_corrections as cc  # noqa: E402
import catalog_rules as rules  # noqa: E402

APP_MUSCLES = {
    "adductors", "back", "biceps", "calves", "chest", "core", "forearms",
    "glutes", "hamstrings", "lats", "lower_back", "quads", "shoulders",
    "traps", "triceps",
}

# (regex on the id without `ea_`, primary, secondary). First match wins.
# "neck" has no tag of its own; traps is the nearest honest home (the vendor
# folder for these is the upper back/neck area and the tag drives chips only).
MUSCLE_RULES: list[tuple[str, list[str], list[str]]] = [
    (r"^agility_ladder", ["calves", "quads"], ["hamstrings"]),
    (r"^air_swing", ["quads", "hamstrings"], ["glutes"]),
    (r"chest_stretch", ["chest"], ["shoulders"]),
    (r"^(cross_body_shoulder_stretch|cross_body_elbow_pull_shoulder_stretch)$", ["shoulders"], []),
    (r"biceps_stretch", ["biceps"], ["forearms"]),
    (r"forearms?_|^side_wrist_pull|_forearms_stretch", ["forearms"], []),
    (r"lats_stretch|side_bend_standing_lats", ["lats"], ["core"]),
    (r"calve|calf", ["calves"], []),
    (r"quadriceps_stretch|foam_roller_(quads|lateral_quads)|crescent_moon_pose_quad", ["quads"], []),
    (r"bulgarian_split_squat_stretch", ["quads"], ["glutes"]),
    (r"hamstring", ["hamstrings"], []),
    (r"glutes_stretch|^pigeon|pigeon_pose|figure_four|double_pigeon|half_lotus|restful_cow_face_pose_legs", ["glutes"], []),
    (r"child_pose_elbows_on_block", ["shoulders", "lats"], []),
    (r"child_pose", ["lower_back", "lats"], []),
    (r"lower_back_stretch|knee_hugs|knees_to_floor", ["lower_back"], ["glutes"]),
    (r"neck|^5_sec_fist_against_chin", ["traps"], []),
    (r"foam_roller_back", ["back", "lats"], []),
    (r"foam_roller_calves", ["calves"], []),
    (r"cobra_stretch", ["chest", "core"], ["lower_back"]),
    (r"bow_pose", ["lower_back", "quads"], ["chest"]),
    (r"cat_pose", ["lower_back", "core"], []),
    (r"chair_pose", ["quads", "glutes"], []),
    (r"crescent_moon_pose", ["core", "lats"], []),
    (r"criss_cross_bow_tie|happy_baby", ["adductors", "glutes"], []),
    (r"crow_pose", ["forearms", "shoulders", "core"], []),
    (r"downward_dog_sprint", ["shoulders", "quads"], ["core"]),
    (r"downward_dog", ["hamstrings", "calves", "shoulders"], []),
    (r"eagle_arms", ["shoulders", "traps"], []),
    (r"easy_seated_twist|scorpion_twist", ["core", "lower_back"], []),
    (r"extended_side_angle|revolved_side_angle", ["quads", "core"], []),
    (r"gate_pose", ["core", "lats"], []),
    (r"half_monkey|monkey_pose", ["hamstrings", "adductors"], []),
    (r"lord_of_the_dance", ["quads", "chest"], ["shoulders"]),
    (r"one_arm_cow_face", ["shoulders", "triceps"], []),
    (r"puppy_pose", ["shoulders", "lats"], []),
    (r"pyramid", ["hamstrings", "calves"], []),
    (r"reclining_pigeon", ["glutes"], []),
    (r"reverse_prayer", ["shoulders", "forearms"], []),
    (r"revolved_head_to_knee", ["hamstrings", "core"], []),
    (r"runners_lunge", ["quads", "glutes", "hamstrings"], []),
    (r"wild_thing", ["shoulders", "chest"], []),
    (r"sun_salutations", ["shoulders", "core", "hamstrings"], []),
    (r"rebounder_high_knee", ["quads", "core"], ["calves"]),
    (r"rebounder", ["quads", "calves"], ["core"]),
    (r"^180_jump_turns|unilateral_(jumps|box_jump)|skater_hops", ["quads", "glutes", "calves"], []),
    (r"arms_lateral_raise_and_rotation|arm_circle", ["shoulders"], []),
    (r"^elbow_extension", ["triceps"], []),
    (r"med_ball_slam_burpees", ["quads", "chest", "shoulders"], ["core"]),
    (r"the_wall_ball", ["quads", "shoulders", "glutes"], []),
    (r"ball_slams|side_wall_slams|overhead_med_ball_throw|med_ball_jumping_jacks", ["core", "shoulders", "lats"], []),
    (r"low_rotational_med_ball", ["core", "shoulders"], ["quads"]),
    (r"band_squat_row", ["quads", "glutes", "back"], ["lats"]),
    (r"hang_clean|plate_clean_and_press|plate_clean$|sandbag_cleans", ["glutes", "hamstrings", "traps", "quads"], ["lower_back"]),
    (r"barbell_jump_shrug", ["traps", "calves", "quads"], ["glutes"]),
    (r"press_under", ["shoulders", "quads", "glutes"], []),
    (r"sled_battle_rope_pull|sled_drag_and_row", ["lats", "back", "biceps"], ["hamstrings"]),
    (r"battle_rope_double_arm_slams", ["shoulders", "lats", "core"], []),
    (r"battle_rope", ["shoulders", "core", "forearms"], []),
    (r"bear_crawl", ["shoulders", "core", "quads"], []),
    (r"sled|crawl_with", ["quads", "glutes", "hamstrings", "calves"], []),
    (r"dumbbell_curl_press_extend", ["biceps", "shoulders", "triceps"], []),
    (r"dumbbell_swing", ["glutes", "hamstrings", "lower_back"], []),
    (r"front_lever", ["lats", "core"], []),
    (r"gorilla_walk", ["glutes", "adductors", "quads"], []),
    (r"hand_stand|headstand", ["shoulders", "triceps", "core"], []),
    (r"kettlebell_snatch", ["glutes", "hamstrings", "shoulders", "traps"], []),
    (r"turkish_get_up", ["shoulders", "core", "glutes"], []),
    (r"walkover_pushup|plank_pushup|pushup_to_renegade", ["chest", "triceps", "shoulders", "core"], []),
    (r"kettlebell_windmill", ["core", "shoulders", "hamstrings"], []),
    (r"kipping_handstand", ["shoulders", "triceps", "traps"], []),
    (r"landmine_alternating_lunge_to_chest", ["quads", "glutes", "chest", "triceps"], ["shoulders"]),
    (r"landmine_alternating_lunge_and_twist", ["quads", "glutes", "core"], []),
    (r"landmine_rotational", ["core", "shoulders", "glutes"], []),
    (r"low_box_", ["calves", "quads"], []),
    (r"lying_neck", ["traps"], []),
    (r"monkey_bar", ["lats", "forearms", "shoulders"], []),
    (r"mountain_climber", ["core", "quads", "shoulders"], []),
    (r"^pike_(shoulder|individual|alternating)", ["shoulders", "core"], []),
    (r"^pike_jacks", ["shoulders", "core", "calves"], []),
    (r"plank_individual|unilateral_(front_)?plank", ["core", "shoulders"], []),
    (r"plank_iytw", ["traps", "shoulders", "core"], []),
    (r"plate_overhead_carry", ["shoulders", "traps", "core"], []),
    (r"plate_thruster", ["quads", "glutes", "shoulders", "triceps"], []),
    (r"ring_dips", ["chest", "triceps", "shoulders"], []),
    (r"stepmill", ["quads", "glutes", "calves"], []),
    (r"tennis_forehand", ["core", "shoulders", "forearms"], []),
    (r"treadmill_walk", ["quads", "hamstrings", "calves", "glutes"], []),
    (r"tyre_flip", ["glutes", "hamstrings", "quads", "back"], []),
    (r"tyre_hammering", ["shoulders", "core", "lats"], []),
]
# Not derivable with any confidence: reported, left empty.
UNRESOLVED_MUSCLES = {
    "ea_major_groups_muscle_body",          # quarantined, not an exercise
    "ea_side_lying_parsva_savasana_variation",  # a relaxation pose, no working muscle
}

# Real muscle disagreements (title says X, tags say something else).
MUSCLE_FIXES: dict[str, tuple[list[str], list[str]]] = {
    "ea_plate_curl_to_overhead_press_to_tricep_extension": (["biceps", "shoulders", "triceps"], []),
    "ea_plate_overhead_press_to_tricep_extension": (["shoulders", "triceps"], []),
    "ea_plate_squat_hold_biceps_curl": (["quads", "biceps"], ["glutes"]),
    "ea_kettlebell_calf_raise": (["calves"], []),
    "ea_kettlebell_seated_calf_raise": (["calves"], []),
    "ea_kettlebell_single_leg_calf_raise": (["calves"], []),
    "ea_landmine_calf_raise": (["calves"], []),
    "ea_horizontal_leg_press_calf_raise": (["calves"], []),
    "ea_horizontal_leg_press_calf_raise_single_leg": (["calves"], []),
    "ea_nordic_hamstring_curl_with_partner": (["hamstrings"], ["glutes", "calves"]),
    "ea_suspension_trainer_with_grips_inverted_row_on_floor": (["back", "lats"], ["biceps", "shoulders"]),
    "ea_kettlebell_rear_delt_row": (["shoulders", "back"], []),
    "ea_pushup_to_renegade_row": (["chest", "lats"], ["triceps", "shoulders", "core"]),
}
UPRIGHT_ROW_ADD = {  # upright rows also load the traps; shoulders stay primary
    "ea_dumbbell_single_arm_upright_row", "ea_kettlebell_upright_row",
}

SHOULDER_STRETCH_IDS = [
    "ea_arms_behind_back_shoulder_flexor_stretch", "ea_cross_over_shoulder_stretch",
    "ea_lying_bench_internal_rotation_stretch", "ea_reaching_up_shoulder_stretch",
    "ea_reverse_shoulder_stretch", "ea_seated_shoulder_flexor_depressor_retractor_stretch",
    "ea_standing_overhand_shoulder_stretch", "ea_standing_reverse_shoulder_stretch",
]

# Individually judged rows (clip name / steps are the evidence).
EQUIPMENT_FIXES: dict[str, dict] = {
    # medicine ball held standing; vendor label said "Exercise Ball", id said bench
    "ea_hold_the_world_med_ball_chest_press": {"equipmentId": "medicine_ball", "equipmentLabel": "Medicine Ball"},
    # "on a bench or the floor": the bench is optional, the dumbbell is not
    "ea_laying_lateral_raise": {"equipmentId": "dumbbell"},
    # steps anchor a resistance band; the row said it needed nothing
    "ea_superman_pulls": {"equipmentId": "resistance_bands", "equipmentLabel": "Resistance Band"},
    # "(with Rack)": the rack, not the Smith machine, is what the title names
    "ea_barbell_full_squat_with_rack": {"equipmentId": "squat_rack"},
}


def derive_muscles(rows: list[dict]) -> tuple[dict, list[str]]:
    out, unresolved = {}, []
    for r in rows:
        if r.get("muscles") or r.get("primaryMuscles"):
            continue
        rid = r["id"]
        if rid in UNRESOLVED_MUSCLES:
            unresolved.append(rid)
            continue
        key = rid[3:]
        for pat, prim, sec in MUSCLE_RULES:
            if re.search(pat, key):
                muscles = prim + [m for m in sec if m not in prim]
                assert set(muscles) <= APP_MUSCLES, (rid, muscles)
                out[rid] = {"muscles": muscles, "primaryMuscles": list(prim)}
                break
        else:
            unresolved.append(rid)
    return out, unresolved


def muscle_fixes(rows: list[dict]) -> dict:
    by = {r["id"]: r for r in rows}
    out = {}
    for rid, (prim, sec) in MUSCLE_FIXES.items():
        out[rid] = {"muscles": prim + [m for m in sec if m not in prim], "primaryMuscles": prim}
    for rid in UPRIGHT_ROW_ADD:
        m = list(by[rid]["muscles"])
        if "traps" not in m:
            m.append("traps")
        out[rid] = {"muscles": m, "primaryMuscles": list(by[rid].get("primaryMuscles") or m[:1])}
    return out


def equipment_fixes(rows: list[dict]) -> tuple[dict, list[str]]:
    out: dict[str, dict] = {k: dict(v) for k, v in EQUIPMENT_FIXES.items()}
    for rid in SHOULDER_STRETCH_IDS:
        out.setdefault(rid, {})["isStretch"] = True
    kept_station = []
    for r in rows:  # "Overhand Tricep Stretching Single Arm" is a stretch too
        if not r.get("isStretch") and re.search(r"\bstretch(ing)?\b", rules.norm(r["title"])):
            out.setdefault(r["id"], {})["isStretch"] = True
    for r in rows:
        rid = r["id"]
        eq = r.get("equipmentId")
        eq = out.get(rid, {}).get("equipmentId", eq)
        kw = rules.title_implement(r["title"])
        if kw is None or rid in EQUIPMENT_FIXES:
            continue
        if rules.title_equipment_ok(r["title"], eq, r.get("equipmentLabel")):
            if not rules._plain_ok(kw, eq):
                kept_station.append(rid)
            continue
        out.setdefault(rid, {})["equipmentId"] = rules.CANONICAL_IMPLEMENT_ID[kw]
    return out, kept_station


def merge(corr: dict, rid: str, side: str, fields: dict) -> None:
    slot = corr.setdefault(rid, {}).setdefault(side, {})
    for k, v in fields.items():
        slot.setdefault(k, v)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--sections", default="muscles,equipment,muscle_fixes,steps,purposes")
    args = ap.parse_args()
    sections = set(args.sections.split(","))
    rows = json.loads(cc.EN_PATH.read_text(encoding="utf-8"))
    ru = json.loads(cc.RU_PATH.read_text(encoding="utf-8"))
    corr = json.loads(cc.CORRECTIONS.read_text(encoding="utf-8"))["rows"] if cc.CORRECTIONS.exists() else {}
    report = {}

    if "muscles" in sections:
        m, unresolved = derive_muscles(rows)
        for rid, f in m.items():
            merge(corr, rid, "en", f)
        report["muscles_derived"] = len(m)
        report["muscles_unresolved"] = unresolved
    if "muscle_fixes" in sections:
        mf = muscle_fixes(rows)
        for rid, f in mf.items():
            corr.setdefault(rid, {}).setdefault("en", {}).update(f)  # explicit fix: overrides
        report["muscle_fixes"] = len(mf)
    if "equipment" in sections:
        ef, kept = equipment_fixes(rows)
        for rid, f in ef.items():
            corr.setdefault(rid, {}).setdefault("en", {}).update(f)
        report["equipment_rows_changed"] = len(ef)
        report["station_rows_kept"] = len(kept)
    if "steps" in sections:
        import author_catalog_steps as s
        n = s.add(corr, rows, ru)
        report["steps_rows_rewritten"] = n
    if "purposes" in sections:
        import author_catalog_purposes as p
        n = p.add(corr, rows, ru)
        report["purposes_authored"] = n

    print(json.dumps(report, indent=1, ensure_ascii=False))
    if args.write:
        ordered = {k: corr[k] for k in sorted(corr)}
        cc.CORRECTIONS.write_text(
            json.dumps({"version": 1, "rows": ordered}, ensure_ascii=False, indent=1) + "\n",
            encoding="utf-8")
        print("wrote", cc.CORRECTIONS)


if __name__ == "__main__":
    main()
