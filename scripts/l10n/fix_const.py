"""Drop `const` where the l10n migration made a constant expression impossible.

`AppLocalizations.of(context).x` is a runtime lookup, so any `const Text(...)`
that now wraps one is a compile error. Rather than guess which call sites those
are from a regex, this uses `flutter analyze` as the oracle: it reports every one
with an exact file:line, and each is fixed by removing the nearest enclosing
`const` keyword.

Runs to a fixed point (or gives up loudly) so a `const` nested two levels deep
gets both levels.

Usage: python scripts/l10n/fix_const.py
"""
from __future__ import annotations

import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOBILE = ROOT / "mobile"

# " error - Methods can't be invoked in constant expressions - lib\a.dart:43:14 - const_eval_method_invocation"
LINE = re.compile(
    r"-\s+(?P<file>lib[\\/][^:]+):(?P<line>\d+):(?P<col>\d+)\s+-\s+"
    r"(?P<code>const_eval_method_invocation|"
    r"const_with_non_constant_argument|invalid_constant|"
    r"non_constant_list_element|non_constant_map_value|"
    r"non_constant_default_value)"
)


def analyze() -> list[tuple[Path, int]]:
    out = subprocess.run(
        ["flutter", "analyze"],
        cwd=MOBILE,
        capture_output=True,
        text=True,
        shell=True,
    ).stdout
    hits = []
    for m in LINE.finditer(out):
        hits.append((MOBILE / m.group("file").replace("\\", "/"),
                     int(m.group("line"))))
    return hits


def strip_const_near(path: Path, line_no: int) -> bool:
    """Remove the `const` governing the expression reported at `line_no`.

    Searches the reported line first, then walks upward: Dart formatting often
    puts `const Foo(` on an earlier line than the offending argument.
    """
    lines = path.read_text(encoding="utf-8").split("\n")
    idx = line_no - 1
    for i in range(idx, max(-1, idx - 12), -1):
        if i < 0 or i >= len(lines):
            continue
        new = re.sub(r"(?<![\w$])const\s+(?=[A-Za-z_\[<])", "", lines[i], count=1)
        if new != lines[i]:
            lines[i] = new
            path.write_text("\n".join(lines), encoding="utf-8")
            return True
    return False


def main() -> None:
    for round_no in range(1, 13):
        hits = analyze()
        if not hits:
            print(f"clean after {round_no - 1} round(s)")
            return
        # Deduplicate per (file, line); process bottom-up so earlier line numbers
        # stay valid within a file.
        fixed = 0
        for path, line_no in sorted(set(hits), key=lambda t: (str(t[0]), -t[1])):
            if strip_const_near(path, line_no):
                fixed += 1
        print(f"round {round_no}: {len(set(hits))} const errors, {fixed} fixed")
        if fixed == 0:
            raise SystemExit(
                "made no progress — remaining const errors need a human:\n  "
                + "\n  ".join(f"{p}:{n}" for p, n in sorted(set(hits))[:10])
            )
    raise SystemExit("still not clean after 12 rounds")


if __name__ == "__main__":
    main()
