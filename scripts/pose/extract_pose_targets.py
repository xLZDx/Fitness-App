"""Measure candidate pose targets off the catalogue's own posters.

## Why this exists

`pose_target.dart` ships geometry for two movements — squat and push-up — while
`exercises_vendor.json` tags 540 exercises with one of EIGHT `poseTargetId`
values. The other six (`curl`, `hinge`, `lunge`, `situp`, `overhead_press`,
`calf_raise`) are labelled with nothing to compare against, so the coach cannot
coach them.

## Why measured, and why only sometimes

`squatBottomTarget`'s own comment settles half the question: hand-authoring a
SHAPE is honest here, because `poseMatchScore` normalises away position and
size, so the numbers describe a movement's geometry rather than a person.

The half it does not settle is the viewing angle. Every shipped target is a
SIDE view, and the on-screen outline is an instruction to stand side-on. A
poster shot from the front, traced faithfully, produces a shape that is
correct for the picture and wrong for the instruction — worse than a
hand-authored side view, because it looks measured.

So this script measures, and also measures **whether the measurement is
usable**: `side_score` is how nearly the left and right joints coincide
horizontally, which is what a true side view looks like. A frontal poster
scores near 0 and is reported as unusable rather than quietly emitted.

Output is a REPORT, not a Dart file. A human picks from it, because "this
poster is a lunge seen from the side" is a judgement about a picture.

Usage:
    D:/tools/ml-train-env/Scripts/python.exe scripts/pose/extract_pose_targets.py
    ... [--tag lunge] [--limit 12] [--out core/pose_targets/measured.json]

Two environment facts, both learned the hard way:

* `mediapipe` lives ONLY in `D:/tools/ml-train-env`. `python` on PATH resolves
  to an unrelated project's venv (see DECISION_LOG, 2026-08-07) and does not
  have it.
* mediapipe 1.0.0 **removed** `mp.solutions`. Only the Tasks API remains, and
  it needs a model file that does not ship with the package -- downloaded
  once to `D:/tools/mediapipe-models/pose_landmarker_heavy.task`.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
CATALOGUE = REPO / "mobile" / "assets" / "data" / "exercises_vendor.json"
POSTERS = REPO / "mobile" / "assets" / "posters" / "men"
MODEL = Path(r"D:\tools\mediapipe-models\pose_landmarker_heavy.task")

#: The six joints a side-view target is scored on, as MediaPipe landmark
#: indices. Matches `_sideViewBones` in `pose_target.dart` — left side only,
#: because from the side the right limbs are behind the body and the
#: detector's estimates for them are guesses.
LEFT = {
    "leftShoulder": 11,
    "leftElbow": 13,
    "leftWrist": 15,
    "leftHip": 23,
    "leftKnee": 25,
    "leftAnkle": 27,
}
RIGHT = {
    "leftShoulder": 12,
    "leftElbow": 14,
    "leftWrist": 16,
    "leftHip": 24,
    "leftKnee": 26,
    "leftAnkle": 28,
}

#: Below this the poster is not a side view and its numbers must not be used
#: as one. Chosen so a clean profile passes and a three-quarter view does not;
#: it is a reporting threshold, not a law -- every row is printed with its
#: score so the cut can be re-judged without re-running the detector.
SIDE_MIN = 0.80


def load_rows() -> list[dict]:
    raw = json.loads(CATALOGUE.read_text(encoding="utf-8"))
    return raw if isinstance(raw, list) else raw.get("exercises", [])


def side_score(lm, w: float, h: float) -> float:  # noqa: D401
    """1.0 when left and right joints sit on top of each other in x.

    A profile hides one side behind the other, so the two sets of landmarks
    project to nearly the same horizontal position. A frontal shot spreads
    them by roughly shoulder width. Normalised by torso length so it does not
    depend on how large the figure is in the frame.
    """
    sh = lm[LEFT["leftShoulder"]]
    hip = lm[LEFT["leftHip"]]
    torso = abs(sh.y - hip.y) * h
    if torso <= 1e-6:
        return 0.0
    spread = 0.0
    for k in LEFT:
        spread += abs(lm[LEFT[k]].x - lm[RIGHT[k]].x) * w
    spread /= len(LEFT)
    # spread == 0 -> 1.0; spread == half a torso -> 0.0
    return max(0.0, 1.0 - spread / (0.5 * torso))


def visible(lm) -> float:
    """Lowest visibility across the six scored joints."""
    return min(lm[i].visibility for i in LEFT.values())


def landmarker():
    """A one-shot PoseLandmarker over the downloaded model.

    The Tasks API replaced `mp.solutions.pose.Pose` in mediapipe 1.0.0 and
    takes its model as a file rather than bundling one, so a missing model is
    a normal first-run condition and gets a message that says what to do about
    it -- not an ImportError three frames deep.
    """
    from mediapipe.tasks import python as mp_python
    from mediapipe.tasks.python import vision

    if not MODEL.exists():
        raise SystemExit(
            f"model missing: {MODEL}\n"
            "curl -fsSL -o that path "
            "https://storage.googleapis.com/mediapipe-models/pose_landmarker/"
            "pose_landmarker_heavy/float16/1/pose_landmarker_heavy.task")
    return vision.PoseLandmarker.create_from_options(
        vision.PoseLandmarkerOptions(
            base_options=mp_python.BaseOptions(
                model_asset_path=str(MODEL)),
            running_mode=vision.RunningMode.IMAGE,
            num_poses=1,
        ))


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--tag", default="")
    ap.add_argument("--limit", type=int, default=10)
    ap.add_argument("--out", default="")
    args = ap.parse_args()

    try:
        import mediapipe as mp
    except ImportError:
        print("mediapipe missing. Use D:/tools/ml-train-env/Scripts/python.exe")
        return 2
    import cv2

    rows = load_rows()
    by_tag: dict[str, list[dict]] = {}
    for r in rows:
        t = r.get("poseTargetId")
        if t and (not args.tag or t == args.tag):
            by_tag.setdefault(t, []).append(r)
    if not by_tag:
        print(f"no exercises for tag {args.tag!r}")
        return 2

    detector = landmarker()
    out: dict[str, list[dict]] = {}

    for tag in sorted(by_tag):
        print(f"\n=== {tag} ({len(by_tag[tag])} exercises) ===")
        print(f"{'exercise':<44}{'side':>6}{'vis':>6}")
        results = []
        for r in by_tag[tag][: args.limit]:
            p = POSTERS / f"{r['id']}.jpg"
            if not p.exists():
                continue
            img = cv2.imread(str(p))
            if img is None:
                continue
            h, w = img.shape[:2]
            res = detector.detect(mp.Image(
                image_format=mp.ImageFormat.SRGB,
                data=cv2.cvtColor(img, cv2.COLOR_BGR2RGB)))
            if not res.pose_landmarks:
                print(f"{r['id']:<44}{'-':>6}{'no pose':>10}")
                continue
            lm = res.pose_landmarks[0]
            s, v = side_score(lm, w, h), visible(lm)
            flag = "  <- usable" if s >= SIDE_MIN and v >= 0.5 else ""
            print(f"{r['id']:<44}{s:>6.2f}{v:>6.2f}{flag}")
            results.append({
                "id": r["id"],
                "title": r.get("title"),
                "side_score": round(s, 3),
                "min_visibility": round(v, 3),
                "joints": {
                    k: [round(lm[i].x, 4), round(lm[i].y, 4)]
                    for k, i in LEFT.items()
                },
            })
        results.sort(key=lambda d: -d["side_score"])
        out[tag] = results
        best = [d for d in results if d["side_score"] >= SIDE_MIN]
        # Printed even when empty, and especially then: a tag with no usable
        # poster is a tag whose target has to be hand-authored, and that is a
        # decision someone must make knowingly rather than discover later.
        print(f"  usable side views: {len(best)}/{len(results)}")
        if not best:
            print("  -> no side-view poster; this target must be hand-authored "
                  "from the movement, like squatBottomTarget")

    if args.out:
        pth = REPO / args.out
        pth.parent.mkdir(parents=True, exist_ok=True)
        pth.write_text(json.dumps(out, indent=2), encoding="utf-8")
        print(f"\nwrote {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
