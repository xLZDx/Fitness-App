"""B1 steps 2 and 7 -- the trusted candidate-document manifest and its resolver.

WHY THE MANIFEST OWNS THE METADATA
----------------------------------
A caller may name a `(sourceId, candidateDocId)` pair. A caller may never supply
the document URL, the declared media type, the allowed final URLs or the identity
expectations. If it could, the identity guard would check the caller's
expectation against the caller's own document and prove nothing at all -- a
tautology wearing the shape of a check.

So `resolve_candidate` is the only door a document enters through, and everything
it returns comes from this file.

WHAT THE SCHEMA REFUSES TO BE ABLE TO SAY
-----------------------------------------
* **Which document governs.** `operative` is UNREPRESENTABLE, not merely unset:
  the validator rejects the field outright. That is a legal conclusion, it
  belongs to a human, and making it unrepresentable means promoting a document
  requires a visible manifest diff rather than a quiet boolean.
* **What an unopened document contains.** `observationState=NOT_OBSERVED` forbids
  `identityExpectations` entirely. Registering a document that exists is honest;
  describing its contents unseen is the precise defect that produced this gate.

THE candidateDocId GRAMMAR, AND WHY IT NEEDS NO TRAVERSAL GUARD
---------------------------------------------------------------
``^[a-z0-9][a-z0-9_-]*(?![\\s\\S])``

The proof is STRUCTURAL, and it has to be, because the language is unbounded --
no finite corpus can establish a property over infinitely many strings, and
calling one "exhaustive" would be a claim wider than its evidence in the very
place built to prevent that.

The argument instead reads off the alphabet. The first character is drawn from
``[a-z0-9]`` and every later one from ``[a-z0-9_-]``. Therefore ``.``, ``/``,
``\\``, ``:``, whitespace and newline are **unrepresentable at any length**, and
so ``.``, ``..``, path separators, drive letters, UNC prefixes and NTFS
alternate-data-stream colons cannot be accepted -- for every string in the
language, not for some sample of it. Finite boundary tests back the argument;
they do not constitute it. Any generated set of strings is a *boundary corpus*
and is called that everywhere it appears.

The terminator is ``(?![\\s\\S])`` rather than ``$`` deliberately: Python's ``$``
also matches just before a trailing newline, so ``"terms_of_use\\n"`` would
validate under ``$`` and then reach a filesystem path. The same file records
that mistake in `rights.py` for `_SOURCE_ID_RE`, which still carries it.

**What this does NOT remove:** resolved-path containment, which stays a separate
guard with its own fixture wherever a path is built. `rights.py` lines 176-179
record why the two are different -- its own `SNAPSHOT_PATH_PATTERN` deliberately
does not reject ``..``, because ``..`` matches ITS component alphabet. Mine is
narrower, so the identifier needs no traversal guard; a resolved path still does.
"""

from __future__ import annotations

import copy
import json
import pathlib
import re
from typing import Any

from terms_acquisition import B1_TARGET_SOURCE_IDS, P0_DIR

CANDIDATES_PATH = P0_DIR / "terms_candidates.json"

#: See the module docstring for the structural argument this expresses.
CANDIDATE_DOC_ID_PATTERN = r"^[a-z0-9][a-z0-9_-]*(?![\s\S])"
_CANDIDATE_DOC_ID_RE = re.compile(CANDIDATE_DOC_ID_PATTERN)

OBSERVATION_STATES: frozenset[str] = frozenset({"OBSERVED", "NOT_OBSERVED"})

#: Fields that would let the manifest declare a legal conclusion. Rejected by
#: name so the answer to "can this file say which document governs?" is no,
#: rather than "not currently".
FORBIDDEN_CANDIDATE_FIELDS: frozenset[str] = frozenset({
    "operative", "isOperative", "governing", "isGoverning",
    "authoritative", "applies", "legalReviewState", "termsCaptured",
})


class CandidateManifestError(Exception):
    """A candidate manifest that claims something it may not, or cannot support."""


def load_candidates(path: pathlib.Path | None = None) -> dict[str, Any]:
    target = CANDIDATES_PATH if path is None else path
    try:
        raw = target.read_bytes()
    except FileNotFoundError as exc:
        raise CandidateManifestError(f"candidate manifest not found at {target}") from exc
    try:
        return json.loads(raw.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise CandidateManifestError(f"{target}: not valid UTF-8 JSON -- {exc}") from exc


def is_valid_candidate_doc_id(value: Any) -> bool:
    """True when `value` is in the candidateDocId language. Total, never raises."""
    return isinstance(value, str) and _CANDIDATE_DOC_ID_RE.match(value) is not None


def _require_text(value: Any, context: str, field: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise CandidateManifestError(
            f"{context}: {field} must be a non-empty string, got {value!r}"
        )
    return value


def _require_https_list(value: Any, context: str, field: str) -> list[str]:
    if not isinstance(value, list) or not value:
        raise CandidateManifestError(f"{context}: {field} must be a non-empty list")
    for item in value:
        _require_text(item, context, f"{field} entry")
        if not item.startswith("https://"):
            raise CandidateManifestError(
                f"{context}: {field} entry {item!r} is not https -- a plaintext target is a "
                "downgrade the manifest must not be able to express"
            )
    return value


def _validate_candidate(entry: Any, context: str) -> str:
    if not isinstance(entry, dict):
        raise CandidateManifestError(f"{context}: each candidate must be an object")

    present = FORBIDDEN_CANDIDATE_FIELDS & set(entry)
    if present:
        raise CandidateManifestError(
            f"{context}: candidate carries {sorted(present)}, which would declare a legal "
            "conclusion. This manifest records what a document IS, never what it permits or "
            "whether it governs -- the field is refused, not merely left unset"
        )

    doc_id = entry.get("candidateDocId")
    if not is_valid_candidate_doc_id(doc_id):
        raise CandidateManifestError(
            f"{context}: candidateDocId {doc_id!r} does not match "
            f"{CANDIDATE_DOC_ID_PATTERN} -- the alphabet excludes '.', '/', '\\\\', ':' and "
            "whitespace, so traversal and drive forms are unrepresentable rather than filtered"
        )
    context = f"{context} ({doc_id})"

    _require_https_list(entry.get("documentUrls"), context, "documentUrls")
    _require_https_list(entry.get("allowedFinalUrls"), context, "allowedFinalUrls")

    media = entry.get("declaredMediaTypes")
    if not isinstance(media, list) or not media:
        raise CandidateManifestError(
            f"{context}: declaredMediaTypes must be a non-empty list -- a capture whose type "
            "nothing declares can only be validated against the caller's own claim"
        )
    for item in media:
        _require_text(item, context, "declaredMediaTypes entry")

    state = _require_text(entry.get("observationState"), context, "observationState")
    if state not in OBSERVATION_STATES:
        raise CandidateManifestError(
            f"{context}: observationState must be one of {sorted(OBSERVATION_STATES)}, "
            f"got {state!r}"
        )
    _validate_observation_state(entry, state, context)
    return doc_id


def _validate_observation_state(entry: dict[str, Any], state: str, context: str) -> None:
    """An unopened document may not be described. The rule this gate exists for."""
    expectations = entry.get("identityExpectations")

    if state == "NOT_OBSERVED":
        if expectations is not None:
            raise CandidateManifestError(
                f"{context}: observationState=NOT_OBSERVED but identityExpectations are "
                "recorded -- nobody opened this document, so anything said about its "
                "contents was invented rather than seen"
            )
        for field in ("observedAtUtc", "observationMethod"):
            if entry.get(field) is not None:
                raise CandidateManifestError(
                    f"{context}: observationState=NOT_OBSERVED but {field}="
                    f"{entry[field]!r} claims an observation happened"
                )
        return

    # OBSERVED
    _require_text(entry.get("observedAtUtc"), context, "observedAtUtc")
    _require_text(entry.get("observationMethod"), context, "observationMethod")
    if not isinstance(expectations, dict):
        raise CandidateManifestError(
            f"{context}: observationState=OBSERVED requires identityExpectations -- a "
            "document that was opened and produced no checkable expectation gives the "
            "identity guard nothing to check"
        )
    markers = expectations.get("requiredMarkers")
    if not isinstance(markers, list) or not markers:
        raise CandidateManifestError(
            f"{context}: identityExpectations.requiredMarkers must be a non-empty list -- "
            "an empty marker set makes the identity guard vacuously true"
        )
    for item in markers:
        _require_text(item, context, "requiredMarkers entry")


def _validate_source(entry: Any, index: int) -> str:
    context = f"sources[{index}]"
    if not isinstance(entry, dict):
        raise CandidateManifestError(f"{context}: must be an object")
    source_id = _require_text(entry.get("sourceId"), context, "sourceId")
    context = f"sources[{index}] ({source_id})"

    candidates = entry.get("candidates")
    if not isinstance(candidates, list):
        raise CandidateManifestError(f"{context}: candidates must be a list")

    seen = [_validate_candidate(item, context) for item in candidates]
    duplicates = {d for d in seen if seen.count(d) > 1}
    if duplicates:
        raise CandidateManifestError(
            f"{context}: duplicate candidateDocId(s) {sorted(duplicates)} -- identity is "
            "(sourceId, candidateDocId), so two rows for one pair make resolution depend "
            "on order, and order is not a rule"
        )

    reason = entry.get("noCandidatesReason")
    if not candidates and not (isinstance(reason, str) and reason.strip()):
        raise CandidateManifestError(
            f"{context}: a source with no candidates must record noCandidatesReason -- "
            "otherwise a later reader cannot tell 'none found' from 'nobody looked'"
        )
    if candidates and reason is not None:
        raise CandidateManifestError(
            f"{context}: noCandidatesReason={reason!r} is recorded beside "
            f"{len(candidates)} candidate(s) -- both cannot be true"
        )
    return source_id


def validate_candidates(manifest: Any, *, expect_targets: bool = True) -> None:
    """Validate a candidate manifest, raising on the first fault."""
    if not isinstance(manifest, dict):
        raise CandidateManifestError("candidate manifest must be a JSON object")
    if manifest.get("manifestKind") != "TERMS_CANDIDATE_DOCUMENTS":
        raise CandidateManifestError(
            f"manifestKind must be TERMS_CANDIDATE_DOCUMENTS, "
            f"got {manifest.get('manifestKind')!r}"
        )

    sources = manifest.get("sources")
    if not isinstance(sources, list) or not sources:
        raise CandidateManifestError("sources must be a non-empty list")

    seen = [_validate_source(entry, index) for index, entry in enumerate(sources)]
    duplicates = {s for s in seen if seen.count(s) > 1}
    if duplicates:
        raise CandidateManifestError(f"duplicate sourceId(s): {sorted(duplicates)}")

    if expect_targets and set(seen) != set(B1_TARGET_SOURCE_IDS):
        missing = sorted(set(B1_TARGET_SOURCE_IDS) - set(seen))
        extra = sorted(set(seen) - set(B1_TARGET_SOURCE_IDS))
        raise CandidateManifestError(
            f"manifest must cover exactly the B1 targets; missing={missing} extra={extra}"
        )


def resolve_candidate(
    source_id: str,
    candidate_doc_id: str,
    manifest: dict[str, Any] | None = None,
) -> dict[str, Any]:
    """Return the trusted record for one pair, or raise.

    The ONLY way a document enters an operation. Returns a deep copy: the caller
    receives data it cannot use to edit the trusted record, because a resolver
    that hands out a live reference is a writer wearing a reader's name.
    """
    if not is_valid_candidate_doc_id(candidate_doc_id):
        raise CandidateManifestError(
            f"candidateDocId {candidate_doc_id!r} does not match {CANDIDATE_DOC_ID_PATTERN}"
        )

    doc = load_candidates() if manifest is None else manifest
    for source in doc.get("sources", []):
        if source.get("sourceId") != source_id:
            continue
        for candidate in source.get("candidates", []):
            if candidate.get("candidateDocId") == candidate_doc_id:
                return copy.deepcopy(candidate)
        raise CandidateManifestError(
            f"source {source_id!r} has no candidate {candidate_doc_id!r} -- a document this "
            "manifest never registered cannot be captured, however well-formed the request"
        )
    raise CandidateManifestError(f"no source {source_id!r} in the candidate manifest")


def main() -> int:
    manifest = load_candidates()
    try:
        validate_candidates(manifest)
    except CandidateManifestError as exc:
        print(f"CANDIDATE MANIFEST INVALID: {exc}")
        return 1
    total = 0
    for source in manifest["sources"]:
        candidates = source["candidates"]
        total += len(candidates)
        if not candidates:
            print(f"  {source['sourceId']:48s} (none) -- {source['noCandidatesReason'][:60]}...")
            continue
        for candidate in candidates:
            print(
                f"  {source['sourceId']:48s} {candidate['candidateDocId']:28s} "
                f"{candidate['observationState']}"
            )
    print(f"candidate manifest valid: {total} candidate document(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
