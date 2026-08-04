# -*- coding: utf-8 -*-
"""Where the purchased library actually lives.

WHY THIS EXISTS

Four scripts each hard-coded their own absolute path to the same three vendor
files, and three of them were wrong: they pointed at `D:/Downloads/`, while the
files sit one directory deeper in `D:/Downloads/Video/New folder/`. Only
`link_vendor_equipment.py` had the current path, because it was written after
the files moved.

The failure was quiet in the worst way. `build_vendor_catalog.py` raised on a
missing zip, and that was read -- by me, in two commit messages and repeatedly
in chat -- as "the vendor bundle is not present on this machine", which is a
statement about the machine. It was a statement about a constant. The catalog
builder has been unrunnable, and the reason was recorded as an unavoidable
environment limitation rather than as a one-line bug.

So: one definition, and an env var, because the root cause is an absolute path
on one person's disk baked into a repository.

    set FITNESS_VENDOR_DIR=E:/somewhere/else   (Windows)
    export FITNESS_VENDOR_DIR=/mnt/vendor      (POSIX)

`missing()` is here so a script can say which file is absent and where it
looked, instead of raising a bare FileNotFoundError that reads as a broken
machine.
"""

from __future__ import annotations

import os
from pathlib import Path

#: Operator's copy, 2026-08-04. Override with FITNESS_VENDOR_DIR.
DEFAULT_VENDOR_DIR = Path("D:/Downloads/Video/New folder")

VENDOR_DIR = Path(os.environ.get("FITNESS_VENDOR_DIR") or DEFAULT_VENDOR_DIR)

#: 45 GB of 2160p clips, one per exercise per body. The catalog's video keys.
BUNDLE_ZIP = VENDOR_DIR / "4K UHD 2160P.zip"

#: Their metadata sheet: muscles, steps, tips, equipment label. 79% filled.
VENDOR_META = VENDOR_DIR / "1500+ exercise data.xlsx"

#: The plain list of movement names, used by the legacy matching pass.
EXERCISE_LIST = VENDOR_DIR / "EXERCISE LIST.xlsx"

#: Smaller renditions, kept for reference. Nothing in the pipeline reads them.
BUNDLE_1080 = VENDOR_DIR / "FULL HD 1080P.zip"
BUNDLE_720 = VENDOR_DIR / "HD 720p LOWEST FILE SIZE.zip"

#: The working drop folder: extracted clips, posters, ad-hoc captures. The
#: vendor archives sit inside it, which is how three scripts came to point one
#: directory too shallow. Separate constant because it is a different thing --
#: `VENDOR_DIR` is what was purchased, this is what is being worked on.
DROP_DIR = Path(os.environ.get("FITNESS_DROP_DIR") or VENDOR_DIR.parent)


def missing(*paths: Path) -> list[Path]:
    """Which of [paths] are not on disk."""
    return [p for p in paths if not p.exists()]


def require(*paths: Path) -> None:
    """Exit with a message naming the absent files and the directory searched.

    Deliberately not a bare raise: the whole point of this module is that
    "file not found" was previously indistinguishable from "this machine does
    not have the vendor bundle", and only one of those is worth telling an
    operator about.
    """
    absent = missing(*paths)
    if not absent:
        return
    raise SystemExit(
        "vendor files not found in {}:\n{}\n\n"
        "Set FITNESS_VENDOR_DIR if the library lives somewhere else.".format(
            VENDOR_DIR, "\n".join(f"    {p.name}" for p in absent)
        )
    )
