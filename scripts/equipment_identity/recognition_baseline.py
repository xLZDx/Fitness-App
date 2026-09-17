# -*- coding: utf-8 -*-
"""P0.G1 — freeze exactly what current generic recognition does before exact
identity can touch it.

    python scripts/equipment_identity/recognition_baseline.py --write
    python scripts/equipment_identity/recognition_baseline.py --check     # CI
    python -m pytest scripts/equipment_identity/test_baseline.py -q

Per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G1: this generator DERIVES the baseline from real source, it does not
hand-type a description of what the pipeline is supposed to do. Every fact
below is either a file hash (this file existed, unmodified, at this SHA) or a
structural assertion extracted from that file's actual text (this branch
order/enum/guard exists in the source, not in a comment about the source).

Mirrors `scripts/ml/dataset_registry.py`'s `--write`/`--check` shape so a
reader who already knows that generator recognises this one.

Named `recognition_baseline.py`, not `baseline.py` — this repository's
per-directory `scripts/` layout has no package `__init__.py` files, so a
bare module name is global across every `scripts/*/` tree once two of them
insert themselves onto `sys.path`. `scripts/ct1/baseline.py` already owns
the generic name; a same-named module here silently shadowed it in
`sys.modules` and broke `scripts/ct1/review_batch.py`'s
`from baseline import ...` the moment both test suites ran in the same
pytest session (caught during P0.G2 work, fixed same-day as P0.G1).
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))
from canonical_json import dump_pretty, file_sha256, payload_sha256, sort_by_key  # noqa: E402

REPO = Path(__file__).resolve().parents[2]
MOBILE = REPO / "mobile"
OUT = REPO / "core" / "equipment_identity" / "p0" / "recognition_baseline_v1.json"
OUT_LEGACY_INVENTORY = (
    REPO / "core" / "equipment_identity" / "p0" / "legacy_real_gym_regression_inventory.json"
)

SCHEMA_VERSION = 1
LEGACY_INVENTORY_SCHEMA_VERSION = 1

FUNCTIONAL_CATALOG = MOBILE / "assets" / "data" / "equipment.json"
MODEL_REGISTRY = REPO / "core" / "ml" / "MODEL_REGISTRY.json"
TFLITE_MODEL = MOBILE / "assets" / "models" / "equipment_v1.tflite"

VISUAL_EQUIPMENT = MOBILE / "lib" / "features" / "visual_equipment"

#: The B1 measurement note is the only recorded evidence of the operator's
#: 30-photo real-gym set — this baseline binds the legacy inventory to that
#: note's text, never to the raw photo directory it names (which this
#: checkout does not have; see `_raw_photo_dir_status`).
B1_MEASUREMENT_NOTE = REPO / "core" / "plans" / "B1_RECOGNITION_MEASUREMENT_2026-08-07.md"

#: Recorded verbatim in B1_MEASUREMENT_NOTE's own text — this generator does
#: not re-derive it, since the raw directory is confirmed absent from this
#: checkout (see `_raw_photo_dir_status`) and there is nothing else to derive
#: it from.
RAW_PHOTO_DIR_AS_RECORDED = r"D:\Downloads\Photos-1-001 (1)"

#: The 4 individually-labeled frames from B1's table (model call, ground
#: truth, confidence) — hand-transcribed from B1_MEASUREMENT_NOTE because the
#: note is prose+table, not structured data this generator can parse
#: reliably; cross-checked against the note's text by `_verify_legacy_frames`
#: before being trusted.
LEGACY_LABELED_FRAMES: tuple[dict[str, Any], ...] = (
    {
        "frameId": "20260730_135634",
        "groundTruth": "Precor Inspiration abduction/adduction (leg ab/adduction machine)",
        "modelPrediction": "treadmill",
        "modelConfidence": 0.892,
    },
    {
        "frameId": "20260806_140007",
        "groundTruth": "Nautilus Inspiration shoulder press",
        "modelPrediction": "leg_press",
        "modelConfidence": 0.897,
    },
    {
        "frameId": "20260730_141736",
        "groundTruth": "Precor Inspiration abdominal machine",
        "modelPrediction": "treadmill",
        "modelConfidence": 0.742,
    },
    {
        "frameId": "Screenshot_20260806_140916",
        "groundTruth": "leg extension machine",
        "modelPrediction": "treadmill",
        "modelConfidence": 0.23,
    },
)

#: A literal substring of B1_MEASUREMENT_NOTE's own text for each frame's
#: ground truth — NOT part of the committed JSON payload (LEGACY_LABELED_FRAMES's
#: `groundTruth` field is an English gloss, not a literal quote, so it cannot
#: itself be cross-checked against the Russian/mixed source table). This is
#: what `_verify_legacy_frames` actually matches against, so a mistranscribed
#: ground truth or confidence fails loudly instead of only checking frameId
#: and modelPrediction (a gap an internal review caught).
LEGACY_FRAME_GROUND_TRUTH_ANCHORS: dict[str, str] = {
    "20260730_135634": "ABDUCTION/ADDUCTION",
    "20260806_140007": "SHOULDER",
    "20260730_141736": "ABDOMINAL",
    "Screenshot_20260806_140916": "разгибание ног",
}

#: (repo-relative path, role). One row per file this baseline treats as part
#: of "current generic recognition" — discovered by reading the pipeline
#: (text anchor -> hybrid cloud/on-device classifier -> describer fallback),
#: not by a directory listing, so a role always names what the file DOES.
SCANNER_CONTRACTS: tuple[tuple[str, str], ...] = (
    (
        "mobile/lib/features/visual_equipment/data/machine_text_anchor.dart",
        "TEXT_ANCHOR_MATCHING — pure string matching from OCR text to a "
        "catalogue id; runs first, silent unless exactly one machine is named",
    ),
    (
        "mobile/lib/features/visual_equipment/data/mlkit_text_recogniser.dart",
        "TEXT_ANCHOR_OCR_BRIDGE — ML Kit text recognition, feeds the matcher above",
    ),
    (
        "mobile/lib/features/visual_equipment/data/scan_outcome.dart",
        "OUTCOME_CONTRACT — ScanOutcome enum and ScanResult, the settled shape "
        "every recognition attempt ends in",
    ),
    (
        "mobile/lib/features/visual_equipment/data/visual_equipment_match.dart",
        "MATCH_CONTRACT — VisualMatch/MatchSource, one ranked candidate and "
        "where it came from",
    ),
    (
        "mobile/lib/features/visual_equipment/data/visual_equipment_service.dart",
        "SERVICE_INTERFACE — VisualEquipmentService/FallbackReportingRecogniser "
        "abstractions the classifier implementations satisfy",
    ),
    (
        "mobile/lib/features/visual_equipment/data/gemini_equipment_service.dart",
        "CLOUD_CLASSIFIER_AND_HYBRID — GeminiVisualEquipmentService (primary) "
        "and HybridVisualEquipmentService (cloud-first, on-device-fallback "
        "orchestration)",
    ),
    (
        "mobile/lib/features/visual_equipment/data/mlkit_visual_equipment_service.dart",
        "ONDEVICE_TFLITE_CLASSIFIER — bundled equipment_v1.tflite, offline fallback",
    ),
    (
        "mobile/lib/features/visual_equipment/data/mlkit_live_equipment_service.dart",
        "LIVE_VIEWFINDER_RECOGNITION — continuous scan-tab recognition, same "
        "text-anchor-first ordering as the single-photo path",
    ),
    (
        "mobile/lib/features/visual_equipment/state/visual_equipment_providers.dart",
        "ORCHESTRATION_CONTROLLER — VisualEquipmentController.classifyFilePath, "
        "wires text anchor -> hybrid classifier -> describer in one call",
    ),
    (
        "mobile/lib/features/visual_equipment/data/machine_describer.dart",
        "DESCRIBER_FALLBACK — names a machine that matched nothing in the "
        "catalogue; distinguishes ScanOutcome.unknown from .noEquipment",
    ),
)

#: Tokens swept to record whether exact-identity vocabulary exists in the
#: scanner/equipment source. Originally a hard "must be absent" gate — v4.4's
#: own vocabulary for the feature this baseline exists to precede. Retired as
#: a gate 2026-09-17 (core/DECISION_LOG.md, same date;
#: scripts/equipment_identity/test_baseline.py's
#: test_exact_identity_concepts_were_absent_at_p0_g1s_close): P2.G4/
#: P2.G5-readiness (2026-09-16, already reviewed and merged) is the
#: authorized exact-identity work P0.G1 existed to precede, and it now
#: legitimately uses several of these tokens. The sweep still runs and is
#: still recorded in the baseline payload — it is now an informational
#: field about what exists, not an assertion about what must not.
EXACT_IDENTITY_TOKENS = (
    "identityLevel",
    "EXACT_MODEL",
    "RecognitionAuthorityTuple",
    "evidenceLane",
    "recognitionSessionId",
    "EquipmentIdentityResponse",
)

#: Trees swept for EXACT_IDENTITY_TOKENS. `equipment/` (the workout-player
#: side, `ExerciseItem.equipmentId` etc.) is included because P0.G1 must also
#: witness that exact identity has not silently leaked into the *consuming*
#: side of the app, not only the scanner that would produce it.
SWEPT_TREES: tuple[Path, ...] = (
    VISUAL_EQUIPMENT,
    MOBILE / "lib" / "features" / "equipment",
)


class BaselineError(RuntimeError):
    """A source assertion this baseline depends on no longer holds."""


def _git_commit() -> str:
    try:
        return subprocess.run(
            ["git", "-C", str(REPO), "rev-parse", "HEAD"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except Exception:
        return "UNKNOWN"


def _read(path: Path) -> str:
    return path.read_text(encoding="utf-8")


# ---------------------------------------------------------------------------
# Lexical position: which characters of a Dart source are executable code.
#
# Every structural assertion below used to ask `token in text` or
# `text.find(token)` over the RAW file. That cannot tell a call from a
# comment mentioning the call, and it is the defect that made this whole
# module's suite red: a comment added to `mlkit_live_equipment_service.dart`
# reading "see gemini_equipment_service.dart's matching comment" tripped a
# guard whose subject is whether the LIVE PATH CALLS A CLOUD CLASSIFIER.
# This module's own header already forbade that reading -- a fact must come
# from "the source, not ... a comment about the source" -- so the check was
# stale against its own contract, not the source against the check.
#
# Four classes, not two. GPT-PM refused a code-vs-comment split with a
# counterexample this repository could not have answered:
#
#     debugPrint('${"_anchorOnPrintedText("}');
#     await service.classifyFile(path);
#     await _anchorOnPrintedText(path);
#
# The real call order is REVERSED, and a lexer that treats a string as code
# -- or that paints a whole `${...}` span CODE without lexing inside it --
# reads the mention as the call and certifies the wrong order. So string
# content is its own class, ordering checks consume CODE only, and
# interpolation is a recursive state transition rather than a span.
#
# FAILS CLOSED, deliberately and in one direction: an unterminated string,
# block comment or interpolation raises rather than returning a partial
# classification. Over-classifying as STRING/comment HIDES a real code
# occurrence, and no caller-level test can distinguish that from a file
# that is genuinely clean -- which is why `test_baseline.py` tests this
# function directly rather than only through its callers.
# ---------------------------------------------------------------------------

CODE = "CODE"
STRING = "STRING"
LINE_COMMENT = "LINE_COMMENT"
BLOCK_COMMENT = "BLOCK_COMMENT"

#: Everything that is not executable. Named so a caller reads as a claim.
NON_EXECUTABLE = frozenset({STRING, LINE_COMMENT, BLOCK_COMMENT})
#: A concept reference: code, or a string naming it. Comments excluded.
CODE_OR_STRING = frozenset({CODE, STRING})
#: Executable structure only.
CODE_ONLY = frozenset({CODE})

_IDENT_START = set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ_")
_IDENT_BODY = _IDENT_START | set("0123456789")


def classify_dart_source(text: str) -> list[str]:
    """Classify every character of a Dart source as CODE, STRING,
    LINE_COMMENT or BLOCK_COMMENT.

    The four classes partition the input: the returned list has exactly one
    entry per character, and `test_baseline.py` asserts that no character is
    left unclassified.

    Modelled, because each of these silently changes the answer:

    - Dart block comments NEST (`/* /* */ */` is ONE comment).
    - A `//` inside a string literal is not a comment; an apostrophe inside
      a comment does not open a string.
    - `${...}` is an expression context that can itself contain strings,
      raw strings, comments and further interpolation, and it ends at the
      MATCHING brace, not the first one.
    - `$identifier` is an expression too, so the identifier is CODE.
    - A raw string (`r'...'`) never interpolates and never honours escapes,
      so `r'${f()}'` is STRING end to end.

    Raises BaselineError on anything it cannot model to the end -- an
    unterminated string, block comment or interpolation. That is the safe
    direction: the failure mode worth preventing is a caller being told a
    real code occurrence is only a comment.
    """
    n = len(text)
    classes: list[str | None] = [None] * n

    def mark(start: int, end: int, kind: str) -> None:
        for k in range(start, min(end, n)):
            classes[k] = kind

    # A frame is either an interpolation-aware code context or a string.
    #   ["code", depth]   depth None at top level, else open-brace count
    #   ["string", quote, triple, raw]
    stack: list[list] = []
    frame: list = ["code", None]
    i = 0

    while i < n:
        if frame[0] == "code":
            ch = text[i]

            if ch == "/" and text.startswith("//", i):
                end = text.find("\n", i)
                end = n if end == -1 else end
                mark(i, end, LINE_COMMENT)
                i = end
                continue

            if ch == "/" and text.startswith("/*", i):
                depth = 0
                j = i
                while j < n:
                    if text.startswith("/*", j):
                        depth += 1
                        j += 2
                    elif text.startswith("*/", j):
                        depth -= 1
                        j += 2
                        if depth == 0:
                            break
                    else:
                        j += 1
                if depth != 0:
                    raise BaselineError(
                        f"unterminated block comment opened at offset {i} -- refusing to "
                        "classify a source this function cannot model to the end"
                    )
                mark(i, j, BLOCK_COMMENT)
                i = j
                continue

            raw = ch == "r" and i + 1 < n and text[i + 1] in "\"'"
            quote_at = i + 1 if raw else i
            if quote_at < n and text[quote_at] in "\"'":
                quote = text[quote_at]
                triple = text[quote_at:quote_at + 3] == quote * 3
                qlen = 3 if triple else 1
                mark(i, quote_at + qlen, STRING)
                stack.append(frame)
                frame = ["string", quote, triple, raw]
                i = quote_at + qlen
                continue

            if frame[1] is not None:
                if ch == "{":
                    frame[1] += 1
                elif ch == "}":
                    if frame[1] == 0:
                        # Closes the interpolation: the brace belongs to the
                        # literal, and the enclosing string resumes.
                        mark(i, i + 1, STRING)
                        frame = stack.pop()
                        i += 1
                        continue
                    frame[1] -= 1

            mark(i, i + 1, CODE)
            i += 1
            continue

        # frame[0] == "string"
        _, quote, triple, raw = frame
        closer = quote * (3 if triple else 1)

        if not raw and text[i] == "\\":
            mark(i, i + 2, STRING)
            i += 2
            continue

        if text.startswith(closer, i):
            mark(i, i + len(closer), STRING)
            frame = stack.pop()
            i += len(closer)
            continue

        if not raw and text[i] == "$":
            if i + 1 < n and text[i + 1] == "{":
                mark(i, i + 2, STRING)
                stack.append(frame)
                frame = ["code", 0]
                i += 2
                continue
            if i + 1 < n and text[i + 1] in _IDENT_START:
                mark(i, i + 1, STRING)
                j = i + 1
                while j < n and text[j] in _IDENT_BODY:
                    j += 1
                mark(i + 1, j, CODE)
                i = j
                continue

        if not triple and text[i] == "\n":
            raise BaselineError(
                f"newline inside a single-line string opened before offset {i} -- "
                "refusing to classify a source this function cannot model to the end"
            )

        mark(i, i + 1, STRING)
        i += 1

    if stack or frame[0] != "code" or frame[1] is not None:
        raise BaselineError(
            "source ended inside a string or an interpolation -- refusing to "
            "classify a source this function cannot model to the end"
        )
    if any(c is None for c in classes):
        raise BaselineError(
            "internal: classify_dart_source left a character unclassified"
        )
    return classes  # type: ignore[return-value]


def find_in(text: str, token: str, allowed: frozenset[str]) -> list[int]:
    """Offsets where `token` occurs with EVERY one of its characters in one
    of the `allowed` lexical classes.

    Every character, not just the first: a token straddling a boundary
    belongs to neither side cleanly, and letting the first character decide
    would let `"gemin` + `i` style splits through.
    """
    classes = classify_dart_source(text)
    hits: list[int] = []
    start = text.find(token)
    while start != -1:
        if all(classes[k] in allowed for k in range(start, start + len(token))):
            hits.append(start)
        start = text.find(token, start + 1)
    return hits


def first_in_code(text: str, token: str) -> int:
    """Offset of the first executable occurrence of `token`, or -1.

    The ordering checks below use this instead of `str.find`, which is what
    made a printed mention of a call indistinguishable from the call.
    """
    hits = find_in(text, token, CODE_ONLY)
    return hits[0] if hits else -1


def _index_of(
    text: str, token: str, classes: list[str], allowed: frozenset[str], start: int = 0
) -> int:
    """First offset at or after `start` where `token` occurs and its FIRST
    character is classified into `allowed`; -1 when there is none.

    Takes a classification rather than computing one, so a caller that needs
    several searches over the same file lexes it once and every search agrees
    about what that file is.
    """
    index = text.find(token, start)
    while index != -1:
        if classes[index] in allowed:
            return index
        index = text.find(token, index + 1)
    return -1


def _matching_close(
    text: str, open_index: int, open_ch: str, close_ch: str, classes: list[str] | None = None
) -> int:
    """Index of the `close_ch` that balances `open_ch` at `open_index`,
    counting only that one bracket pair (a Dart named-parameter block's
    `{`/`}` does not perturb a `(`/`)` search, and vice versa).

    Brackets are counted in CODE only. A brace inside a string literal or a
    comment is a character, not a block boundary -- counting it raw would end
    a block early or run past its end, which is this gate's own defect
    committed by the function that decides where to APPLY the lexer.
    """
    if classes is None:
        classes = classify_dart_source(text)
    depth = 0
    for i in range(open_index, len(text)):
        if classes[i] != CODE:
            continue
        if text[i] == open_ch:
            depth += 1
        elif text[i] == close_ch:
            depth -= 1
            if depth == 0:
                return i
    raise BaselineError(f"unbalanced {open_ch!r}/{close_ch!r} from index {open_index}")


def _block_bounds(text: str, marker: str) -> tuple[int, int]:
    """Shared bracket work for `_extract_block` and `_extract_block_span`, so
    the span and the body can never disagree about where a block is.

    The marker is located in CODE, and the brackets are counted in CODE. This
    was a raw `text.find` until round 4, which made the whole lexer beside the
    point at the one step that chooses what to lex. Measured on that version:
    a doc-comment quoting `if (answeredOffline) {` above the real guard moved
    the extracted body from line 6 to line 1, and what came back was the
    commented code -- a fact taken from a comment about the source, which is
    exactly what this module's header says must never happen.
    """
    classes = classify_dart_source(text)
    start = _index_of(text, marker, classes, CODE_ONLY)
    if start == -1:
        raise BaselineError(f"marker not found in code (only in prose, if at all): {marker!r}")

    if marker.endswith("{"):
        brace_open = start + len(marker) - 1
    elif marker.endswith("("):
        paren_open = start + len(marker) - 1
        paren_close = _matching_close(text, paren_open, "(", ")", classes)
        brace_open = _index_of(text, "{", classes, CODE_ONLY, paren_close)
        if brace_open == -1:
            raise BaselineError(f"no body brace found in code after parameter list: {marker!r}")
    else:
        raise BaselineError(f"marker must end with '{{' or '(': {marker!r}")

    brace_close = _matching_close(text, brace_open, "{", "}", classes)
    return brace_open + 1, brace_close


def _extract_block_span(text: str, marker: str) -> tuple[int, int]:
    """`(start, end)` offsets of the body `_extract_block` would return.

    Callers that need LEXICAL classification take the span and classify the
    whole file, rather than lexing the extracted fragment: a fragment can
    begin inside a string or comment whose opening it does not contain, and
    `classify_dart_source` fails closed on exactly that, which would turn a
    correct check into an unexplained error.
    """
    return _block_bounds(text, marker)


def _extract_block(text: str, marker: str) -> str:
    """The body of the `{ ... }` block this `marker` introduces, using real
    balanced-bracket counting rather than a regex terminator (a regex like
    `\\n  \\}` breaks the moment the construct contains an earlier
    same-indent `}` — e.g. a named-parameter list closing with `}) {`
    before the method body even starts, which is exactly the shape this
    codebase's Dart uses throughout).

    Two marker shapes are supported:
    - Marker ends with `{` (`"if (x) {"`, `"enum Y {"`) — that trailing
      brace IS the block's opening brace.
    - Marker ends with `(` (a method signature's parameter list opener,
      `"Future<T> f("`) — the parameter list is skipped via balanced PAREN
      counting first (so a named-parameter `{...}` inside it is never
      mistaken for the method body), then the body's own `{` is the next
      one found after that parameter list closes.
    """
    start, end = _block_bounds(text, marker)
    return text[start:end]


def _in_span(hits: list[int], span: tuple[int, int]) -> list[int]:
    """The offsets of `hits` that fall inside `span`."""
    start, end = span
    return [h for h in hits if start <= h < end]


# ---------------------------------------------------------------------------
# Structural assertions over real source text. Each returns a small dict of
# derived facts; each raises BaselineError with the exact reason if the
# source no longer matches what this baseline claims about it, rather than
# silently recording a stale claim.
# ---------------------------------------------------------------------------

def _scan_outcome_states() -> list[str]:
    # Routed through `_extract_block`'s real balanced-brace counter rather
    # than a `\n\}`-terminated regex — the latter is the exact unsafe
    # construct this module's own `_extract_block` docstring warns about (it
    # breaks on an earlier same-indent `}`, e.g. inside a doc comment).
    text = _read(VISUAL_EQUIPMENT / "data" / "scan_outcome.dart")
    body = _extract_block(text, "enum ScanOutcome {")
    states = re.findall(r"^\s*([a-zA-Z][a-zA-Z0-9]*)\s*,?\s*(?://.*)?$", body, re.M)
    states = [s for s in states if s]
    if not states:
        raise BaselineError("scan_outcome.dart: could not parse any ScanOutcome states")
    return states


def _offline_never_confident() -> bool:
    """An offline (on-device) answer must never resolve to `.confident` —
    the guardrail that keeps a weaker answer from ever being reported as the
    settled identification `isWorthRemembering` (and, later, any
    exact-identity gate) treats as trustworthy.

    Two shapes satisfy this, and both are checked for rather than assuming
    only the older one:

    1. `ScanResult.confident` is unreachable from `fromMatches` at all (in
       CODE) — the strongest form of the invariant, since neither an online
       nor an offline answer from this factory can ever be `.confident`.
       FITAPP-EQUIP-ACC-2026-09-17 (commit a0e842a, GPT-PM-approved decision
       C) moved the codebase to exactly this shape: every match list, cloud
       or on-device, now settles as `.alternatives`. There is no
       `answeredOffline` branch left to find, because there is no
       `.confident` return left to guard.
    2. `ScanResult.confident` IS reachable from `fromMatches` (e.g. an
       online-only confident path exists again in a future change) — in
       which case an `if (answeredOffline) {` guard must exist, and inside
       it the factory must still downgrade to `.alternatives` and must not
       also return `.confident`. This is the shape the original version of
       this check enforced, kept for the case a future change reintroduces
       a confident branch without reintroducing the guard.

    Scoped to the single-photo path (`ScanResult.fromMatches`) only — see
    `_live_mode_has_no_offline_downgrade_guard` for the live-viewfinder path,
    which has no equivalent guard at all and is recorded as its own,
    separately-named fact rather than folded into this one (an internal
    review, `fitness-flutter-reviewer` substitute, flagged the two paths
    being described under one unscoped name as misleading)."""
    text = _read(VISUAL_EQUIPMENT / "data" / "scan_outcome.dart")
    factory_span = _extract_block_span(text, "factory ScanResult.fromMatches(")
    # CODE only throughout: a guard/return is executable structure, so a
    # printed or commented mention of `ScanResult.confident` must neither
    # satisfy a positive check nor trip a negative one.
    confident_in_factory = _in_span(
        find_in(text, "ScanResult.confident", CODE_ONLY), factory_span
    )
    if not confident_in_factory:
        # Shape 1: .confident is entirely unreachable from this factory, so
        # there is nothing an answeredOffline guard would even need to
        # downgrade.
        return True

    # Shape 2: .confident is reachable from this factory, so the
    # answeredOffline guard must exist and must still downgrade it.
    if not _in_span(find_in(text, "if (answeredOffline) {", CODE_ONLY), factory_span):
        raise BaselineError(
            "scan_outcome.dart: fromMatches can return ScanResult.confident "
            "but no longer special-cases answeredOffline — the "
            "offline-never-confident invariant may have been removed"
        )
    guard_span = _extract_block_span(text, "if (answeredOffline) {")
    if not _in_span(find_in(text, "ScanResult.alternatives", CODE_ONLY), guard_span):
        raise BaselineError(
            "scan_outcome.dart: the answeredOffline guard no longer returns "
            "ScanResult.alternatives"
        )
    if _in_span(find_in(text, "ScanResult.confident", CODE_ONLY), guard_span):
        raise BaselineError(
            "scan_outcome.dart: the answeredOffline guard now also mentions "
            "ScanResult.confident — offline results may have stopped being "
            "downgraded"
        )
    return True


def _live_mode_has_no_offline_downgrade_guard() -> dict[str, Any]:
    """The live-viewfinder path (`MlKitLiveEquipmentService` /
    `RecognitionSmoother`) is on-device only — it never calls a cloud
    classifier — and its `settled` reading (the functional analogue of
    `ScanOutcome.confident`: `scanner_page.dart`'s `ref.listen` writes a
    settled live reading straight into recognition history the same way a
    confident photo result is remembered) has no `answeredOffline`-style
    branch that downgrades it. This is recorded as its own fact, not folded
    into `offlineFallbackNeverReportsConfident`, because the two paths behave
    differently: the photo path CAN run on-device and gets downgraded when it
    does; the live path is ALWAYS on-device and is never downgraded for it."""
    live_service_text = _read(VISUAL_EQUIPMENT / "data" / "mlkit_live_equipment_service.dart")
    lowered = live_service_text.lower()
    # CODE **or STRING**, deliberately wider than the ordering checks below:
    # a string naming a cloud endpoint is a real concept reference, so the
    # conservative reading applies here. Only comments are excluded, and they
    # are excluded because this module's own header forbids taking a fact
    # from "a comment about the source" — which is exactly what the previous
    # raw-substring version did, turning a cross-reference comment naming
    # `gemini_equipment_service.dart` into a false cloud-coupling report.
    executable_hits = (
        find_in(lowered, "gemini", CODE_OR_STRING)
        + find_in(lowered, "cloud", CODE_OR_STRING)
    )
    if executable_hits:
        raise BaselineError(
            "mlkit_live_equipment_service.dart: now references a cloud/Gemini "
            "concept — the live path may no longer be on-device-only, so the "
            "no-offline-downgrade-guard fact needs re-deriving, not assuming"
        )
    # Comment-only mentions pass, but are RECORDED rather than dropped: the
    # count is part of the payload, so a new mention still changes the
    # baseline and forces a deliberate regeneration. "Needs re-deriving, not
    # assuming" survives; it just stops firing on prose.
    commented_mentions = len(
        find_in(lowered, "gemini", NON_EXECUTABLE)
        + find_in(lowered, "cloud", NON_EXECUTABLE)
    )

    smoother_text = _read(VISUAL_EQUIPMENT / "data" / "live_recognition.dart")
    add_span = _extract_block_span(smoother_text, "LiveRecognition? add(VisualMatch? top) {")
    if _in_span(find_in(smoother_text.lower(), "offline", CODE_ONLY), add_span):
        raise BaselineError(
            "live_recognition.dart: RecognitionSmoother.add now mentions "
            "'offline' — it may have grown a downgrade guard this baseline "
            "does not yet know how to verify; do not assume the old absence"
        )
    if "settled" not in _extract_block(smoother_text, "class LiveRecognition {").lower() and \
            "this.settled" not in smoother_text:
        raise BaselineError(
            "live_recognition.dart: LiveRecognition no longer exposes a "
            "`settled` field — the fact this generator records about it is stale"
        )

    return {
        "livePathIsOnDeviceOnly": True,
        "settledLiveReadingHasNoOfflineDowngradeEquivalent": True,
        "settledLiveReadingsAreWrittenToHistory": True,
        "cloudConceptMentionsInCommentsOnly": commented_mentions,
        "note": "Live mode's `settled` state is the functional analogue of "
                "ScanOutcome.confident (persisted to recognition history the "
                "same way) but has no answeredOffline-style guard, because it "
                "is always on-device. Do not assume "
                "offlineFallbackNeverReportsConfident covers this path.",
    }


def _match_source_values() -> list[str]:
    text = _read(VISUAL_EQUIPMENT / "data" / "visual_equipment_match.dart")
    body = _extract_block(text, "enum MatchSource {")
    values = re.findall(r"^\s*([a-zA-Z][a-zA-Z0-9]*)\s*,?\s*(?://.*)?$", body, re.M)
    values = [v for v in values if v]
    if not values:
        raise BaselineError("visual_equipment_match.dart: could not parse MatchSource values")
    return values


def _text_anchor_runs_first() -> bool:
    """In `classifyFilePath`, `_anchorOnPrintedText` must be called, and its
    result checked, strictly before `service.classifyFile` — the ordering
    B5b's whole design rationale (measured: printed text beats the
    classifier 18-for-18 vs 5-of-18) depends on."""
    text = _read(VISUAL_EQUIPMENT / "state" / "visual_equipment_providers.dart")
    span = _extract_block_span(text, "Future<void> classifyFilePath(String path) async {")
    # CODE only. `body.find(...)` read a printed or interpolated mention as
    # the call itself, so a source whose real order is REVERSED could still
    # record the ordering this function claims to have measured.
    anchor_hits = _in_span(find_in(text, "_anchorOnPrintedText(", CODE_ONLY), span)
    classifier_hits = _in_span(find_in(text, "service.classifyFile(", CODE_ONLY), span)
    anchor_idx = anchor_hits[0] if anchor_hits else -1
    classifier_idx = classifier_hits[0] if classifier_hits else -1
    if anchor_idx == -1 or classifier_idx == -1:
        raise BaselineError(
            "visual_equipment_providers.dart: classifyFilePath no longer "
            "calls both _anchorOnPrintedText and service.classifyFile"
        )
    if not anchor_idx < classifier_idx:
        raise BaselineError(
            "visual_equipment_providers.dart: the text anchor no longer runs "
            "before the classifier in classifyFilePath"
        )
    return True


def _text_anchor_ambiguity_preserved() -> dict[str, bool]:
    """`matchMachineText` must still hand back a RANKED LIST rather than
    resolving ambiguity itself — one candidate when the text is
    unambiguous, several when it names more than one machine (never a
    silent "pick the first")."""
    text = _read(VISUAL_EQUIPMENT / "data" / "machine_text_anchor.dart")
    signature_ok = "List<TextAnchorMatch> matchMachineText(" in text
    single_branch_ok = "distinct.length == 1" in text
    multi_branch_ok = "distinct.length >= 3" in text
    two_branch_ok = "for (final id in distinct)" in text
    if not (signature_ok and single_branch_ok and multi_branch_ok and two_branch_ok):
        raise BaselineError(
            "machine_text_anchor.dart: matchMachineText no longer has the "
            "expected single/pair/triple-or-more branch structure"
        )
    return {
        "returnsRankedList": signature_ok,
        "singleUnambiguousMatchHandled": single_branch_ok,
        "threeOrMoreDistinctCollapsesToGeneric": multi_branch_ok,
        "exactlyTwoReturnedAsCandidates": two_branch_ok,
    }


def _hybrid_cloud_before_local() -> bool:
    """`HybridVisualEquipmentService.classifyFile` must try `cloud` before
    `local` — the on-device model is the FALLBACK, not a peer."""
    text = _read(VISUAL_EQUIPMENT / "data" / "gemini_equipment_service.dart")
    class_idx = text.find("class HybridVisualEquipmentService")
    if class_idx == -1:
        raise BaselineError(
            "gemini_equipment_service.dart: class HybridVisualEquipmentService not found"
        )
    span_start, span_end = _extract_block_span(
        text[class_idx:], "Future<List<VisualMatch>> classifyFile("
    )
    span = (class_idx + span_start, class_idx + span_end)
    # CODE only, same reason as `_text_anchor_runs_first`: this records a
    # call ORDER, and a printed mention of either call is not a call.
    cloud_hits = _in_span(find_in(text, "cloud.classifyFile(", CODE_ONLY), span)
    local_hits = _in_span(find_in(text, "local.classifyFile(", CODE_ONLY), span)
    cloud_idx = cloud_hits[0] if cloud_hits else -1
    local_idx = local_hits[0] if local_hits else -1
    if cloud_idx == -1 or local_idx == -1:
        raise BaselineError(
            "gemini_equipment_service.dart: HybridVisualEquipmentService no "
            "longer calls both cloud.classifyFile and local.classifyFile"
        )
    if not cloud_idx < local_idx:
        raise BaselineError(
            "gemini_equipment_service.dart: the on-device model is no "
            "longer tried strictly after the cloud recogniser"
        )
    return True


def _exact_identity_absent() -> dict[str, Any]:
    hits: list[dict[str, str]] = []
    for tree in SWEPT_TREES:
        for path in sorted(tree.rglob("*.dart")):
            text = _read(path)
            for token in EXACT_IDENTITY_TOKENS:
                if token in text:
                    hits.append({
                        "token": token,
                        "path": str(path.relative_to(REPO)).replace("\\", "/"),
                    })
    return {
        "tokensSwept": list(EXACT_IDENTITY_TOKENS),
        "treesSwept": [str(t.relative_to(REPO)).replace("\\", "/") for t in SWEPT_TREES],
        "hits": sort_by_key(hits, "token") if hits else [],
        "exactIdentityConceptsAbsent": len(hits) == 0,
    }


def _model_registry_entry(registry: dict[str, Any], model_id: str, version: str) -> dict[str, Any]:
    for m in registry.get("models", []):
        if m.get("model_id") == model_id and m.get("model_version") == version:
            return m
    raise BaselineError(f"MODEL_REGISTRY.json: no entry for {model_id}@{version}")


def _require(entry: dict[str, Any], key: str, model_ref: str) -> Any:
    """A missing registry key must fail the generator, not silently resolve
    to `None`/`False` — `dict.get(key)` with no default does exactly that
    (`bool(None) == False`, indistinguishable from a verified `false`), which
    an internal review caught producing a plausible-looking but unverified
    value for `bundled`/`champion`/`supports_unknown_or_abstain`."""
    if key not in entry:
        raise BaselineError(f"MODEL_REGISTRY.json: {model_ref} is missing required key {key!r}")
    return entry[key]


def build() -> dict[str, Any]:
    if not FUNCTIONAL_CATALOG.exists():
        raise BaselineError(f"functional catalog missing: {FUNCTIONAL_CATALOG}")
    if not MODEL_REGISTRY.exists():
        raise BaselineError(f"model registry missing: {MODEL_REGISTRY}")
    if not TFLITE_MODEL.exists():
        raise BaselineError(f"bundled TFLite model missing: {TFLITE_MODEL}")

    catalogue = json.loads(_read(FUNCTIONAL_CATALOG))
    if not isinstance(catalogue, list) or not catalogue:
        raise BaselineError("equipment.json is not a non-empty JSON array")
    ids = [item["id"] for item in catalogue]
    if len(ids) != len(set(ids)):
        raise BaselineError("equipment.json contains a duplicate equipment id")

    registry = json.loads(_read(MODEL_REGISTRY))
    v1 = _model_registry_entry(registry, "equipment_recognition", "v1")
    v2 = _model_registry_entry(registry, "equipment_recognition", "v2")

    actual_v1_hash = file_sha256(TFLITE_MODEL)
    actual_v1_bytes = TFLITE_MODEL.stat().st_size
    if actual_v1_hash != v1["artifact_sha256"]:
        raise BaselineError(
            "equipment_v1.tflite on disk does not match MODEL_REGISTRY's "
            f"artifact_sha256 ({actual_v1_hash} != {v1['artifact_sha256']})"
        )
    if actual_v1_bytes != v1["artifact_bytes"]:
        raise BaselineError(
            "equipment_v1.tflite on disk does not match MODEL_REGISTRY's "
            f"artifact_bytes ({actual_v1_bytes} != {v1['artifact_bytes']})"
        )
    v2_artifact_path = REPO / v2["artifact_path"] if not v2["artifact_path"].startswith("D:/") \
        else Path(v2["artifact_path"])
    v2_present_in_repo = v2_artifact_path.exists() and str(v2_artifact_path).startswith(str(REPO))

    scanner_contracts = sort_by_key(
        [
            {
                "path": path,
                "sha256": file_sha256(REPO / path),
                "role": role,
            }
            for path, role in SCANNER_CONTRACTS
        ],
        "path",
    )

    payload: dict[str, Any] = {
        "schemaVersion": SCHEMA_VERSION,
        "sourceCommit": _git_commit(),
        "generatedBy": "scripts/equipment_identity/recognition_baseline.py",
        "functionalCatalog": {
            "path": str(FUNCTIONAL_CATALOG.relative_to(REPO)).replace("\\", "/"),
            "sha256": file_sha256(FUNCTIONAL_CATALOG),
            "typeCount": len(ids),
        },
        "modelRegistry": {
            "path": str(MODEL_REGISTRY.relative_to(REPO)).replace("\\", "/"),
            "sha256": file_sha256(MODEL_REGISTRY),
        },
        "scannerContracts": scanner_contracts,
        "modelArtifacts": {
            "equipment_recognition@v1": {
                "artifactPath": v1["artifact_path"],
                "sha256": actual_v1_hash,
                "bytes": actual_v1_bytes,
                "registryVersion": "v1",
                "deploymentStatus": v1["deployment_status"],
                "bundledInApk": bool(_require(v1, "bundled", "equipment_recognition@v1")),
                "champion": bool(_require(v1, "champion", "equipment_recognition@v1")),
                "classCount": _require(v1, "class_count", "equipment_recognition@v1"),
                "supportsUnknownOrAbstain": bool(
                    _require(v1, "supports_unknown_or_abstain", "equipment_recognition@v1")
                ),
            },
            "equipment_recognition@v2": {
                "artifactPath": v2["artifact_path"],
                "registryVersion": "v2",
                "deploymentStatus": v2["deployment_status"],
                "bundledInApk": bool(_require(v2, "bundled", "equipment_recognition@v2")),
                "presentInThisRepoCheckout": v2_present_in_repo,
                "note": "NOT_SHIPPED per MODEL_REGISTRY.json — recorded here so "
                        "a future P1+ change cannot silently start treating v2 "
                        "as deployed without this baseline being regenerated.",
            },
        },
        "genericInvariants": {
            "scanOutcomeStates": _scan_outcome_states(),
            "matchSourceValues": _match_source_values(),
            "photoPathOfflineFallbackNeverReportsConfident": _offline_never_confident(),
            "liveMode": _live_mode_has_no_offline_downgrade_guard(),
            "textAnchorRunsBeforeClassifier": _text_anchor_runs_first(),
            "textAnchorAmbiguitySemantics": _text_anchor_ambiguity_preserved(),
            "hybridServiceTriesCloudBeforeOnDevice": _hybrid_cloud_before_local(),
            "exactIdentity": _exact_identity_absent(),
        },
    }
    return payload


def _raw_photo_dir_status() -> dict[str, Any]:
    """Never invent a hash for a directory this checkout does not have.

    The 30 raw photos live only on the operator's machine at the path B1
    records; this checkout has no copy. `rawContentHashes` is honestly
    `UNAVAILABLE_IN_THIS_CHECKOUT` rather than a fabricated value, and that
    absence does not fail P0.G1 — the gate binds to the recorded evaluation
    evidence (B1's own text) instead, per the plan's explicit instruction not
    to fail G1 solely for the raw files being absent.
    """
    present = Path(RAW_PHOTO_DIR_AS_RECORDED).exists()
    return {
        "recordedPath": RAW_PHOTO_DIR_AS_RECORDED,
        "presentInThisCheckout": present,
        "rawContentHashes": "UNAVAILABLE_IN_THIS_CHECKOUT" if not present else "NOT_COMPUTED",
    }


#: Parses B1's own markdown table rows into (groundTruthCell, prediction,
#: confidence) keyed by frame id — two shapes because the screenshot row
#: (`| скриншот \`140916\` | ... |`) is written differently from the three
#: dated-filename rows (`| \`20260730_135634\` | ... | **0.892** |`).
_B1_TABLE_ROW_RE = re.compile(
    r"\|\s*`(\d{8}_\d{6})`\s*\|\s*(.*?)\s*\|\s*`(\w+)`\s*\|\s*\*\*([\d.]+)\*\*\s*\|"
)
_B1_TABLE_SCREENSHOT_ROW_RE = re.compile(
    r"\|\s*скриншот\s*`(\d+)`\s*\|\s*(.*?)\s*\|\s*`(\w+)`\s*\|\s*([\d.]+)\s*\|"
)


def _parse_b1_table_rows(note_text: str) -> dict[str, tuple[str, str, float]]:
    rows: dict[str, tuple[str, str, float]] = {}
    for frame_id, ground_truth_cell, prediction, confidence in _B1_TABLE_ROW_RE.findall(note_text):
        rows[frame_id] = (ground_truth_cell, prediction, float(confidence))
    # B1's screenshot row is keyed by its bare filename suffix (`140916`),
    # not the full `Screenshot_20260806_140916` frame id used in
    # LEGACY_LABELED_FRAMES — `_verify_legacy_frames` strips the shared
    # prefix before looking a frame up here.
    for suffix, ground_truth_cell, prediction, confidence in _B1_TABLE_SCREENSHOT_ROW_RE.findall(note_text):
        rows[suffix] = (ground_truth_cell, prediction, float(confidence))
    return rows


def _verify_legacy_frames(note_text: str) -> None:
    """Cross-check the hand-transcribed `LEGACY_LABELED_FRAMES` table against
    B1's own text ROW BY ROW — not "does this value occur anywhere in the
    file", which would pass even if two rows' fields were transposed between
    frames sharing a `modelPrediction` (e.g. the two `treadmill` rows). Each
    frame's prediction and confidence are checked against ITS OWN parsed
    table row; ground truth is checked via `LEGACY_FRAME_GROUND_TRUTH_ANCHORS`'s
    literal-substring anchor against THAT row's ground-truth cell specifically
    (not the whole document), since `groundTruth` itself is an English gloss,
    not a quote, of the Russian/mixed source cell."""
    rows = _parse_b1_table_rows(note_text)
    if len(rows) < len(LEGACY_LABELED_FRAMES):
        raise BaselineError(
            f"legacy inventory: table-row parser found {len(rows)} rows in "
            f"{B1_MEASUREMENT_NOTE.name}, fewer than the "
            f"{len(LEGACY_LABELED_FRAMES)} frames this generator expects — "
            "the note's table shape may have changed"
        )

    for frame in LEGACY_LABELED_FRAMES:
        frame_id = frame["frameId"]
        lookup_key = frame_id.replace("Screenshot_20260806_", "") if frame_id.startswith("Screenshot_") else frame_id
        row = rows.get(lookup_key) or rows.get(frame_id)
        if row is None:
            raise BaselineError(
                f"legacy inventory: no table row for frame {frame_id!r} found in "
                f"{B1_MEASUREMENT_NOTE.name} — transcription no longer matches source"
            )
        ground_truth_cell, row_prediction, row_confidence = row

        if row_prediction != frame["modelPrediction"]:
            raise BaselineError(
                f"legacy inventory: frame {frame_id!r} row says model predicted "
                f"{row_prediction!r}, LEGACY_LABELED_FRAMES says "
                f"{frame['modelPrediction']!r} — transcription drifted from source"
            )
        if row_confidence != frame["modelConfidence"]:
            raise BaselineError(
                f"legacy inventory: frame {frame_id!r} row says confidence "
                f"{row_confidence}, LEGACY_LABELED_FRAMES says "
                f"{frame['modelConfidence']} — transcription drifted from source"
            )
        anchor = LEGACY_FRAME_GROUND_TRUTH_ANCHORS.get(frame_id)
        if anchor is None:
            raise BaselineError(
                f"legacy inventory: frame {frame_id!r} has no entry in "
                "LEGACY_FRAME_GROUND_TRUTH_ANCHORS — ground truth cannot be verified"
            )
        if anchor not in ground_truth_cell:
            raise BaselineError(
                f"legacy inventory: ground-truth anchor {anchor!r} for frame "
                f"{frame_id!r} not found in that frame's OWN table row "
                f"({ground_truth_cell!r}) in {B1_MEASUREMENT_NOTE.name} — "
                "transcription drifted from source or rows were transposed"
            )


def build_legacy_inventory() -> dict[str, Any]:
    """P0.G1 §6.2 — classify the operator's 30 real-gym photos as a frozen
    regression/reference set, never a training set, per B1's own explicit
    conclusion (`B1_RECOGNITION_MEASUREMENT_2026-08-07.md` closing note:
    "эти 30 фото — тест, не обучающая выборка")."""
    if not B1_MEASUREMENT_NOTE.exists():
        raise BaselineError(f"B1 measurement note missing: {B1_MEASUREMENT_NOTE}")

    note_text = _read(B1_MEASUREMENT_NOTE)
    _verify_legacy_frames(note_text)

    payload: dict[str, Any] = {
        "schemaVersion": LEGACY_INVENTORY_SCHEMA_VERSION,
        "sourceCommit": _git_commit(),
        "generatedBy": "scripts/equipment_identity/recognition_baseline.py",
        "datasetRole": "LEGACY_REAL_GYM_REGRESSION",
        "trainingAllowed": False,
        "sealedBlindEvaluation": False,
        "promotionHoldout": False,
        "evidenceBasis": {
            "sourceDoc": str(B1_MEASUREMENT_NOTE.relative_to(REPO)).replace("\\", "/"),
            "sourceDocSha256": file_sha256(B1_MEASUREMENT_NOTE),
            "note": "This inventory binds to B1's recorded evaluation text, not "
                    "to the raw photo directory, which this checkout does not have.",
        },
        "rawPhotoSet": {
            **_raw_photo_dir_status(),
            "recordedFrameCount": 30,
            "capturedOn": ["2026-07-30", "2026-08-06"],
        },
        "labeledFrames": sort_by_key(list(LEGACY_LABELED_FRAMES), "frameId"),
        "measurementSummary": {
            "modelEvaluated": "equipment_recognition@v1 (equipment_v1.tflite, the bundled APK model)",
            "classCount": 10,
            "top1BelowRandomChance": 0,
            "top1ConfidenceMin": 0.215,
            "top1ConfidenceMedian": 0.437,
            "top1ConfidenceMax": 0.897,
            "conclusion": "None of the labeled machines are among the 10 trained "
                          "classes; the model reports a confident wrong answer "
                          "rather than abstaining, and a confidence threshold "
                          "does not fix this (min observed confidence 0.215 is "
                          "still above both deployed thresholds of 0.05 and 0.10).",
        },
    }
    return payload


def _write_or_check(
    build_fn: Any,
    out_path: Path,
    label: str,
    args: argparse.Namespace,
) -> tuple[int, dict[str, Any] | None]:
    try:
        payload = build_fn()
    except BaselineError as e:
        print(f"{label} generation failed: {e}", file=sys.stderr)
        return 1, None

    text = dump_pretty(payload)
    path = out_path if args.out is None else Path(args.out)

    if args.check:
        if not path.exists():
            print(f"{path} does not exist; run with --write", file=sys.stderr)
            return 1, None
        committed = json.loads(path.read_text(encoding="utf-8"))
        fresh = json.loads(text)
        committed.pop("sourceCommit", None)
        fresh.pop("sourceCommit", None)
        if committed != fresh:
            print(
                f"{path.name} does not match what the source actually says. "
                "Either the underlying source changed without this artefact "
                "being regenerated, or the file was hand-edited.",
                file=sys.stderr,
            )
            return 1, None
        print(f"{label} matches (payload sha256 {payload_sha256(payload)})")
        return 0, payload

    if args.write:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(text, encoding="utf-8")
        print(f"-> {path}")

    return 0, payload


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--write", action="store_true")
    ap.add_argument("--check", action="store_true")
    ap.add_argument(
        "--target",
        choices=("baseline", "legacy", "all"),
        default="all",
        help="baseline=recognition_baseline_v1.json, "
             "legacy=legacy_real_gym_regression_inventory.json, all=both (default)",
    )
    ap.add_argument(
        "--out", default=None,
        help="override output path; only valid with --target baseline|legacy",
    )
    args = ap.parse_args(argv)

    if args.out is not None and args.target == "all":
        print("--out requires --target baseline or --target legacy", file=sys.stderr)
        return 1

    targets = []
    if args.target in ("baseline", "all"):
        targets.append((build, OUT, "recognition_baseline_v1.json"))
    if args.target in ("legacy", "all"):
        targets.append((build_legacy_inventory, OUT_LEGACY_INVENTORY, "legacy_real_gym_regression_inventory.json"))

    rc = 0
    baseline_payload = None
    for build_fn, out_path, label in targets:
        target_rc, payload = _write_or_check(build_fn, out_path, label, args)
        rc = target_rc or rc
        if build_fn is build:
            baseline_payload = payload

    if rc == 0 and baseline_payload is not None:
        print(f"scannerContracts: {len(baseline_payload['scannerContracts'])} files")
        print(f"exact identity concepts absent: "
              f"{baseline_payload['genericInvariants']['exactIdentity']['exactIdentityConceptsAbsent']}")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
