"""Builds mobile/assets/fonts/MaterialSymbolsSharp-scan.ttf.

SCAN-G1 (core/SCAN_G1_SCOPE.md, R6): the Scan screen draws its four glyphs
with the design reference's own icon font -- Material Symbols Sharp, the
variable font Google ships at
https://github.com/google/material-design-icons -- so the fidelity gate can
compare the app's pixels with the reference's without masking the icons.
The full font is 8.8 MB; the app needs six glyphs, so this script subsets
it with fontTools, keeping every variation axis (FILL, GRAD, opsz, wght) so
Flutter can pick the same optical size the reference does.

Reproducible: `py -3 tools/design/build_symbols_subset.py <path to the
variable font>`; the codepoints below are the canonical ones from the
repository's `MaterialSymbolsSharp[FILL,GRAD,opsz,wght].codepoints` file.
The licence (Apache-2.0) is copied next to the output as
`LICENSE-MaterialSymbols.txt`.
"""

from __future__ import annotations

import os
import sys

from fontTools import subset, ttLib

GLYPHS = {
    0xE3B5: "center_focus_weak",  # viewfinder centre
    0xE3B4: "center_focus_strong",  # Recognise
    0xE5D5: "refresh",  # Scan again
    0xE5C8: "arrow_forward",  # Open exercises
    0xE413: "photo_library",  # From gallery (production row)
    0xE04B: "videocam",  # Live labeler (production row)
}

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.normpath(
    os.path.join(HERE, "..", "..", "mobile", "assets", "fonts",
                 "MaterialSymbolsSharp-scan.ttf"))


def main(argv: list[str]) -> int:
    if len(argv) != 2:
        print("usage: build_symbols_subset.py <MaterialSymbolsSharp[...].ttf>",
              file=sys.stderr)
        return 2
    src = argv[1]
    font = ttLib.TTFont(src)
    axes = [(a.axisTag, a.minValue, a.defaultValue, a.maxValue)
            for a in font["fvar"].axes]
    opts = subset.Options()
    opts.name_IDs = ["*"]
    opts.notdef_outline = True
    opts.recalc_bounds = True
    opts.layout_features = ["*"]
    s = subset.Subsetter(opts)
    s.populate(unicodes=list(GLYPHS))
    s.subset(font)
    font.save(OUT)
    check = ttLib.TTFont(OUT)
    kept = {cp for table in check["cmap"].tables for cp in table.cmap}
    missing = [f"{cp:04x} {name}" for cp, name in GLYPHS.items()
               if cp not in kept]
    if missing:
        print("missing glyphs:", missing, file=sys.stderr)
        return 1
    print(f"wrote {OUT} ({os.path.getsize(OUT)} bytes); axes {axes}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
