"""Read and rewrite the catalogue JSON without reformatting it.

Extracted from `correct_exercise_text.py` after that tool's first run produced a
54,118-line diff for three corrected strings: it wrote `indent=2` through
`Path.write_text`, against a file indented by one space and stored with LF, on a
platform that translates newlines on write.

A formatting-only diff over a data file is worse than no diff. It defeats
review, it defeats `git blame`, and it makes the next person's genuine change
indistinguishable from this one.

This lives in its own module because two tools now rewrite these files and
copying the fix would mean maintaining the same subtlety twice -- which is how
the second copy ends up being the one that still has the bug.
"""

from __future__ import annotations

import json
from pathlib import Path


def load_json(path: Path):
    return json.loads(Path(path).read_text(encoding="utf-8"))


def detect_format(path: Path) -> tuple[int, str]:
    """The indent width and line ending [path] is currently stored with.

    Both are read rather than assumed: `exercises_vendor.json` and
    `exercises_vendor.ru.json` do not agree with each other, which is exactly
    why neither can be a constant.
    """
    raw = Path(path).read_bytes()
    first_line = raw.split(b"\n", 1)[0]
    newline = "\r\n" if first_line.endswith(b"\r") else "\n"

    indent = 2
    for line in raw.decode("utf-8").splitlines()[1:]:
        stripped = line.lstrip(" ")
        if stripped and stripped != line:
            indent = len(line) - len(stripped)
            break
    return indent, newline


def dump_json(path: Path, data) -> None:
    """Rewrite [path] in the format it already has."""
    path = Path(path)
    indent, newline = detect_format(path)
    with open(path, "w", encoding="utf-8", newline=newline) as fh:
        fh.write(json.dumps(data, ensure_ascii=False, indent=indent) + "\n")
