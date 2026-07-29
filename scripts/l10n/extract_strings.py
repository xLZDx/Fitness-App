"""Extract hardcoded user-facing strings from the Flutter app into an l10n spec.

Why a script: the migration touches 40+ files with the same mechanical edit.
Hand-editing that many call sites is how call sites get missed and how the edits
drift apart from each other.

The load-bearing invariant: the generated English ARB value is the OLD TEXT, byte
for byte. Widget tests render in `en` (test/helpers/test_app.dart pins
`kTestLocale`) and the ARB template is English, so every existing assertion on
English text keeps passing and the migration does not require rewriting the suite.

Adjacent-literal runs are captured WHOLE. Dart concatenates `'a ' 'b'` into
"a b", and this codebase wraps long prose that way constantly. Matching only the
first literal would have translated half a sentence and left the English tail
sitting next to it -- visible, broken UI.

Interpolated runs (containing `$`) are reported but NOT migrated: they need ARB
placeholders, which is a larger and more invasive change.

Usage:
    python scripts/l10n/extract_strings.py            # write spec
    python scripts/l10n/extract_strings.py --report   # counts only
"""
from __future__ import annotations

import argparse
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
LIB = ROOT / "mobile" / "lib"
SPEC = ROOT / "scripts" / "l10n" / "strings_spec.json"

# A single Dart string literal, then a run of adjacent literals.
_SQ = r"'(?:[^'\\\n]|\\.)*'"
_DQ = r'"(?:[^"\\\n]|\\.)*"'
_ONE = f"(?:{_SQ}|{_DQ})"
_RUN = f"{_ONE}(?:\\s*{_ONE})*"

PATTERNS = [
    re.compile(rf"Text\(\s*(?P<run>{_RUN})"),
    re.compile(
        r"(?:label|title|subtitle|hintText|labelText|tooltip|semanticLabel"
        r"|helperText|errorText|message|confirmLabel|cancelLabel)"
        rf"\s*:\s*(?P<run>{_RUN})"
    ),
]

SKIP = re.compile(
    r"^(?:assets/|/|https?://|fitness://|[\w.\-]+\.(?:png|jpg|json|tflite)$)"
)


def _value_of(run: str) -> str:
    """Concatenate an adjacent-literal run into the string Dart would build."""
    parts = re.findall(_ONE, run)
    return "".join(p[1:-1] for p in parts)


def _is_prose(s: str) -> bool:
    if len(s) < 2:
        return False
    if SKIP.match(s):
        return False
    if not re.search(r"[A-Za-z]{2}", s):
        return False
    if re.fullmatch(r"[a-z][a-z0-9_]*", s):
        return False
    return True


def _key_for(file: Path, s: str, used: set[str]) -> str:
    """Stable camelCase key: feature prefix + slug of the string."""
    parts = file.relative_to(LIB).with_suffix("").parts
    prefix = parts[1] if parts[0] in {"features", "core"} else parts[0]
    prefix = re.sub(r"[^a-z0-9]", "", prefix.lower())

    words = re.findall(r"[A-Za-z0-9]+", s)[:6] or ["text"]
    slug = words[0].lower() + "".join(w.capitalize() for w in words[1:])
    key = re.sub(r"[^A-Za-z0-9]", "", f"{prefix}{slug[:1].upper()}{slug[1:]}")

    base, n = key, 2
    while key in used:
        key = f"{base}{n}"
        n += 1
    used.add(key)
    return key


def extract() -> tuple[list[dict], list[dict]]:
    entries: list[dict] = []
    interpolated: list[dict] = []
    used: set[str] = set()
    seen: dict[str, str] = {}

    for f in sorted(LIB.rglob("*.dart")):
        src = f.read_text(encoding="utf-8")
        rel = str(f.relative_to(ROOT / "mobile")).replace("\\", "/")

        runs: list[str] = []
        for p in PATTERNS:
            for m in p.finditer(src):
                run = m.group("run")
                if run not in runs:
                    runs.append(run)

        for run in runs:
            value = _value_of(run)
            if not _is_prose(value):
                continue
            if "$" in value:
                interpolated.append({"file": rel, "en": value})
                continue
            if value in seen:
                entries.append(
                    {"file": rel, "raw": run, "en": value, "key": seen[value],
                     "ru": ""}
                )
                continue
            key = _key_for(f, value, used)
            seen[value] = key
            entries.append(
                {"file": rel, "raw": run, "en": value, "key": key, "ru": ""}
            )
    return entries, interpolated


def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    args = ap.parse_args()

    entries, interpolated = extract()
    keys = {e["key"] for e in entries}
    multi = sum(1 for e in entries if len(re.findall(_ONE, e["raw"])) > 1)
    print(f"migratable      : {len(entries)} runs, {len(keys)} keys")
    print(f"  of those, multi-literal runs: {multi}")
    print(f"interpolated    : {len(interpolated)} (skipped)")
    print(f"files touched   : {len({e['file'] for e in entries})}")
    if args.report:
        return

    existing: dict[str, str] = {}
    if SPEC.exists():
        for e in json.loads(SPEC.read_text(encoding="utf-8"))["entries"]:
            if e.get("ru"):
                existing[e["key"]] = e["ru"]
    for e in entries:
        if not e["ru"] and e["key"] in existing:
            e["ru"] = existing[e["key"]]

    SPEC.write_text(
        json.dumps({"entries": entries, "interpolated": interpolated},
                   indent=2, ensure_ascii=False),
        encoding="utf-8",
    )
    print(f"-> {SPEC}")


if __name__ == "__main__":
    main()
