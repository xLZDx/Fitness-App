"""SCAN-G1 reference-fidelity check (core/SCAN_G1_SCOPE.md, R6(c)).

Compares the app's Scan screen, rendered by `flutter test` as the
`composed_scan_fidelity_<state>_<theme>.png` goldens (390x844 @2x over the
flat base colour, transparent camera, reduce motion so the sweep is at
t=0), with the design reference rendered the same way by
`tools/design/render_reference_scan.js` (`scan_<state>_<theme>_flat.png`).

Region of interest: the full width from y=46 (under the status bar) down to
the bottom of that state's primary button, read from `scan_anchors.json` --
i.e. exactly the part of the screen the reference draws. Everything the
reference does not model sits below it and is not judged here.

Masked out (the ONLY mask): the bracket window's interior -- the card inset
by 23px, so the 2px bracket stroke at inset 20..22 stays inside the
comparison -- because that is where the camera preview goes in the app and
the reference draws nothing there. The centre glyph and the hint sit inside
that window and ARE compared: their boxes (dilated by 2px) are subtracted
back out of the mask.

Metrics per frame, at 2x: the share of compared pixels whose largest channel
difference exceeds 40/255, and the mean absolute difference over all
channels. Thresholds: <= 2.5 % bad-pixel-share (aiming_dark: <= 3.2 %, a
GPT-PM-approved per-frame exception -- see MAX_BAD_PIXEL_SHARE_OVERRIDES'
own comment) and <= 5.0/255 mean, every frame. A FAIL is a finding to
remediate, not a number to tune -- the one existing override was obtained
through a Rosetta plan and GPT-PM APPROVE, not by editing this file alone.

usage: py -3 tools/design/scan_fidelity_check.py [--goldens DIR] [--reference DIR] [--json OUT] [--diff-dir DIR]
exit 0 = all four frames pass; 1 = any fails; 2 = an input is missing.
"""

from __future__ import annotations

import argparse
import json
import os
import sys

try:
    from PIL import Image, ImageChops
except ImportError:  # pragma: no cover
    print("needs Pillow: py -3 -m pip install pillow", file=sys.stderr)
    sys.exit(2)

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
DEFAULT_GOLDENS = os.path.join(ROOT, "mobile", "test", "golden", "goldens")
DEFAULT_REFERENCE = os.path.join(ROOT, "mobile", "test", "golden", "reference")

DSF = 2
ROI_TOP_LOGICAL = 46
WINDOW_INSET_LOGICAL = 23
TEXT_DILATE_LOGICAL = 2
CHANNEL_THRESHOLD = 40
MAX_BAD_PIXEL_SHARE = 2.5  # percent -- every frame except the override below
# Rosetta plan fitness_app-2026-09-04T16-17-19-994Z-588ce5, GPT-PM APPROVE on
# hash cb7afce8caa0c6a8b90ede096df28a073c5675e07fcaf7a39f8588e00b25e248
# (core/DECISION_LOG.md, SCAN-G1). aiming_dark alone: two independent
# measurements (3.102%, then 2.965% after the canonical-Archivo correction)
# with the diff confined to text/glyph/hairline anti-aliasing edges across
# the whole frame and no localised or systematic defect -- the practical
# floor of comparing Chromium's rasteriser against Skia's at this ROI size,
# per GPT-PM's own review. The other three frames are NOT raised; changing
# this dict for any key but "aiming_dark" needs its own approval the same
# way this one required.
MAX_BAD_PIXEL_SHARE_OVERRIDES = {"aiming_dark": 3.2}  # percent
MAX_MEAN_DIFF = 5.0  # /255, unchanged for every frame

FRAMES = [(s, t) for s in ("aiming", "found") for t in ("dark", "light")]


def rect(anchor: dict) -> tuple[float, float, float, float]:
    r = anchor["rect"]
    return r["x"], r["y"], r["x"] + r["w"], r["y"] + r["h"]


def scaled(box, dilate: float = 0.0) -> tuple[int, int, int, int]:
    l, t, r, b = box
    return (
        int(round((l - dilate) * DSF)),
        int(round((t - dilate) * DSF)),
        int(round((r + dilate) * DSF)),
        int(round((b + dilate) * DSF)),
    )


def build_mask(size: tuple[int, int], anchors: dict) -> Image.Image:
    """255 where a pixel is compared, 0 where it is masked out."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    roi_bottom = rect(anchors["primary_button"])[3]
    roi = scaled((0, ROI_TOP_LOGICAL, w / DSF, roi_bottom))
    mask.paste(255, roi)
    card = rect(anchors["card"])
    window = (
        card[0] + WINDOW_INSET_LOGICAL,
        card[1] + WINDOW_INSET_LOGICAL,
        card[2] - WINDOW_INSET_LOGICAL,
        card[3] - WINDOW_INSET_LOGICAL,
    )
    mask.paste(0, scaled(window))
    for name in ("centre_glyph", "hint"):
        mask.paste(255, scaled(rect(anchors[name]), TEXT_DILATE_LOGICAL))
    return mask


def compare(app_path: str, ref_path: str, anchors: dict, diff_path: str | None, frame: str):
    app = Image.open(app_path).convert("RGB")
    ref = Image.open(ref_path).convert("RGB")
    if app.size != ref.size:
        return {"error": f"size mismatch app={app.size} ref={ref.size}"}
    mask = build_mask(app.size, anchors)
    diff = ImageChops.difference(app, ref)
    # Max channel per pixel.
    r, g, b = diff.split()
    max_channel = ImageChops.lighter(ImageChops.lighter(r, g), b)
    compared = 0
    bad = 0
    total_diff = 0
    mpx = mask.load()
    dpx = diff.load()
    mxpx = max_channel.load()
    w, h = app.size
    for y in range(h):
        for x in range(w):
            if mpx[x, y] == 0:
                continue
            compared += 1
            if mxpx[x, y] > CHANNEL_THRESHOLD:
                bad += 1
            dr, dg, db = dpx[x, y]
            total_diff += dr + dg + db
    bad_share = 100.0 * bad / compared if compared else 0.0
    mean_diff = total_diff / (3 * compared) if compared else 0.0
    ceiling = MAX_BAD_PIXEL_SHARE_OVERRIDES.get(frame, MAX_BAD_PIXEL_SHARE)
    passed = bad_share <= ceiling and mean_diff <= MAX_MEAN_DIFF
    if diff_path:
        # A visual: the max-channel diff amplified x4 where compared, black
        # elsewhere, next to the two inputs.
        amplified = max_channel.point(lambda v: min(255, v * 4))
        amplified = Image.composite(amplified, Image.new("L", app.size, 0), mask)
        sheet = Image.new("RGB", (w * 3, h), (0, 0, 0))
        sheet.paste(ref, (0, 0))
        sheet.paste(app, (w, 0))
        sheet.paste(amplified.convert("RGB"), (w * 2, 0))
        sheet.save(diff_path)
    return {
        "compared_pixels": compared,
        "bad_pixels": bad,
        "bad_pixel_share_pct": round(bad_share, 3),
        "mean_abs_diff_255": round(mean_diff, 3),
        "bad_pixel_share_ceiling_pct": ceiling,
        "pass": passed,
    }


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--goldens", default=DEFAULT_GOLDENS)
    ap.add_argument("--reference", default=DEFAULT_REFERENCE)
    ap.add_argument("--json", default=None, help="write the per-frame numbers here")
    ap.add_argument("--diff-dir", default=None, help="write ref|app|diff sheets here")
    args = ap.parse_args(argv)

    anchors_path = os.path.join(args.reference, "scan_anchors.json")
    if not os.path.exists(anchors_path):
        print(f"missing {anchors_path}", file=sys.stderr)
        return 2
    with open(anchors_path, encoding="utf-8") as f:
        anchors_all = json.load(f)

    if args.diff_dir:
        os.makedirs(args.diff_dir, exist_ok=True)

    results = {
        "thresholds": {
            "channel_threshold_255": CHANNEL_THRESHOLD,
            "max_bad_pixel_share_pct": MAX_BAD_PIXEL_SHARE,
            "max_bad_pixel_share_pct_overrides": MAX_BAD_PIXEL_SHARE_OVERRIDES,
            "max_mean_abs_diff_255": MAX_MEAN_DIFF,
            "roi": f"x 0..390, y {ROI_TOP_LOGICAL}..primary_button.bottom (logical), at {DSF}x",
            "mask": f"card inset {WINDOW_INSET_LOGICAL} minus centre_glyph/hint dilated {TEXT_DILATE_LOGICAL}",
        },
        "frames": {},
    }
    all_ok = True
    print(f"{'frame':<16}{'compared':>10}{'bad px':>9}{'bad %':>8}{'mean':>8}  verdict")
    for state, theme in FRAMES:
        key = f"{state}_{theme}"
        app_path = os.path.join(args.goldens, f"composed_scan_fidelity_{key}.png")
        ref_path = os.path.join(args.reference, f"scan_{key}_flat.png")
        missing = [p for p in (app_path, ref_path) if not os.path.exists(p)]
        if missing:
            print(f"{key:<16} MISSING {missing}")
            results["frames"][key] = {"error": f"missing {missing}"}
            all_ok = False
            continue
        diff_path = (
            os.path.join(args.diff_dir, f"scan_fidelity_diff_{key}.png") if args.diff_dir else None
        )
        res = compare(app_path, ref_path, anchors_all[f"{theme}_{state}"], diff_path, key)
        results["frames"][key] = res
        if "error" in res:
            print(f"{key:<16} ERROR {res['error']}")
            all_ok = False
            continue
        verdict = "PASS" if res["pass"] else "FAIL"
        all_ok &= res["pass"]
        print(
            f"{key:<16}{res['compared_pixels']:>10}{res['bad_pixels']:>9}"
            f"{res['bad_pixel_share_pct']:>8.3f}{res['mean_abs_diff_255']:>8.3f}  {verdict}"
        )
    results["pass"] = all_ok
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(results, f, indent=1)
            f.write("\n")
    print("ALL PASS" if all_ok else "FAIL")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
