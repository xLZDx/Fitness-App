"""Derive typical-range posture metrics from the MM-Fit dataset.

Why this script exists, and what it is NOT
--------------------------------------------
R8's `extract_mmfit_targets.py` measures a known, labelled, repeated event
(one rep of a named exercise). This script measures something weaker:
incidental body asymmetry in people who were captured mid-workout, not
applying for a posture assessment. MM-Fit contains no "stand neutrally for
a posture check" scenario at all.

The proxy used here: the "top" phase of squats and lunges -- the moment a
lifter is standing between reps -- is the closest available approximation
of "an ordinary person standing normally" in this dataset. The numbers this
script produces describe how much shoulder/hip/head asymmetry showed up in
THAT population at THAT moment. They are a typical-range reference, never a
clinical "correct posture" line. See core/plans/PLAN_R10_POSTURE_2026-08-08.md
sections 2-3 for the full reasoning -- read it before changing this file's
interpretation of its own output.

A second, separate approximation: Human3.6M (MM-Fit's skeleton) has one HEAD
joint, not ears. The app's live detector (BlazePose) has left/right ears but
no single head point. Forward-head here is measured HEAD-to-shoulder-midpoint;
live it will be measured ear-midpoint-to-shoulder-midpoint. Same idea,
different anatomical reference -- not the same measurement, an approximation
of the same measurement.

Dataset
-------
MM-Fit (Stromback, Huang, Radu -- IMWUT 2020), CC BY 4.0.
https://doi.org/10.5281/zenodo.7672767
Same archive, same verified layout as `extract_mmfit_targets.py` -- see that
file's docstring for the joint-order verification. Not repeated here.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import zipfile
from pathlib import Path

import numpy as np

# Human3.6M 17-joint order -- identical to extract_mmfit_targets.py.
R_HIP, R_KNEE, R_FOOT = 1, 2, 3
L_HIP, L_KNEE, L_FOOT = 4, 5, 6
SPINE, THORAX, NECK, HEAD = 7, 8, 9, 10
L_SHOULDER, R_SHOULDER = 11, 14

VERTICAL_AXIS = 2

# Which exercises' "top" (standing) phase stands in for neutral standing.
# Only movements where the lifter is genuinely upright at the top -- a
# curl's top is still a standing lifter, but its labelled reps are shorter
# and noisier for isolating a clean standing window, so this script sticks
# to the two exercises R8 already validated has a legible top phase for.
STANDING_EXERCISES = {"squats", "lunges"}


def _dist(a: np.ndarray, b: np.ndarray) -> np.ndarray:
    return np.linalg.norm(a - b, axis=0)


def top_phase_mask(driver_signal: np.ndarray, pct: float = 90.0) -> np.ndarray:
    """Frames in the top ``pct``-th percentile of standing-ness.

    ``driver_signal`` here is hip-knee-ankle angle (same driver
    `extract_mmfit_targets.py` uses for squats/lunges) -- high angle means
    a straight leg, i.e. standing. Using a percentile rather than a fixed
    degree threshold means this adapts per person instead of assuming
    everyone's "standing" angle is identically 180.
    """
    threshold = np.percentile(driver_signal, pct)
    return driver_signal >= threshold


def leg_angle(joints: np.ndarray, hip: int, knee: int, ankle: int) -> np.ndarray:
    ba = joints[:, :, hip] - joints[:, :, knee]
    bc = joints[:, :, ankle] - joints[:, :, knee]
    denom = np.linalg.norm(ba, axis=0) * np.linalg.norm(bc, axis=0)
    cos = (ba * bc).sum(0) / np.where(denom == 0, 1e-9, denom)
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))


def posture_metrics(joints: np.ndarray, forward_axis: int) -> dict[str, np.ndarray]:
    """Per-frame shoulder asymmetry, pelvis tilt, forward head.

    All three normalised by a body-scale distance so the numbers do not
    depend on the subject's size or distance from camera -- the same
    normalisation principle `rep_signals.dart` already applies at runtime.

    ``forward_axis`` is passed in rather than picked per clip: an earlier
    version chose whichever horizontal axis had the larger spread on EACH
    clip individually, which mixes different clips' answers into one pooled
    distribution if the camera setup is not perfectly uniform across
    subjects. Picking one axis globally (see ``calibrate``) is the
    conservative choice; it does not fix the deeper issue that "standing
    between reps" is not "holding a neutral posture" -- see
    core/plans/PLAN_R10_POSTURE_2026-08-08.md section 2.

    VERTICAL_AXIS convention (confirmed by `extract_mmfit_targets.py`'s
    `verify_layout`): larger value = higher up. So positive shoulder_asym /
    pelvis_tilt means the RIGHT side sits higher, not lower.
    """
    l_sh, r_sh = joints[:, :, L_SHOULDER], joints[:, :, R_SHOULDER]
    l_hip, r_hip = joints[:, :, L_HIP], joints[:, :, R_HIP]
    head, thorax = joints[:, :, HEAD], joints[:, :, THORAX]

    shoulder_width = _dist(l_sh, r_sh)
    hip_width = _dist(l_hip, r_hip)
    torso_len = _dist(thorax, joints[:, :, SPINE])

    shoulder_asym = (r_sh[VERTICAL_AXIS] - l_sh[VERTICAL_AXIS]) / np.where(
        shoulder_width == 0, 1e-9, shoulder_width
    )
    pelvis_tilt = (r_hip[VERTICAL_AXIS] - l_hip[VERTICAL_AXIS]) / np.where(
        hip_width == 0, 1e-9, hip_width
    )

    shoulder_mid = (l_sh + r_sh) / 2
    forward_head = (head[forward_axis] - shoulder_mid[forward_axis]) / np.where(
        torso_len == 0, 1e-9, torso_len
    )

    return {
        "shoulder_asym": shoulder_asym,
        "pelvis_tilt": pelvis_tilt,
        "forward_head": forward_head,
    }


def iter_standing_windows(archive: Path):
    """Yields (workout, exercise, joints-at-top-phase) for squats/lunges sets."""
    with zipfile.ZipFile(archive) as z:
        names = set(z.namelist())
        for i in range(21):
            w = f"w{i:02d}"
            pose_name = f"mm-fit/{w}/{w}_pose_3d.npy"
            label_name = f"mm-fit/{w}/{w}_labels.csv"
            if pose_name not in names or label_name not in names:
                continue
            pose = np.load(io.BytesIO(z.read(pose_name)))
            frame_ids = pose[0, :, 0].astype(int)
            joints_all = pose[:, :, 1:]
            index = {f: i for i, f in enumerate(frame_ids)}
            rows = csv.reader(
                io.StringIO(z.read(label_name).decode("utf-8", "replace"))
            )
            for row in rows:
                if len(row) < 4 or not row[3].strip():
                    continue
                name = row[3].strip()
                if name not in STANDING_EXERCISES:
                    continue
                start, end = index.get(int(row[0])), index.get(int(row[1]))
                if start is None or end is None or end - start < 10:
                    continue
                clip = joints_all[:, start:end, :]
                # Mean of both legs, same reasoning as `driver_signal` in
                # extract_mmfit_targets.py: one occluded leg drags a single
                # side to nonsense, the mean stays usable.
                driver = (
                    leg_angle(clip, L_HIP, L_KNEE, L_FOOT)
                    + leg_angle(clip, R_HIP, R_KNEE, R_FOOT)
                ) / 2
                mask = top_phase_mask(driver)
                if not mask.any():
                    continue
                yield w, name, clip[:, mask, :]


def calibrate(archive: Path) -> dict:
    windows = list(iter_standing_windows(archive))

    # One forward axis for the whole dataset, chosen once from the pooled
    # head-to-shoulder-midpoint spread across every window -- not per clip.
    # See `posture_metrics`'s docstring for why per-clip selection was wrong.
    horiz_axes = [a for a in (0, 1) if a != VERTICAL_AXIS]
    pooled_offsets = {a: [] for a in horiz_axes}
    for _workout, _name, joints in windows:
        sh_mid = (joints[:, :, L_SHOULDER] + joints[:, :, R_SHOULDER]) / 2
        head = joints[:, :, HEAD]
        for a in horiz_axes:
            pooled_offsets[a].extend((head[a] - sh_mid[a]).tolist())
    forward_axis = max(horiz_axes, key=lambda a: np.std(pooled_offsets[a]))

    metrics: dict[str, list[float]] = {
        "shoulder_asym": [],
        "pelvis_tilt": [],
        "forward_head": [],
    }
    sets_seen = 0
    for _workout, _name, joints in windows:
        sets_seen += 1
        m = posture_metrics(joints, forward_axis)
        for key in metrics:
            metrics[key].extend(float(v) for v in m[key])

    out = {"sets_seen": sets_seen, "forward_axis": forward_axis}
    for key, values in metrics.items():
        arr = np.array(values)
        out[key] = {
            "n_frames": len(arr),
            "p05": round(float(np.percentile(arr, 5)), 4),
            "p25": round(float(np.percentile(arr, 25)), 4),
            "median": round(float(np.percentile(arr, 50)), 4),
            "p75": round(float(np.percentile(arr, 75)), 4),
            "p95": round(float(np.percentile(arr, 95)), 4),
            "std": round(float(np.std(arr)), 4),
        }
    return out


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("archive", type=Path, help="path to mm-fit.zip")
    ap.add_argument("--out", type=Path, default=None)
    args = ap.parse_args()

    result = calibrate(args.archive)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
