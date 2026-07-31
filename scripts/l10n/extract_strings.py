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
        r"|helperText|errorText|message|confirmLabel|cancelLabel|body"
        # Added 2026-07-31, after a sweep found 190 user-facing strings the
        # two patterns above had never seen. Every name here was carrying real
        # interface text on the donation page, the profile page or a step of
        # the onboarding questionnaire.
        r"|hint|price|tagline|caption|placeholder|heading|prompt|description)"
        rf"\s*:\s*(?P<run>{_RUN})"
    ),
    # A positional argument to a small labelled widget: `FieldLabel('Age')`,
    # `_SectionHeader('Today')`. The onboarding questionnaire is built almost
    # entirely out of these, which is why 97 of its strings survived the first
    # migration untouched.
    re.compile(rf"\b(?:FieldLabel|StepTitle|_SectionHeader|SectionHeader)"
               rf"\(\s*(?P<run>{_RUN})\s*[,)]"),
    # A switch arm returning a literal, which is how every enum in this app
    # gets a display name: `Gender.female => 'Female'`, `case X: return 'Y';`.
    re.compile(rf"=>\s*(?P<run>{_RUN})\s*,"),
    re.compile(rf"\breturn\s+(?P<run>{_RUN});"),
]

# Shapes the extractor can SEE but must not rewrite in place, because the
# result would not compile. It reports them; a human restructures them.
#
#   static const _titles = ['Personal', ...]   a const list cannot hold a call
#   String _label(Gender g) => switch (g)      a top-level function has no
#                                              context to read a lookup from
#
# Both of those really occurred, and both needed the surrounding code changed
# rather than the literal swapped. See `scripts/l10n/onboarding_l10n.py`.
NEEDS_RESTRUCTURING = re.compile(r"static\s+const\s+\w+\s*=\s*[\[{]")


def _without_comments(src: str) -> str:
    """Blank out comment bodies, keeping line count and offsets intact.

    A doc comment quoting the interface -- `/// A label: "Today 07:00"` -- is
    documentation ABOUT a string, not a string. Reporting it sends someone to
    translate a sentence no user will ever see, and the previous run did
    exactly that.
    """
    return "\n".join(
        "" if line.lstrip().startswith("//") else line
        for line in src.splitlines()
    )


def _builds_material_app(src: str) -> bool:
    """Whether this file constructs the MaterialApp itself.

    Such a widget sits ABOVE the Localizations ancestor it installs, so
    `AppLocalizations.of(context)` there returns null and the non-nullable getter
    throws on the very first frame -- the app does not boot.

    This guard exists because the pipeline made that exact mistake twice: it
    rewrote `title: 'Fitness App'` in `main.dart`, directly beneath the comment
    forbidding it. The first time it was reverted by hand but the Russian string
    was left in `ru.json`, so the next run silently reapplied it. A structural
    rule is the only thing that stops a third time.
    """
    return "MaterialApp" in src


def _has_context(src: str) -> bool:
    """Whether `AppLocalizations.of(context)` could compile in this file.

    Decided by looking for `BuildContext` in the source rather than by guessing
    from the directory name. A path rule (`/data/`, `/state/`) missed
    `core/notifications/mock_notification_service.dart`, which builds
    notification text in a plain class and was rewritten into code referencing
    an undefined `context`.

    Files that fail this check are reported, not migrated: their user-visible
    text needs a per-site design -- an enum resolved in the widget layer, or a
    language-aware constructor like AssetEquipmentRepository's.
    """
    return "BuildContext" in src

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


def _interpolation(value: str) -> tuple[str, list[str]] | None:
    """Split `'Could not load: $e'` into `('Could not load: {arg0}', ['e'])`.

    Returns None when the interpolation cannot be migrated safely:

    * an expression containing a quote or a brace we cannot balance -- the
      single-line literal regex has already mangled those, so anything reaching
      here with unbalanced braces is not trustworthy;
    * a literal that already contains `{` or `}`, because ARB reads braces as
      placeholder syntax and would misparse the result.

    Callers treat None as "report it, do not touch it".
    """
    out: list[str] = []
    exprs: list[str] = []
    i = 0
    while i < len(value):
        ch = value[i]
        if ch in "{}":
            return None  # would collide with ARB placeholder syntax
        if ch != "$":
            out.append(ch)
            i += 1
            continue
        i += 1
        if i >= len(value):
            return None
        if value[i] == "{":
            depth, j = 1, i + 1
            while j < len(value) and depth:
                if value[j] == "{":
                    depth += 1
                elif value[j] == "}":
                    depth -= 1
                elif value[j] in "'\"":
                    return None  # a nested literal; the run regex cannot be trusted
                j += 1
            if depth:
                return None
            expr = value[i + 1 : j - 1].strip()
            i = j
        else:
            m = re.match(r"[A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)*", value[i:])
            if not m:
                return None
            expr = m.group(0)
            i += len(expr)
        if not expr:
            return None
        out.append(f"{{arg{len(exprs)}}}")
        exprs.append(expr)
    return "".join(out), exprs


def _key_for(file: Path, s: str, used: set[str]) -> str:
    """Stable camelCase key: feature prefix + slug of the string."""
    parts = file.relative_to(LIB).with_suffix("").parts
    prefix = parts[1] if parts[0] in {"features", "core"} else parts[0]
    prefix = re.sub(r"[^a-z0-9]", "", prefix.lower())

    # Slug from the text only: placeholder names carry no meaning and would
    # make keys like `equipmentCouldNotLoadArg0`.
    s = re.sub(r"\{arg\d+\}", " ", s)
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
        src = _without_comments(f.read_text(encoding="utf-8"))
        rel = str(f.relative_to(ROOT / "mobile")).replace("\\", "/")

        runs: list[str] = []
        for p in PATTERNS:
            for m in p.finditer(src):
                run = m.group("run")
                if run not in runs:
                    runs.append(run)

        for run in runs:
            value = _value_of(run)

            # Split interpolations BEFORE deciding whether this is prose. Testing
            # the raw literal instead would read the Dart expression as text:
            # `'${line.percent}%'` looks like prose because "line" is a word,
            # and the migration would mint an ARB key whose entire English value
            # is `{arg0}%` -- a lookup with nothing to translate.
            args: list[str] = []
            if "$" in value:
                split = _interpolation(value)
                if split is None:
                    interpolated.append({"file": rel, "en": value})
                    continue
                value, args = split

            if not _is_prose(re.sub(r"\{arg\d+\}", "", value)):
                continue
            if not _has_context(src) or _builds_material_app(src):
                interpolated.append({"file": rel, "en": value})
                continue

            # Two sites can share a template but pass different expressions, so
            # the key is keyed on the template and the args ride on the entry.
            key = seen.get(value)
            if key is None:
                key = _key_for(f, value, used)
                seen[value] = key
            entries.append({
                "file": rel, "raw": run, "en": value, "key": key, "ru": "",
                "args": args,
            })
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
