# -*- coding: utf-8 -*-
"""Everything about the video drop that is DERIVED, not authored.

`build_video_library.py` produced `data/staging/video_library.json` straight
from the filenames and refused to guess anything it could not read there. This
module is the second pass: it says which of those 359 rows must not ship at
all, and which of them are the exercise the catalog already has under a
different name. Both answers are evidence-based, and the evidence is recorded
next to the decision.

WHY ROWS ARE DROPPED

Ten of the 359 are not exercises, they are the same video file twice. Every
.mp4 in the drop was md5-hashed; these pairs came back byte-identical:

  men/*/X (1).mp4              == men/*/X.mp4          (7 rows)
  */cardio/Cardio Exercises    == */cardio/Running      (both genders)
  girl/Cardio/... Machine      == girl/Cardio/Elliptical
  men/cardio/... Machines      == men/cardio/Elliptical

So "Cardio Exercises" is not a cardio exercise, it is the Running clip filed
twice, and shipping it would put the same video on two cards under two names.

Five more are dropped for the opposite reason: the filename does not say what
the movement is, and nothing else in the drop does either. They are listed in
`data/staging/library/UNSURE.txt` with the reason rather than given an invented
description -- a wrong instruction is worse than a missing exercise.

WHY ROWS ARE MERGED

69 of them are an exercise the catalog already ships with photographs and a
finished translation. Those keep their existing id -- a saved programme points
at ids -- and simply gain the video. The pairing is the same Jaccard >= 0.6 on
the tokenised name that `build_video_library.py` uses against Free Exercise DB;
below that threshold the two names stop describing the same movement.
"""
from __future__ import annotations

import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STAGING = ROOT / 'data' / 'staging'
CATALOG_DIR = ROOT / 'mobile' / 'assets' / 'data'

# Duplicate video files, proven by md5 over the whole drop. Value = the row
# whose clip this one is byte-identical to.
DUPLICATE_CLIPS = {
    'vid_45_degree_bycicle_twisting_crunch_1': 'vid_45_degree_bycicle_twisting_crunch',
    'vid_lever_seated_crunch_1': 'vid_lever_seated_crunch',
    'vid_smith_deadlift_deadlift_1': 'vid_smith_deadlift_deadlift',
    'vid_stretching_middle_back_stretch_1': 'vid_stretching_middle_back_stretch',
    'vid_stretching_standing_lateral_stretch_1': 'vid_stretching_standing_lateral_stretch',
    'vid_stretching_bridge_pose_setu_bandhasana_1': 'vid_stretching_bridge_pose_setu_bandhasana',
    'vid_dumbbell_decline_fly_45_degree_1': 'vid_dumbbell_decline_fly_45_degree',
    'vid_cardio_exercises': 'vid_running',
    'vid_cardio_exercises_machine': 'vid_elliptical',
    'vid_cardio_exercises_machines': 'vid_elliptical',
}

# The filename does not determine the movement, and guessing it would ship a
# confident description of the wrong exercise.
UNIDENTIFIED = {
    'vid_walk_wave_machine':
        'name does not identify the machine; the same clip is filed under both '
        'genders, so the drop gives no second view to read it from',
    'vid_bench_pull_ups':
        '"Bench Pull-ups" is either an inverted row with the feet on a bench or '
        'a bench-assisted pull-up; the name does not say which',
    'vid_old_school_reverse_extensions':
        'filed under triceps but "reverse extension" names a different movement '
        'in every source; implement unstated',
    'vid_weighted_standing_curl':
        'forearm folder, implement unstated -- a standing wrist curl already '
        'ships twice here with a barbell and with dumbbells',
    'vid_weighted_standing_curl_weights_or_lever':
        'the name itself says "weights or lever", i.e. the source did not know '
        'which was demonstrated',
    'vid_stretching_slopes_towards_stretch':
        '"Slopes Towards Stretch" is a machine translation of something; it does '
        'not name a movement in any stretching vocabulary and the folder does '
        'not narrow it down',
}

# Rows that DO ship, with correct instructions, but whose equipmentId had to
# stay null because equipment.json has no id for the implement the movement
# actually uses. Null is the honest answer; the alternative is putting the
# exercise on the page of a machine it has nothing to do with. Recorded here so
# the gap is visible when someone next edits the registry.
EQUIPMENT_GAPS = {
    'vid_jump_rope': 'skipping rope',
    'vid_lever_shrug': 'shrug machine',
    'vid_lever_lateral_raise': 'lateral raise machine',
    'vid_stretching_standing_wheel_rollout': 'ab wheel',
    'vid_deep_push_ups': 'parallettes / push-up handles',
    'vid_sit_up_on_exercise_ball': 'stability ball',
    'vid_stretching_spinal_stretch_on_exercise_ball': 'stability ball',
    'vid_ball_sit_up_on_stability_ball': 'stability ball',
    'vid_bent_knee_lying_twist_on_stability_ball': 'stability ball',
    'vid_crunch_legs_on_stability_ball': 'stability ball',
    'vid_lying_hip_lift_on_stability_ball': 'stability ball',
    'vid_side_bend_on_stability_ball': 'stability ball',
    'vid_stretching_calf_stretch_with_rope': 'stretching rope',
    'vid_stretching_calf_stretch_with_strap': 'stretching strap',
    'vid_stretching_peroneals_stretch': 'stretching belt / strap',
    'vid_stretching_hamstring_stretch': 'stretching belt / strap',
    'vid_stretching_hip_flexor_and_quad_stretch': 'stretching belt / strap',
    'vid_weighted_leg_extension_crunch': 'a weight the source does not name',
    'vid_weighted_lying_twist': 'a weight the source does not name',
}

# Pairs the tokeniser cannot see but that are provably the same exercise: the
# catalog already ships them under this exact English title, and shipping both
# would put two identical cards in front of the user. The Jaccard score is
# recorded so it is obvious why the automatic rule missed each one.
EXTRA_MERGES = {
    # "Squat" vs "Bodyweight Squat" -- 0.50, one token apart.
    'vid_squat': 'fedb_bodyweight_squat',
    # "Lever Triceps Extension" vs "Machine Triceps Extension" -- 0.50; "lever"
    # IS "machine" in this source, which is the whole point of the rename.
    'vid_lever_triceps_extension': 'fedb_machine_triceps_extension',
    # "Chin-ups  Pull-Ups" vs "Chin-Up" -- 0.25, because the plural stemmer only
    # fires on words longer than three letters, so "ups" never becomes "up".
    'vid_chin_ups_pull_ups': 'fedb_chin-up',
}

STOP = {'the', 'a', 'an', 'with', 'and', 'on', 'to', 'of', 'or'}


def bag(name: str) -> frozenset:
    s = re.sub(r'\(.*?\)', ' ', name.lower().replace('.mp4', ''))
    s = re.sub(r'[^a-z0-9]+', ' ', s)
    return frozenset(
        w[:-1] if len(w) > 3 and w.endswith('s') and not w.endswith('ss') else w
        for w in s.split() if w and w not in STOP)


def jaccard(a: frozenset, b: frozenset) -> float:
    return len(a & b) / len(a | b) if (a | b) else 0.0


def load_rows() -> list[dict]:
    return json.loads((STAGING / 'video_library.json').read_text('utf-8'))


def load_catalog() -> list[dict]:
    return json.loads((CATALOG_DIR / 'exercises.json').read_text('utf-8'))


def merge_targets(rows: list[dict], catalog: list[dict]) -> dict[str, str]:
    """video row id -> existing catalog id it is the same movement as.

    ONE video row per catalog entry. The Jaccard rule on its own is not
    injective: 22 rows scored >= 0.6 against a catalog entry that another row
    matched better, and "Dumbbell Incline Hammer Curl" scoring 0.6 against
    "Alternate Incline Dumbbell Curl" does not make them the same exercise --
    it makes the tokeniser blind to the word "hammer". Collapsing them would
    throw the losing row's video away silently.

    So for each catalog entry only the highest-scoring row merges; the rest are
    treated as new exercises and get their own written entry.
    """
    bags = [(bag(e['title']), e['id']) for e in catalog]
    best_for: dict[str, tuple[float, str]] = {}
    for r in rows:
        w = bag(r['title'])
        best, src = 0.0, None
        for b, cid in bags:
            s = jaccard(w, b)
            if s > best:
                best, src = s, cid
        if best >= 0.6 and src:
            prev = best_for.get(src)
            # Ties go to the row that sorts first, so the result is stable.
            if prev is None or best > prev[0]:
                best_for[src] = (best, r['id'])
    out = {rid: cid for cid, (_, rid) in best_for.items()}
    out.update(EXTRA_MERGES)
    return out


def dropped() -> dict[str, str]:
    out = {k: f'duplicate clip of {v}' for k, v in DUPLICATE_CLIPS.items()}
    out.update(UNIDENTIFIED)
    return out
