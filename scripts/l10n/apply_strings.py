"""Apply the l10n spec: rewrite Dart call sites and regenerate the ARB files.

Run `extract_strings.py` first, then fill Russian into `ru.json`, then this.

Safety properties this script relies on:

* The English ARB value is the OLD TEXT byte for byte, so existing widget tests
  (which render in `en`) keep passing untouched.
* Adjacent-literal runs are replaced WHOLE, so a wrapped sentence never ends up
  half translated.
* Every key must have a Russian string. A missing one is an error, not a silent
  fallback to English -- a half-Russian screen is the exact complaint being fixed.

`const` breakage is deliberately NOT guessed at here. Substituting a runtime
lookup into a `const Text(...)` is a compile error, and `flutter analyze` reports
those with exact positions -- `fix_const.py` consumes that output. Guessing from
regex would silently mangle code the analyzer can pinpoint.

Usage:
    python scripts/l10n/apply_strings.py --dry-run
    python scripts/l10n/apply_strings.py
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
MOBILE = ROOT / "mobile"
SPEC = ROOT / "scripts" / "l10n" / "strings_spec.json"
RU = ROOT / "scripts" / "l10n" / "ru.json"
ARB_DIR = MOBILE / "lib" / "l10n"

IMPORT_LINE = "import 'package:flutter_gen/gen_l10n/app_localizations.dart';"


def _unescape(s: str) -> str:
    """Turn Dart literal escapes into the characters they denote."""
    out, i = [], 0
    while i < len(s):
        c = s[i]
        if c == "\\" and i + 1 < len(s):
            nxt = s[i + 1]
            out.append({"n": "\n", "t": "\t", "'": "'", '"': '"', "\\": "\\"}
                       .get(nxt, nxt))
            i += 2
            continue
        out.append(c)
        i += 1
    return "".join(out)


def _add_import(src: str) -> str:
    if IMPORT_LINE in src:
        return src
    lines = src.split("\n")
    # After the last package: import, so directive ordering stays plausible.
    last = max(
        (i for i, l in enumerate(lines) if l.startswith("import 'package:")),
        default=-1,
    )
    if last == -1:
        last = max(
            (i for i, l in enumerate(lines) if l.startswith("import ")),
            default=-1,
        )
    lines.insert(last + 1, IMPORT_LINE)
    return "\n".join(lines)


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    spec = json.loads(SPEC.read_text(encoding="utf-8"))
    ru = json.loads(RU.read_text(encoding="utf-8"))
    entries = spec["entries"]

    keys = {}
    for e in entries:
        keys.setdefault(e["key"], _unescape(e["en"]))

    missing = sorted(k for k in keys if not ru.get(k))
    if missing:
        raise SystemExit(
            f"{len(missing)} keys have no Russian string; a partly translated "
            f"screen is the bug being fixed. First few: {missing[:8]}"
        )
    extra = sorted(set(ru) - set(keys))
    if extra:
        print(f"note: {len(extra)} unused ru keys: {extra[:5]}")

    # ARB treats braces as placeholder syntax.
    braced = sorted(k for k, v in keys.items() if "{" in v or "}" in v)
    braced += sorted(k for k in keys if "{" in ru[k] or "}" in ru[k])
    if braced:
        raise SystemExit(f"values contain ARB placeholder braces: {braced}")

    by_file: dict[str, list[dict]] = {}
    for e in entries:
        by_file.setdefault(e["file"], []).append(e)

    patched_files = 0
    patched_runs = 0
    skipped: list[str] = []

    for rel, items in sorted(by_file.items()):
        path = MOBILE / rel
        src = path.read_text(encoding="utf-8")
        original = src
        # Longest first so a short literal never eats part of a longer run.
        for e in sorted(items, key=lambda x: -len(x["raw"])):
            if e["raw"] not in src:
                skipped.append(f"{rel}: {e['key']}")
                continue
            src = src.replace(
                e["raw"], f"AppLocalizations.of(context).{e['key']}"
            )
            patched_runs += 1
        if src != original:
            src = _add_import(src)
            patched_files += 1
            if not args.dry_run:
                path.write_text(src, encoding="utf-8")

    # ARB files. Sorted so diffs stay readable.
    if not args.dry_run:
        for name, table in (("app_en.arb", keys), ("app_ru.arb", ru)):
            f = ARB_DIR / name
            current = json.loads(f.read_text(encoding="utf-8"))
            for k in sorted(keys):
                current[k] = table[k]
            f.write_text(
                json.dumps(current, indent=2, ensure_ascii=False) + "\n",
                encoding="utf-8",
            )

    print(f"files patched : {patched_files}")
    print(f"runs replaced : {patched_runs}")
    print(f"keys in ARB   : {len(keys)}")
    if skipped:
        print(f"NOT FOUND in source ({len(skipped)}): {skipped[:6]}")
    if args.dry_run:
        print("(dry run — nothing written)")


if __name__ == "__main__":
    main()
