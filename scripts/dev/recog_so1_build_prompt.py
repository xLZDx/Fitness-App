"""Freeze the SO1 prompt by EXTRACTING production's, not by rewriting it.

The scientific point of SO1 is a second opinion on the same question. If Qwen
were asked a differently-worded question than Gemini, every disagreement would
be confounded with the wording, and the experiment would measure two prompts
rather than two models. So the SO1 prompt is production's `buildPrompt()`
output, byte for byte.

It is EXTRACTED rather than ported: the template literal is lifted out of
`functions/src/ai_equipment_recognition.ts` and the one interpolation it
contains, `${CANONICAL_MACHINES.join(", ")}`, is substituted with the same list
this script reads from the same file. A retyped prompt would be one more copy
free to drift, which is the failure that file's own doc comment already records
happening between the Functions list and the Flutter one.

What the prompt does NOT contain, by construction and by test: any Gemini
answer, any confidence, any ground-truth kind, any arm identity, any
scorer-derived field. It is a fixed constant plus the machine list, exactly as
production's own comment says of itself -- "No input is interpolated".
"""

from __future__ import annotations

import argparse
import hashlib
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
RECOGNITION_TS = REPO / "functions" / "src" / "ai_equipment_recognition.ts"
OUT = REPO / "scripts" / "dev" / "recog_so1_prompt.txt"

INTERPOLATION = "${CANONICAL_MACHINES.join(\", \")}"


def read_canonical_machines(src: str) -> list[str]:
    marker = "export const CANONICAL_MACHINES: readonly string[] = ["
    start = src.index(marker) + len(marker)
    end = src.index("] as const;", start)
    return re.findall(r'"([^"]+)"', src[start:end])


def extract_prompt(src: str) -> str:
    """Lift the template literal out of `buildPrompt()` and fill its one hole.

    Anchored on the function itself rather than on "the first backtick in the
    file", so an unrelated template literal added above it cannot silently
    become the prompt this experiment freezes.
    """
    fn = src.index("function buildPrompt(): string {")
    open_tick = src.index("`", fn)
    close_tick = src.index("`", open_tick + 1)
    template = src[open_tick + 1 : close_tick]
    if INTERPOLATION not in template:
        raise SystemExit(
            "buildPrompt()'s template no longer ends with the CANONICAL_MACHINES interpolation; "
            "production changed shape and this extractor must be re-read before it is trusted"
        )
    if template.count("${") != 1:
        raise SystemExit(
            f"buildPrompt()'s template has {template.count('${')} interpolations, expected exactly 1 -- "
            "something other than the machine list is now being substituted into the prompt"
        )
    machines = read_canonical_machines(src)
    return template.replace(INTERPOLATION, ", ".join(machines))


FORBIDDEN = [
    # Nothing that could carry the first model's opinion, the answer, or which
    # arm this is may appear in the frozen prompt. Checked here as well as in
    # the test suite, because the cheapest place to catch it is at the moment
    # it would be written to disk.
    "gemini", "ground truth", "gt_kind", "canonical_single", "multiple",
    "arm a", "arm b", "arm_a", "arm_b", "crop", "full frame",
]


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true", help="write scripts/dev/recog_so1_prompt.txt")
    ap.add_argument("--check", action="store_true", help="re-extract and fail if the file on disk differs")
    args = ap.parse_args(argv)

    src = RECOGNITION_TS.read_text("utf-8")
    prompt = extract_prompt(src)

    lowered = prompt.lower()
    leaked = [token for token in FORBIDDEN if token in lowered]
    if leaked:
        raise SystemExit(f"the extracted prompt contains blinding-breaking tokens: {leaked}")

    print(f"{len(prompt)} characters, {len(prompt.splitlines())} lines")
    print(f"offers the sentinel 'unknown': {'unknown' in lowered}")

    if args.check:
        if not OUT.is_file():
            print(f"{OUT.relative_to(REPO)} does not exist")
            return 1
        if OUT.read_text("utf-8") != prompt:
            print(f"{OUT.relative_to(REPO)} DIFFERS from production's current prompt")
            return 1
        print(f"{OUT.relative_to(REPO)} matches production's prompt exactly")
        return 0

    if args.write:
        OUT.write_text(prompt, encoding="utf-8", newline="")
        print(f"wrote {OUT.relative_to(REPO)}  sha256 {hashlib.sha256(OUT.read_bytes()).hexdigest()}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
