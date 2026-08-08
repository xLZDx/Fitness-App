"""Derive per-exercise reference joint angles from the MM-Fit dataset.

Why this script exists
----------------------
The form coach compares a detected pose against a reference and names the
error. Every threshold behind that comparison used to be a guess, and the
guesses were measurably wrong: of five configurations checked by hand on
2026-08-08, four did not survive contact with data. This script replaces the
guessing with a measurement over 6,160 labelled repetitions.

Dataset
-------
MM-Fit (Stromback, Huang, Radu -- IMWUT 2020), CC BY 4.0.
https://doi.org/10.5281/zenodo.7672767

Layout, verified against the archive rather than assumed:

    mm-fit/<wNN>/<wNN>_pose_3d.npy   float64, shape (3, frames, 18)
    mm-fit/<wNN>/<wNN>_labels.csv    start_frame, end_frame, reps, exercise

Slot 0 of the last axis is the frame number, not a joint; joints are slots
1..17. The joint order is Human3.6M. That was not taken on faith either --
running this module with ``--verify-layout`` prints the mean height of every
joint, and the assertion the layout has to pass is that feet sit below hips
which sit below shoulders which sit below the head.

What it does NOT give us
------------------------
MM-Fit labels an exercise and a repetition count. It does not label form
quality. So these numbers describe what a repetition of this movement looks
like when ordinary people do it -- not what a *correct* one looks like. Use
them as the centre of a plausible range, never as a pass/fail line on their
own.
"""

from __future__ import annotations

import argparse
import csv
import io
import json
import zipfile
from dataclasses import dataclass, asdict
from pathlib import Path

import numpy as np

# Human3.6M 17-joint order, confirmed empirically by joint heights.
ROOT = 0
R_HIP, R_KNEE, R_FOOT = 1, 2, 3
L_HIP, L_KNEE, L_FOOT = 4, 5, 6
SPINE, THORAX, NECK, HEAD = 7, 8, 9, 10
L_SHOULDER, L_ELBOW, L_WRIST = 11, 12, 13
R_SHOULDER, R_ELBOW, R_WRIST = 14, 15, 16

VERTICAL_AXIS = 2


@dataclass
class ExerciseSpec:
    """How to read one movement out of a skeleton.

    ``driver`` is the joint triple whose angle rises and falls once per
    repetition. ``low``/``high`` bound the hysteresis used to count reps: a
    rep is one descent below ``low`` followed by a return above ``high``. Two
    thresholds rather than one because a single threshold double-counts every
    time the signal jitters across it at the bottom of a rep.
    """

    name: str
    driver: tuple[int, int, int]
    mirror: tuple[int, int, int] | None
    low: float
    high: float


# Thresholds here are seeds for the sweep in `calibrate`, not final values.
SPECS: dict[str, ExerciseSpec] = {
    "squats": ExerciseSpec(
        "squats", (L_HIP, L_KNEE, L_FOOT), (R_HIP, R_KNEE, R_FOOT), 140, 160
    ),
    "pushups": ExerciseSpec(
        "pushups", (L_SHOULDER, L_ELBOW, L_WRIST),
        (R_SHOULDER, R_ELBOW, R_WRIST), 120, 150
    ),
    "bicep_curls": ExerciseSpec(
        "bicep_curls", (L_SHOULDER, L_ELBOW, L_WRIST),
        (R_SHOULDER, R_ELBOW, R_WRIST), 70, 140
    ),
    "lunges": ExerciseSpec(
        "lunges", (L_HIP, L_KNEE, L_FOOT), (R_HIP, R_KNEE, R_FOOT), 140, 165
    ),
    "situps": ExerciseSpec(
        "situps", (L_SHOULDER, L_HIP, L_KNEE), (R_SHOULDER, R_HIP, R_KNEE),
        120, 150
    ),
    "dumbbell_shoulder_press": ExerciseSpec(
        "dumbbell_shoulder_press", (L_SHOULDER, L_ELBOW, L_WRIST),
        (R_SHOULDER, R_ELBOW, R_WRIST), 100, 150
    ),
}


def angle_deg(joints: np.ndarray, a: int, b: int, c: int) -> np.ndarray:
    """Angle at ``b`` in the a-b-c chain, per frame, in degrees."""
    ba = joints[:, :, a] - joints[:, :, b]
    bc = joints[:, :, c] - joints[:, :, b]
    denom = np.linalg.norm(ba, axis=0) * np.linalg.norm(bc, axis=0)
    cos = (ba * bc).sum(0) / np.where(denom == 0, 1e-9, denom)
    return np.degrees(np.arccos(np.clip(cos, -1.0, 1.0)))


def driver_signal(joints: np.ndarray, spec: ExerciseSpec) -> np.ndarray:
    """Mean of the left and right driver angles.

    Averaging the sides rather than picking one is what makes the signal
    survive a limb the camera could not see: a single occluded knee drags one
    side to nonsense, the mean stays usable. It also means the signal is blind
    to left/right asymmetry -- fine here, because asymmetry is a posture
    metric, not a rep-counting one.
    """
    left = angle_deg(joints, *spec.driver)
    if spec.mirror is None:
        return left
    return (left + angle_deg(joints, *spec.mirror)) / 2


def count_reps(signal: np.ndarray, low: float, high: float) -> int:
    n, armed = 0, False
    for v in signal:
        if v < low and not armed:
            armed = True
        elif v > high and armed:
            armed = False
            n += 1
    return n


def iter_sets(archive: Path):
    """Yields (workout, exercise, reps, joints) for every labelled set."""
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
            joints = pose[:, :, 1:]
            index = {f: i for i, f in enumerate(frame_ids)}
            rows = csv.reader(
                io.StringIO(z.read(label_name).decode("utf-8", "replace"))
            )
            for row in rows:
                if len(row) < 4 or not row[3].strip():
                    continue
                start, end = index.get(int(row[0])), index.get(int(row[1]))
                if start is None or end is None or end - start < 10:
                    continue
                yield w, row[3].strip(), int(row[2]), joints[:, start:end, :]


def _sweep(samples: list[tuple[int, np.ndarray]]) -> tuple[int, float, float]:
    best = (-1, 0.0, 0.0)
    for low in range(40, 171, 5):
        for high in range(low + 5, 181, 5):
            hits = sum(
                count_reps(sig, low, high) == reps for reps, sig in samples
            )
            if hits > best[0]:
                best = (hits, float(low), float(high))
    return best


def _rate(samples: list[tuple[int, np.ndarray]], low: float, high: float) -> float:
    if not samples:
        return 0.0
    hits = sum(count_reps(sig, low, high) == reps for reps, sig in samples)
    return hits / len(samples)


def calibrate(archive: Path) -> dict:
    """Sweeps the hysteresis pair per exercise and keeps the best.

    Three numbers are reported per exercise, and only the third means
    anything:

    ``exact_rate_at_seed``   accuracy at the hand-guessed thresholds.
    ``exact_rate_in_sample`` accuracy of the swept thresholds on the same sets
                             they were fitted to. Always flattering, always
                             ~700 trials deep, never evidence.
    ``exact_rate_holdout``   the swept thresholds scored on workouts the sweep
                             never saw.

    The split is by workout, not by set. Splitting by set would put two sets
    from the same session -- same person, same camera, same lighting -- on
    both sides of the line, and the holdout would be measuring memorisation
    rather than transfer. Odd-numbered workouts fit, even-numbered score.
    """
    sets: dict[str, list[tuple[str, int, np.ndarray]]] = {k: [] for k in SPECS}
    for workout, name, reps, joints in iter_sets(archive):
        if name in SPECS:
            sets[name].append((workout, reps, driver_signal(joints, SPECS[name])))

    out = {}
    for name, spec in SPECS.items():
        samples = sets[name]
        if not samples:
            continue
        fit = [(r, s) for w, r, s in samples if int(w[1:]) % 2 == 1]
        held = [(r, s) for w, r, s in samples if int(w[1:]) % 2 == 0]
        alls = [(r, s) for _, r, s in samples]

        hits, low, high = _sweep(fit if fit else alls)
        bottoms = [float(np.percentile(s, 5)) for _, s in alls]
        tops = [float(np.percentile(s, 95)) for _, s in alls]
        out[name] = {
            "sets": len(samples),
            "reps": sum(r for _, r, _ in samples),
            "fit_sets": len(fit),
            "holdout_sets": len(held),
            "low": low,
            "high": high,
            "exact_rate_at_seed": round(_rate(alls, spec.low, spec.high), 4),
            "exact_rate_in_sample": round(hits / max(len(fit), 1), 4),
            "exact_rate_holdout": round(_rate(held, low, high), 4),
            "trials": len(range(40, 171, 5)) * 27,
            "bottom_deg": round(float(np.median(bottoms)), 1),
            "bottom_p25": round(float(np.percentile(bottoms, 25)), 1),
            "bottom_p75": round(float(np.percentile(bottoms, 75)), 1),
            "top_deg": round(float(np.median(tops)), 1),
            "driver": list(spec.driver),
        }
    return out


def verify_layout(archive: Path) -> None:
    with zipfile.ZipFile(archive) as z:
        pose = np.load(io.BytesIO(z.read("mm-fit/w01/w01_pose_3d.npy")))
    means = pose[:, :, 1:].mean(axis=1)
    height = means[VERTICAL_AXIS]
    for label, j in (
        ("l_foot", L_FOOT), ("l_knee", L_KNEE), ("l_hip", L_HIP),
        ("l_shoulder", L_SHOULDER), ("head", HEAD),
    ):
        print(f"  {label:<12} height={height[j]:8.1f}")
    assert height[L_FOOT] < height[L_KNEE] < height[L_HIP], "leg order wrong"
    assert height[L_HIP] < height[L_SHOULDER] < height[HEAD], "trunk order wrong"
    print("  layout OK")


def main() -> None:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("archive", type=Path, help="path to mm-fit.zip")
    ap.add_argument("--out", type=Path, default=None)
    ap.add_argument("--verify-layout", action="store_true")
    args = ap.parse_args()

    if args.verify_layout:
        verify_layout(args.archive)
        return

    result = calibrate(args.archive)
    text = json.dumps(result, indent=2, sort_keys=True)
    if args.out:
        args.out.write_text(text + "\n", encoding="utf-8")
        print(f"wrote {args.out}")
    else:
        print(text)


if __name__ == "__main__":
    main()
